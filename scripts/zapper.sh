#!/bin/bash
# Script: zapper.sh
# Description:
#   This script takes an AppImage or a .tar.xz file as an argument, asks for a folder name,
#   creates a dedicated folder under $HOME/zapps with that name, moves the AppImage into that folder
#   (renamed as "zapp.AppImage") and sets it to be executable, or extracts a .tar.xz archive into that folder.
#
# Usage:
#   ./zapper.sh /path/to/Your-App.AppImage
#   ./zapper.sh /path/to/Your-App.tar.xz

# Check if an argument is provided.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/AppImage-or-tar.xz"
    exit 1
fi

# Get the absolute path of the file.
APPFILE="$1"

# Verify that the file exists.
if [ ! -f "$APPFILE" ]; then
    echo "File '$APPFILE' does not exist."
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

# Determine the file type based on its extension.
if [[ "$APPFILE" == *.AppImage ]]; then
    # Move the AppImage to the destination directory as "zapp.AppImage".
    mv "$APPFILE" "$DEST_DIR/zapp.AppImage"
    # Set the executable permission.
    chmod +x "$DEST_DIR/zapp.AppImage"
    echo "AppImage has been prepared in '$DEST_DIR/zapp.AppImage'."
elif [[ "$APPFILE" == *.tar.xz ]]; then
    # Extract the tar.xz archive into the destination directory.
    tar -xf "$APPFILE" -C "$DEST_DIR"
    echo "tar.xz archive has been extracted in '$DEST_DIR'."
else
    echo "Unsupported file type. Please provide an AppImage or a .tar.xz file."
    exit 1
fi
