#!/bin/zsh
set -euo pipefail
script_directory=${0:A:h}
project_directory=${script_directory:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
export CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-artwork-module-cache
/usr/bin/xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
    -warnings-as-errors -parse-as-library -D MUSIC_GLASS_LIGHT_TESTS \
    "$project_directory/Cascade/Features/MusicGlassLightResponse.swift" \
    "$project_directory/Cascade/Features/Tests/MusicGlassLightChecks.swift" \
    -o /private/tmp/cascade-music-glass-light-checks
/private/tmp/cascade-music-glass-light-checks
