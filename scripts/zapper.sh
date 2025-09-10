#!/bin/bash
set -euo pipefail
# Script: zapper.sh

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/AppImage-or-archive"
  exit 1
fi

APPFILE="$1"

if [[ ! -f "$APPFILE" ]]; then
  echo "File '$APPFILE' does not exist."
  exit 1
fi

read -r -p "Enter the folder name for the zapp (e.g., endless-sky): " folder_name

if [[ -z "$folder_name" ]]; then
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
  exes=()
  while IFS= read -r -d '' exe; do
    exes+=("$exe")
  done < <(find "$DEST_DIR" -maxdepth 2 -type f \( -perm -u+x -o -perm -g+x -o -perm -o+x \) -print0)
  exe_count=${#exes[@]}

  if [[ $exe_count -eq 0 ]]; then
    echo "No executable file found in '$DEST_DIR'."
  elif [[ $exe_count -eq 1 ]]; then
    MAIN_EXE="${exes[0]#"$DEST_DIR"/}"
    echo "Identified main executable: $(basename "$MAIN_EXE")"
  else
    echo "Multiple executables found:"
    letters=({a..z})
    for i in "${!exes[@]}"; do
      echo "  [${letters[$i]}] $(basename "${exes[$i]}")"
      if [[ $i -ge 25 ]]; then break; fi
    done
    read -r -p "Enter the letter of the main executable: " exe_choice
    pick=-1
    for i in "${!exes[@]}"; do
      if [[ "$exe_choice" == "${letters[$i]}" ]]; then pick=$i; break; fi
      if [[ $i -ge 25 ]]; then break; fi
    done
    if [[ $pick -ge 0 ]]; then
      MAIN_EXE="${exes[$pick]#"$DEST_DIR"/}"
    else
      echo "Invalid selection. No markdown or desktop entry created."
    fi
  fi
fi

# Icon selection logic adjusted to look one level down relative to main exec
if [[ -n "$MAIN_EXE" ]]; then
  MAIN_EXE_DIR=$(dirname "$DEST_DIR/$MAIN_EXE")
  icons=()
  while IFS= read -r -d '' ico; do
    icons+=("$ico")
  done < <(find "$MAIN_EXE_DIR" -maxdepth 2 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.ico' -o -iname '*.icns' \) -print0)
else
  icons=()
fi

icon_count=${#icons[@]}

if [[ $icon_count -eq 1 ]]; then
  ICON_PATH="${icons[0]}"
elif [[ $icon_count -gt 1 ]]; then
  echo "Multiple icon/image files found:"
  letters=({a..z})
  for i in "${!icons[@]}"; do
    echo "  [${letters[$i]}] $(basename "${icons[$i]}")"
    if [[ $i -ge 25 ]]; then break; fi
  done
  read -r -p "Enter the letter of the icon you want to use: " icon_choice
  ipick=-1
  for i in "${!icons[@]}"; do
    if [[ "$icon_choice" == "${letters[$i]}" ]]; then ipick=$i; break; fi
    if [[ $i -ge 25 ]]; then break; fi
  done
  if [[ $ipick -ge 0 ]]; then
    ICON_PATH="${icons[$ipick]}"
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

  ABS_MAIN_EXE="$DEST_DIR/$MAIN_EXE"
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
  update-desktop-database ~/.local/share/applications/ &> /dev/null || true
  echo "Desktop entry created at: $DESKTOP_ENTRY_PATH"
  echo "You can now search for '$folder_name' in your app launcher."
else
  echo "No executable registered — skipping .desktop creation."
fi
