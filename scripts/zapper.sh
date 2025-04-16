#!/bin/bash
# Script: zapper.sh

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/AppImage-or-archive"
    exit 1
fi

APPFILE="$1"

if [ ! -f "$APPFILE" ]; then
    echo "File '$APPFILE' does not exist."
    exit 1
fi

read -p "Enter the folder name for the zapp (e.g., endless-sky): " folder_name

if [ -z "$folder_name" ]; then
    echo "Folder name cannot be empty."
    exit 1
fi

DEST_DIR="$HOME/zapps/$folder_name"
mkdir -p "$DEST_DIR"
MAIN_EXE=""

if [[ "$APPFILE" == *.AppImage ]]; then
    mv "$APPFILE" "$DEST_DIR/zapp.AppImage"
    chmod +x "$DEST_DIR/zapp.AppImage"
    echo "AppImage has been prepared in '$DEST_DIR/zapp.AppImage'."
    MAIN_EXE="zapp.AppImage"
elif [[ "$APPFILE" == *.tar.xz ]]; then
    tar -xf "$APPFILE" -C "$DEST_DIR"
    echo "tar.xz archive has been extracted in '$DEST_DIR'."
elif [[ "$APPFILE" == *.tar.gz ]]; then
    tar -xzf "$APPFILE" -C "$DEST_DIR"
    echo "tar.gz archive has been extracted in '$DEST_DIR'."
else
    echo "Unsupported file type."
    exit 1
fi

if [[ -z "$MAIN_EXE" ]]; then
    mapfile -t exes < <(find "$DEST_DIR" -maxdepth 2 -type f -executable)
    exe_count=${#exes[@]}

    if [[ $exe_count -eq 0 ]]; then
        echo "No executable file found in '$DEST_DIR'."
    elif [[ $exe_count -eq 1 ]]; then
        MAIN_EXE=$(realpath --relative-to="$DEST_DIR" "${exes[0]}")
        echo "Identified main executable: $(basename "$MAIN_EXE")"
    else
        echo "Multiple executables found:"
        declare -A exe_map
        letters=({a..z})
        counter=0
        for exe in "${exes[@]}"; do
            key="${letters[$counter]}"
            exe_map["$key"]="$exe"
            exe_name=$(basename "$exe")
            echo "  [$key] $exe_name"
            ((counter++))
        done
        read -p "Enter the letter of the main executable: " exe_choice
        if [[ -n "${exe_map[$exe_choice]}" ]]; then
            MAIN_EXE=$(realpath --relative-to="$DEST_DIR" "${exe_map[$exe_choice]}")
        else
            echo "Invalid selection. No markdown or desktop entry created."
        fi
    fi
fi

# Icon selection logic adjusted to look one level down relative to main exec
if [[ -n "$MAIN_EXE" ]]; then
    MAIN_EXE_DIR=$(dirname "$DEST_DIR/$MAIN_EXE")
    mapfile -t icons < <(find "$MAIN_EXE_DIR" -maxdepth 2 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.ico' -o -iname '*.icns' \))
else
    icons=()
fi

icon_count=${#icons[@]}

if [[ $icon_count -eq 1 ]]; then
    ICON_PATH=$(realpath "${icons[0]}")
elif [[ $icon_count -gt 1 ]]; then
    echo "Multiple icon/image files found:"
    declare -A icon_map
    letters=({a..z})
    counter=0
    for ico in "${icons[@]}"; do
        key="${letters[$counter]}"
        icon_map["$key"]="$ico"
        ico_name=$(basename "$ico")
        echo "  [$key] $ico_name"
        ((counter++))
    done
    read -p "Enter the letter of the icon you want to use: " icon_choice
    if [[ -n "${icon_map[$icon_choice]}" ]]; then
        ICON_PATH=$(realpath "${icon_map[$icon_choice]}")
    else
        echo "Invalid selection. Defaulting to utilities-terminal."
        ICON_PATH="utilities-terminal"
    fi
else
    ICON_PATH="utilities-terminal"
fi

if [[ -n "$MAIN_EXE" ]]; then
    echo "$MAIN_EXE" > "$DEST_DIR/zapp.md"
    echo "Registered main executable: $MAIN_EXE"

    DESKTOP_ENTRY_PATH="$HOME/.local/share/applications/zapp-$folder_name.desktop"
    mkdir -p "$(dirname "$DESKTOP_ENTRY_PATH")"

    ABS_MAIN_EXE=$(realpath "$DEST_DIR/$MAIN_EXE")

    cat > "$DESKTOP_ENTRY_PATH" <<EOF
[Desktop Entry]
Type=Application
Name=$folder_name
Comment=Installed with zapper
Exec=sh -c 'chmod +x "\$1" && exec "\$1" >> "\$HOME/.local/share/zapper-launch.log" 2>&1' sh "$ABS_MAIN_EXE"
Icon=$ICON_PATH
Terminal=false
Categories=Utility;
StartupNotify=true
EOF

    chmod +x "$DESKTOP_ENTRY_PATH"
    update-desktop-database ~/.local/share/applications/ &> /dev/null
    echo "Desktop entry created at: $DESKTOP_ENTRY_PATH"
    echo "You can now search for '$folder_name' in your app launcher."
else
    echo "No executable registered — skipping .desktop creation."
fi
