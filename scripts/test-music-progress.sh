#!/bin/zsh
set -euo pipefail
script_directory=${0:A:h}
project_directory=${script_directory:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
export CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-progress-module-cache
check_directory=$(mktemp -d /private/tmp/cascade-progress-checks.XXXXXX)
trap 'rm -rf "$check_directory"' EXIT
/usr/bin/xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
    -default-isolation MainActor -warnings-as-errors -parse-as-library \
    -D MUSIC_PROGRESS_TESTS \
    "$project_directory/Cascade/Features/MusicProgressSlider.swift" \
    "$project_directory/Cascade/Features/Tests/MusicProgressScrollChecks.swift" \
    -o "$check_directory/progress-checks"
"$check_directory/progress-checks"
