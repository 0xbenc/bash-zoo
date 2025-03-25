#!/bin/bash
# Script: azap.sh
# Description:
#   This script lists folders one level down from the '$HOME/zapps' directory,
#   assigns each a unique key (a, b, c, …), and waits for the user to input
#   a key. When a valid key is entered, it will:
#     - Run the 'zapp.AppImage' if it exists in the selected folder, or
#     - Search for executable files (in the folder or its single subdirectory) and run one.
#
# Usage:
#   ./azap.sh

# Set the directory containing the zapp folders
ZAPPS_DIR="$HOME/zapps"

# Check if the zapps directory exists
if [[ ! -d "$ZAPPS_DIR" ]]; then
    echo "Directory '$ZAPPS_DIR' does not exist."
    exit 1
fi

# Declare an associative array to map keys to folder paths.
declare -A folder_map

# Array of letters for unique keys.
letters=( {a..z} )

echo "Available zapps:"
counter=0
# Loop through each item one level down in ZAPPS_DIR.
for folder in "$ZAPPS_DIR"/*; do
    if [[ -d "$folder" ]]; then
        key="${letters[$counter]}"
        folder_map["$key"]="$folder"
        folder_name=$(basename "$folder")
        echo "  [$key] $folder_name"
        ((counter++))
    fi
done

# Check if any folders were found.
if [[ $counter -eq 0 ]]; then
    echo "No zapp folders found in '$ZAPPS_DIR'."
    exit 1
fi

# Prompt the user to choose a zapp by its key.
read -p "Enter the letter corresponding to the zapp you want to run: " user_key

# Validate the user's input.
if [[ -z "${folder_map[$user_key]}" ]]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

# Retrieve the selected folder.
selected_folder="${folder_map[$user_key]}"

# First, check if there's a 'zapp.AppImage' file.
if [[ -f "$selected_folder/zapp.AppImage" ]]; then
    APPIMAGE_PATH="$selected_folder/zapp.AppImage"
    if [[ ! -x "$APPIMAGE_PATH" ]]; then
        echo "File '$APPIMAGE_PATH' is not executable."
        exit 1
    fi
    echo "Running $(basename "$selected_folder") using zapp.AppImage..."
    "$APPIMAGE_PATH"
    exit 0
fi

# If no AppImage is found, attempt to find executables.
# If the folder contains exactly one subdirectory, assume that is the actual app folder.
subdirs=( "$selected_folder"/*/ )
if [[ ${#subdirs[@]} -eq 1 ]]; then
    search_dir="${subdirs[0]}"
else
    search_dir="$selected_folder"
fi

# Look for executable files (only regular files) in the chosen directory.
mapfile -t executables < <(find "$search_dir" -maxdepth 1 -type f -executable)
exe_count=${#executables[@]}

if [[ $exe_count -eq 0 ]]; then
    echo "No executable file found in '$search_dir'."
    exit 1
elif [[ $exe_count -eq 1 ]]; then
    echo "Running $(basename "$search_dir") using $(basename "${executables[0]}")..."
    "${executables[0]}"
    exit 0
else
    # More than one executable found; prompt the user to select one.
    declare -A exe_map
    echo "Multiple executables found in '$search_dir'. Choose one:"
    counter=0
    for exe in "${executables[@]}"; do
        key="${letters[$counter]}"
        exe_map["$key"]="$exe"
        exe_name=$(basename "$exe")
        echo "  [$key] $exe_name"
        ((counter++))
    done
    read -p "Enter the letter corresponding to the executable you want to run: " exe_choice
    if [[ -z "${exe_map[$exe_choice]}" ]]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi
    chosen_exe="${exe_map[$exe_choice]}"
    echo "Running $(basename "$chosen_exe")..."
    "$chosen_exe"
    exit 0
fi
