#!/bin/bash

# Function to build a package
build_package() {
    local package_path=$1
    local package_name=$(basename "$package_path")
    echo "Building $package_name..."
    swift build --package-path "$package_path"
    if [ $? -eq 0 ]; then
        echo -e "$package_name build successful. \n"
    else
        echo "$package_name build failed!"
        exit 1
    fi
}

# Function to test a package
test_package() {
    local package_path=$1
    local package_name=$(basename "$package_path")
    echo "Testing $package_name..."
    swift test --package-path "$package_path"
    if [ $? -eq 0 ]; then
        echo -e "$package_name tests passed. \n"
    else
        echo "$package_name tests failed!"
        exit 1
    fi
}

# List of package paths
packages=( "./Blockchain" "./Boka" "./Database" "./Node" "./Utils" )

for package_path in "${packages[@]}"; do
    build_package "$package_path"
done

for package_path in "${packages[@]}"; do
    test_package "$package_path"
done

echo "All packages built and tested successfully."
