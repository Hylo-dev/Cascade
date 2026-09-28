#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
export CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-spacebar-module-cache

/usr/bin/xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
    -default-isolation MainActor \
    -warnings-as-errors -parse-as-library -D MUSIC_SPACEBAR_TESTS \
    "$project_directory/Cascade/Core/Input/MusicSpacebarTap.swift" \
    "$project_directory/Cascade/Core/Input/MusicSpacebarRelay.swift" \
    "$project_directory/Cascade/Core/Input/EventTapThread.swift" \
    "$project_directory/Cascade/Checks/Music/MusicSpacebarChecks.swift" \
    -o /private/tmp/cascade-music-spacebar-checks
/private/tmp/cascade-music-spacebar-checks
