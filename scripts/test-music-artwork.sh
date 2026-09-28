#!/bin/zsh
set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
export CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-artwork-module-cache

/usr/bin/xcrun swiftc \
    -swift-version 6 \
    -target arm64-apple-macosx14.0 \
    -default-isolation MainActor \
    -warnings-as-errors \
    -parse-as-library \
    -D MUSIC_ARTWORK_TESTS \
    "$project_directory/Cascade/Models/Media/MusicArtworkColor.swift" \
    "$project_directory/Cascade/Models/Media/DecodedMusicArtwork.swift" \
    "$project_directory/Cascade/Core/Media/MusicArtworkDecoder.swift" \
    "$project_directory/Cascade/Checks/Music/MusicArtworkChecks.swift" \
    -o /private/tmp/cascade-artwork-checks

/private/tmp/cascade-artwork-checks
