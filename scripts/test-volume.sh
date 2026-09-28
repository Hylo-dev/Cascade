#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
module_cache=/private/tmp/cascade-volume-module-cache
test_binary=/private/tmp/cascade-volume-tests
test_define=VOLUME_MONITOR_TESTS
if [[ ${1:-} == --probe ]]; then
    test_define=VOLUME_READ_ONLY_PROBE
    test_binary=/private/tmp/cascade-volume-read-only-probe
fi

mkdir -p "$module_cache"

source_files=(
    "$project_directory"/Cascade/Integrations/Volume/*.swift
    "$project_directory/Cascade/Integrations/Volume/Tests/VolumeBehaviorChecks.swift"
    "$project_directory/Cascade/Integrations/Volume/Tests/VolumeReadOnlyProbe.swift"
)

DEVELOPER_DIR="$developer_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc \
    -swift-version 6 \
    -target arm64-apple-macosx14.0 \
    -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -warnings-as-errors \
    -parse-as-library \
    -D "$test_define" \
    "${source_files[@]}" \
    -framework AppKit \
    -framework CoreAudio \
    -o "$test_binary"

"$test_binary"
