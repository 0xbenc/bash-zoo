#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Update package list
echo "Updating package list..."
sudo apt update

# Install required packages
echo "Installing xclip..."
sudo apt install -y xclip magic-wormhole figlet qrencode

# Verify installations
echo "Verifying installations..."
for cmd in pass oathtool figlet; do
    if command_exists "$cmd"; then
        echo "$cmd installed successfully!"
    else
        echo "Error: $cmd installation failed."
        exit 1
    fi
done

echo "Installation complete!"
