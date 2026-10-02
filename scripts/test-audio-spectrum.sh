#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
module_cache=/private/tmp/cascade-audio-spectrum-module-cache
test_binary=/private/tmp/cascade-audio-spectrum-tests

mkdir -p "$module_cache"

DEVELOPER_DIR="$developer_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc \
    -D AUDIO_SPECTRUM_TESTS -swift-version 6 \
    -target arm64-apple-macosx15.0 \
    -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility \
    -warnings-as-errors \
    -parse-as-library \
    "$project_directory/Cascade/Core/Audio/AudioCapturePermissionRequester.swift" \
    "$project_directory/Cascade/Core/Audio/AudioSpectrumAnalyzer.swift" \
    "$project_directory/Cascade/Models/Audio/AudioSpectrumFrame.swift" \
    "$project_directory/Cascade/Models/Audio/Enums/AudioSpectrumStatus.swift" \
    "$project_directory/Cascade/Core/Protocols/AudioSpectrumMonitoring.swift" \
    "$project_directory/Cascade/Core/Audio/AudioSpectrumPCMExchange.swift" \
    "$project_directory/Cascade/Core/Audio/SpectrumPCMSlot.swift" \
    "$project_directory/Cascade/Core/Audio/CoreAudioSpectrumCaptureDriver.swift" \
    "$project_directory/Cascade/Core/Errors/SpectrumCaptureFailure.swift" \
    "$project_directory/Cascade/Core/Audio/CoreAudioSpectrumCaptureSession.swift" \
    "$project_directory/Cascade/Core/Protocols/AudioSpectrumCaptureDriving.swift" \
    "$project_directory/Cascade/Core/Audio/CoreAudioSpectrumMonitor.swift" \
    "$project_directory/Cascade/Checks/Audio/AudioSpectrumBehaviorChecks.swift" \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework Accelerate \
    -o "$test_binary"

"$test_binary"
