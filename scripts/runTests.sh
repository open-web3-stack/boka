#!/usr/bin/env bash

set -e

# Parse --skip argument
skip_packages=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip=*)
            skip_packages="${1#*=}"
            shift
            ;;
        *)
            break
            ;;
    esac
done

command=$1
shift

# Helper function to check if package should be skipped
is_skipped() {
    [[ ",$skip_packages," == *",$1,"* ]]
}

for file in **/Tests; do
    package=$(basename "$(dirname "$file")")

    if is_skipped "$package"; then
        echo "Skipping $package"
        continue
    fi

    swift "$command" "$@" --package-path "$(dirname "$file")"
done
