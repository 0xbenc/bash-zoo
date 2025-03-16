#!/bin/bash
# Script: azap.sh
# Description:
#   This script lists folders one level down from the 'zapps' directory,
#   assigns each a unique key (a, b, c, …), and waits for the user to input
#   a key. When a valid key is entered, it runs the 'zapp.AppImage' found in that folder.

# Set the directory containing the zapp folders
ZAPPS_DIR="~/zapps"

# Check if the zapps directory exists
if [[ ! -d "$ZAPPS_DIR" ]]; then
    echo "Directory '$ZAPPS_DIR' does not exist."
    exit 1
fi

# Declare an associative array to map keys to folder paths.
declare -A folder_map

# Use an array of letters for unique keys.
letters=( {a..z} )

echo "Available zapps:"

counter=0
# Loop through each item one level down in ZAPPS_DIR.
for folder in "$ZAPPS_DIR"/*; do
    if [[ -d "$folder" ]]; then
        # Assign a unique letter from the letters array.
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

# Retrieve the selected folder and determine the AppImage path.
selected_folder="${folder_map[$user_key]}"
APPIMAGE_PATH="$selected_folder/zapp.AppImage"

# Check if the AppImage file exists and is executable.
if [[ ! -f "$APPIMAGE_PATH" ]]; then
    echo "File '$APPIMAGE_PATH' does not exist."
    exit 1
fi

if [[ ! -x "$APPIMAGE_PATH" ]]; then
    echo "File '$APPIMAGE_PATH' is not executable."
    exit 1
fi

# Inform the user and execute the AppImage.
echo "Running $(basename "$selected_folder")..."
"$APPIMAGE_PATH"
