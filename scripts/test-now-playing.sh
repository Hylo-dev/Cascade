#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
test_directory=$(mktemp -d /private/tmp/cascade-now-playing-tests.XXXXXX)
module_cache=/private/tmp/cascade-now-playing-module-cache
trap 'rm -rf "$test_directory"' EXIT
mkdir -p "$module_cache"
export DEVELOPER_DIR="$developer_directory"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFT_MODULE_CACHE_PATH="$module_cache"

compiler_options=(
    -swift-version 6
    -target arm64-apple-macosx14.0
    -default-isolation MainActor
    -enable-upcoming-feature MemberImportVisibility
    -warnings-as-errors
    -parse-as-library
)

/usr/bin/xcrun swiftc "${compiler_options[@]}" \
    -emit-module -emit-library -module-name CascadeKit \
    -emit-module-path "$test_directory/CascadeKit.swiftmodule" \
    "$project_directory/CascadeKit/Sources/CascadeKit/Models/Media/NowPlayingSnapshot.swift" \
    "$project_directory/CascadeKit/Sources/CascadeKit/Models/Media/MediaCommandCapabilities.swift" \
    "$project_directory/CascadeKit/Sources/CascadeKit/Core/Protocols/NowPlayingProviding.swift" \
    "$project_directory/CascadeKit/Sources/CascadeKit/Models/Media/Enums/MediaCommand.swift" \
    -o "$test_directory/libCascadeKit.dylib"

/usr/bin/xcrun swiftc "${compiler_options[@]}" \
    -D NOW_PLAYING_TESTS \
    -I "$test_directory" -L "$test_directory" -lCascadeKit \
    -Xlinker -rpath -Xlinker "$test_directory" \
    "$project_directory/Cascade/Core/Media/MusicPlaybackPresentation.swift" \
    "$project_directory/Cascade/Models/Media/Enums/NowPlayingProviderStatus.swift" \
    "$project_directory/Cascade/Core/Media/SystemNowPlayingProvider.swift" \
    "$project_directory/Cascade/Core/Media/ScriptableMusicAppleEventReader.swift" \
    "$project_directory/Cascade/Core/Media/ScriptableMusicArtwork.swift" \
    "$project_directory/Cascade/Core/Media/ScriptableMusicDescriptorDecoder.swift" \
    "$project_directory/Cascade/Models/Media/Enums/ScriptableMusicSource.swift" \
    "$project_directory/Cascade/Models/Media/ScriptablePlayerTarget.swift" \
    "$project_directory/Cascade/Models/Media/Enums/ScriptablePlaybackState.swift" \
    "$project_directory/Cascade/Core/Extensions/NowPlayingSnapshot+Announcement.swift" \
    "$project_directory/Cascade/Models/Media/NowPlayingAnnouncement.swift" \
    "$project_directory/Cascade/Models/Media/ScriptableTrackMetadata.swift" \
    "$project_directory/Cascade/Core/Media/NowPlayingSourceSelection.swift" \
    "$project_directory/Cascade/Core/Media/NowPlayingRefreshRevisions.swift" \
    "$project_directory/Cascade/Core/Errors/ScriptableMusicError.swift" \
    "$project_directory/Cascade/Core/Protocols/ScriptableMusicCommandSending.swift" \
    "$project_directory/Cascade/Core/Protocols/ScriptableMusicReading.swift" \
    "$project_directory/Cascade/Checks/Media/NowPlayingBehaviorChecks.swift" \
    -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
    -o "$test_directory/now-playing-tests"

"$test_directory/now-playing-tests" "$@"
