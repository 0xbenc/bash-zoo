#!/bin/bash
set -euo pipefail
# Script: zapp.sh
# Description:
#   Lists folders under "$HOME/zapps" and launches the selected app.
#   Order of preference per app folder:
#     1) Run zapp.AppImage if present
#     2) If zapp.md exists, run the relative executable it names
#     3) Fallback: find executable files (in folder or its single subdir) and prompt

ZAPPS_DIR="$HOME/zapps"

ensure_gum() {
  if command -v gum >/dev/null 2>&1; then return 0; fi
  echo "gum is required but not installed. Install it via Homebrew (brew install gum)." >&2
  exit 1
}

if [[ ! -d "$ZAPPS_DIR" ]]; then
  echo "Directory '$ZAPPS_DIR' does not exist."
  exit 1
fi

ensure_gum

folders=()
while IFS= read -r -d '' d; do
  folders+=("$d")
done < <(find "$ZAPPS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

if [[ ${#folders[@]} -eq 0 ]]; then
  echo "No zapp folders found in '$ZAPPS_DIR'."
  exit 1
fi

folder_labels=()
for folder in "${folders[@]}"; do
  base=$(basename "$folder")
  short_path=${folder/#$HOME/~}
  folder_labels+=("$base  —  $short_path")
done

selection=$(printf '%s\n' "${folder_labels[@]}" | gum choose --header "Select a zapp to launch" --height 20) || {
  echo "No selection made. Exiting."
  exit 1
}

sel_idx=-1
for i in "${!folder_labels[@]}"; do
  if [[ "${folder_labels[$i]}" == "$selection" ]]; then
    sel_idx=$i
    break
  fi
done

if [[ $sel_idx -lt 0 ]]; then
  echo "Selection could not be resolved. Exiting."
  exit 1
fi

selected_folder="${folders[$sel_idx]}"
folder_basename=$(basename "$selected_folder")

# 1) zapp.AppImage
if [[ -f "$selected_folder/zapp.AppImage" ]]; then
  app="$selected_folder/zapp.AppImage"
  if [[ ! -x "$app" ]]; then
    echo "File '$app' is not executable."
    exit 1
  fi
  echo "Running $folder_basename using zapp.AppImage..."
  exec "$app"
fi

# 2) zapp.md (relative path)
zapp_md="$selected_folder/zapp.md"
if [[ -f "$zapp_md" ]]; then
  rel_path=$(head -n 1 "$zapp_md" | tr -d '\r\n')
  if [[ -n "$rel_path" ]]; then
    main_exe="$selected_folder/$rel_path"
    if [[ -x "$main_exe" ]]; then
      echo "Running $folder_basename using registered executable: $(basename "$main_exe")..."
      exec "$main_exe"
    else
      echo "Executable from zapp.md not found or not executable: $main_exe"
    fi
  fi
fi

# 3) Fallback: discover executables
search_dir="$selected_folder"
subdir_count=0
only_sub=""
while IFS= read -r -d '' sub; do
  only_sub="$sub"
  subdir_count=$((subdir_count+1))
done < <(find "$selected_folder" -mindepth 1 -maxdepth 1 -type d -print0)
if [[ $subdir_count -eq 1 ]]; then
  search_dir="$only_sub"
fi

executables=()
while IFS= read -r -d '' f; do
  executables+=("$f")
done < <(find "$search_dir" -maxdepth 1 -type f \( -perm -u+x -o -perm -g+x -o -perm -o+x \) -print0)

exe_count=${#executables[@]}
if [[ $exe_count -eq 0 ]]; then
  echo "No executable file found in '$search_dir'."
  exit 1
elif [[ $exe_count -eq 1 ]]; then
  echo "Running $(basename "$search_dir") using $(basename "${executables[0]}")..."
  exec "${executables[0]}"
else
  exe_labels=()
  for exe in "${executables[@]}"; do
    exe_labels+=("$(basename "$exe")  —  ${exe/#$HOME/~}")
  done
  exe_selection=$(printf '%s\n' "${exe_labels[@]}" | gum choose --header "Select executable in $folder_basename" --height 15) || {
    echo "No executable selected. Exiting."
    exit 1
  }
  pick=-1
  for i in "${!exe_labels[@]}"; do
    if [[ "${exe_labels[$i]}" == "$exe_selection" ]]; then
      pick=$i
      break
    fi
  done
  if [[ $pick -lt 0 ]]; then
    echo "Executable selection could not be resolved. Exiting."
    exit 1
  fi
  echo "Running $(basename "${executables[$pick]}")..."
  exec "${executables[$pick]}"
fi
