#!/bin/bash
# Script: zapper.sh
# Description:
#   This script takes an AppImage, a .tar.xz file, or a .tar.gz file as an argument,
#   asks for a folder name, creates a dedicated folder under $HOME/zapps with that name,
#   moves the AppImage into that folder (renamed as "zapp.AppImage") and sets it to be executable,
#   or extracts the archive into that folder.
#
#   If installing from an archive and multiple executables are found,
#   the user is prompted to identify the "main program". The script then creates a
#   markdown file (zapp.md) inside the new zapp folder storing the relative path to
#   the main executable and creates a .desktop entry in the application launcher.
#
# Usage:
#   ./zapper.sh /path/to/Your-App.AppImage
#   ./zapper.sh /path/to/Your-App.tar.xz
#   ./zapper.sh /path/to/Your-App.tar.gz

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
        letters=( {a..z} )
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

if [[ -n "$MAIN_EXE" ]]; then
    echo "$MAIN_EXE" > "$DEST_DIR/zapp.md"
    echo "Registered main executable: $MAIN_EXE"

    DESKTOP_ENTRY_PATH="$HOME/.local/share/applications/zapp-$folder_name.desktop"
    mkdir -p "$(dirname "$DESKTOP_ENTRY_PATH")"

    ABS_MAIN_EXE=$(realpath "$DEST_DIR/$MAIN_EXE")
    ICON_PATH="$DEST_DIR/icon.png"
    if [ -f "$ICON_PATH" ]; then
        ICON_LINE="Icon=$(realpath "$ICON_PATH")"
    else
        ICON_LINE="Icon=utilities-terminal"
    fi

    cat > "$DESKTOP_ENTRY_PATH" <<EOF
[Desktop Entry]
Type=Application
Name=$folder_name
Comment=Installed with zapper.sh
Exec=sh -c 'chmod +x "\$1" && exec "\$1" >> "\$HOME/.local/share/zapper-launch.log" 2>&1' sh "$ABS_MAIN_EXE"
$ICON_LINE
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
