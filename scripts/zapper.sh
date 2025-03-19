#!/bin/bash
# Script: zapper.sh
# Description:
#   This script takes an AppImage file as an argument, asks for a folder name,
#   creates a dedicated folder under $HOME/zapps with that name, moves the AppImage
#   into that folder (renamed as "zapp.AppImage"), and sets it to be executable.
#
# Usage:
#   ./zapper.sh /path/to/Your-AppImage.AppImage

# Check if an argument is provided.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/AppImage"
    exit 1
fi

# Get the absolute path of the AppImage.
APPIMAGE="$1"

# Verify that the file exists.
if [ ! -f "$APPIMAGE" ]; then
    echo "File '$APPIMAGE' does not exist."
    exit 1
fi

# Prompt the user to input a folder name.
read -p "Enter the folder name for the zapp (e.g., endless-sky): " folder_name

# Check if the user entered a folder name.
if [ -z "$folder_name" ]; then
    echo "Folder name cannot be empty."
    exit 1
fi

# Define the destination directory under $HOME/zapps.
DEST_DIR="$HOME/zapps/$folder_name"

# Create the destination directory if it does not exist.
mkdir -p "$DEST_DIR"

# Move the AppImage to the destination directory as "zapp.AppImage".
mv "$APPIMAGE" "$DEST_DIR/zapp.AppImage"

# Set the executable permission.
chmod +x "$DEST_DIR/zapp.AppImage"

echo "AppImage has been prepared in '$DEST_DIR/zapp.AppImage'."
