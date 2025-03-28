#!/bin/bash
set -e

# Update package lists and install packages based on available package manager

if command -v apt-get >/dev/null; then
    echo "Detected apt-get. Installing via apt-get..."
    sudo apt-get update
    sudo apt-get install -y ccache cppcheck
elif command -v yum >/dev/null; then
    echo "Detected yum. Installing via yum..."
    sudo yum install -y ccache cppcheck
elif command -v dnf >/dev/null; then
    echo "Detected dnf. Installing via dnf..."
    sudo dnf install -y ccache cppcheck
elif command -v pacman >/dev/null; then
    echo "Detected pacman. Installing via pacman..."
    sudo pacman -Sy --noconfirm ccache cppcheck
else
    echo "No supported package manager found. Please install ccache and cppcheck manually."
    exit 1
fi

echo "Installation complete."
