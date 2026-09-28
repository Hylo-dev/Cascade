#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
module_cache=/private/tmp/cascade-audio-spectrum-module-cache
test_binary=/private/tmp/cascade-audio-spectrum-tests

mkdir -p "$module_cache"

DEVELOPER_DIR="$developer_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc \
    -D AUDIO_SPECTRUM_TESTS -swift-version 6 \
    -target arm64-apple-macosx14.0 \
    -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility \
    -warnings-as-errors \
    -parse-as-library \
    "$project_directory"/Cascade/Integrations/Audio/*.swift \
    "$project_directory/Cascade/Integrations/Audio/Tests/AudioSpectrumBehaviorChecks.swift" \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework Accelerate \
    -o "$test_binary"

"$test_binary"
