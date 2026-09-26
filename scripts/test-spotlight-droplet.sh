#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
export CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-spotlight-droplet-module-cache
check_directory=$(mktemp -d /private/tmp/cascade-spotlight-droplet-checks.XXXXXX)
trap 'rm -rf "$check_directory"' EXIT

/usr/bin/xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
    -default-isolation MainActor -warnings-as-errors -parse-as-library \
    -D SPOTLIGHT_DROPLET_TESTS \
    "$project_directory"/Cascade/Features/Spotlight/*.swift \
    "$project_directory/Cascade/Features/Spotlight/Tests/SpotlightDropletChecks.swift" \
    -o "$check_directory/spotlight-droplet-checks"

"$check_directory/spotlight-droplet-checks"
