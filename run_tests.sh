#!/bin/bash
# Headless Godot 4.6-stable unit test automation runner script
set -e

# Change directory to the repository root
cd "$(dirname "$0")"

# Path to local Godot binary
LOCAL_GODOT="./godot_bin"

# Check if Godot is in PATH globally
if command -v godot &> /dev/null; then
    echo "Using global Godot binary found in PATH: $(command -v godot)"
    GODOT_CMD="godot"
# Check if local Godot binary exists
elif [ -f "$LOCAL_GODOT" ]; then
    echo "Using local Godot binary found at $LOCAL_GODOT"
    GODOT_CMD="$LOCAL_GODOT"
else
    echo "Godot binary not found globally or locally."
    echo "Downloading Godot 4.6-stable Linux 64-bit..."
    
    DOWNLOAD_URL="https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_linux.x86_64.zip"
    ZIP_FILE="Godot_v4.6-stable_linux.x86_64.zip"
    
    # Download using curl
    curl -L -o "$ZIP_FILE" "$DOWNLOAD_URL"
    
    # Unzip
    echo "Extracting Godot binary..."
    unzip -q "$ZIP_FILE"
    
    # Rename binary to godot_bin for consistency
    mv Godot_v4.6-stable_linux.x86_64 "$LOCAL_GODOT"
    chmod +x "$LOCAL_GODOT"
    
    # Clean up zip
    rm "$ZIP_FILE"
    echo "Godot 4.6-stable setup completed successfully."
    GODOT_CMD="$LOCAL_GODOT"
fi

echo "========================================="
echo "Running Wave Function Collapse Unit Tests..."
echo "========================================="
"$GODOT_CMD" --headless -s tests/headless_test_runner.gd
echo "========================================="
echo "Test runner finished execution."
echo "========================================="
