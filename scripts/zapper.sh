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
#   the main executable.
#
# Usage:
#   ./zapper.sh /path/to/Your-App.AppImage
#   ./zapper.sh /path/to/Your-App.tar.xz
#   ./zapper.sh /path/to/Your-App.tar.gz

# Check if an argument is provided.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/AppImage-or-archive"
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

# Variable to hold the main executable path for the markdown file.
MAIN_EXE=""

# Determine the file type based on its extension.
if [[ "$APPFILE" == *.AppImage ]]; then
    # Move the AppImage to the destination directory as "zapp.AppImage".
    mv "$APPFILE" "$DEST_DIR/zapp.AppImage"
    # Set the executable permission.
    chmod +x "$DEST_DIR/zapp.AppImage"
    echo "AppImage has been prepared in '$DEST_DIR/zapp.AppImage'."
    MAIN_EXE="zapp.AppImage"
elif [[ "$APPFILE" == *.tar.xz ]]; then
    # Extract the tar.xz archive into the destination directory.
    tar -xf "$APPFILE" -C "$DEST_DIR"
    echo "tar.xz archive has been extracted in '$DEST_DIR'."
elif [[ "$APPFILE" == *.tar.gz ]]; then
    # Extract the tar.gz archive into the destination directory.
    tar -xzf "$APPFILE" -C "$DEST_DIR"
    echo "tar.gz archive has been extracted in '$DEST_DIR'."
else
    echo "Unsupported file type. Please provide an AppImage, a .tar.xz, or a .tar.gz file."
    exit 1
fi

# For archive-based installations, try to determine the main executable.
if [[ -z "$MAIN_EXE" ]]; then
    # Search for executable files within DEST_DIR (and one level deeper).
    mapfile -t exes < <(find "$DEST_DIR" -maxdepth 2 -type f -executable)
    exe_count=${#exes[@]}

    if [[ $exe_count -eq 0 ]]; then
        echo "No executable file found in '$DEST_DIR'."
    elif [[ $exe_count -eq 1 ]]; then
        MAIN_EXE=$(realpath --relative-to="$DEST_DIR" "${exes[0]}")
        echo "Identified main executable: $(basename "$MAIN_EXE")"
    else
        echo "Multiple executables found in '$DEST_DIR':"
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
        read -p "Enter the letter corresponding to the main executable for this zapp: " exe_choice
        if [[ -z "${exe_map[$exe_choice]}" ]]; then
            echo "Invalid selection. No markdown file will be created."
        else
            MAIN_EXE=$(realpath --relative-to="$DEST_DIR" "${exe_map[$exe_choice]}")
        fi
    fi
fi

# If a main executable was determined, create a markdown file (zapp.md) in the DEST_DIR.
if [[ -n "$MAIN_EXE" ]]; then
    echo "$MAIN_EXE" > "$DEST_DIR/zapp.md"
    echo "Registered main executable '$MAIN_EXE' in '$DEST_DIR/zapp.md'."
else
    echo "No main executable was registered."
fi
