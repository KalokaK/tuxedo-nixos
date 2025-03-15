#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <binary-path>"
    exit 1
fi

BINARY=$1

if ! command -v ldd &> /dev/null; then
    echo "Error: ldd not found. Please install it."
    exit 1
fi

if ! command -v nix-locate &> /dev/null; then
    echo "Error: nix-locate not found. Please install nix-index."
    exit 1
fi

# Get shared library dependencies
libs=$(ldd "$BINARY" | awk '{print $1}' | grep "\.so" | sed 's/\.out$//' | sort -u)

echo "Finding Nix packages for the following libraries:"
echo "$libs"

declare -A found_packages

declare -A package_to_libraries

for lib in $libs; do
    for package in $(nix-locate --minimal --top-level -w "/$lib" | awk '{print $1}' | sed 's/\.out$//' | sort -u | uniq); do
        found_packages[$lib]="$package"
        package_to_libraries[$package]+="$lib "
    done
done

echo -e "\nMatching Nix packages:"
for package in "${!package_to_libraries[@]}"; do
    echo "$package -> ${package_to_libraries[$package]}"
done
