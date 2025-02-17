#!/bin/bash

# Generate a random UUID and copy it to the clipboard
UUID=$(uuidgen --random)
echo -n "$UUID" | xclip -selection clipboard

echo "UUID copied to clipboard: $UUID"

