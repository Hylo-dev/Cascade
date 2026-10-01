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
    "$project_directory/Cascade/Core/Volume/CoreAudioSystemVolume.swift"
    "$project_directory/Cascade/Core/Volume/VolumeMonitorWorker.swift"
    "$project_directory/Cascade/Core/Volume/CoreAudioVolumeMonitor.swift"
    "$project_directory/Cascade/Core/Volume/VolumeAccessibilityObserver.swift"
    "$project_directory/Cascade/Models/Volume/SystemVolumeSnapshot.swift"
    "$project_directory/Cascade/Models/Volume/VolumeChangeEvent.swift"
    "$project_directory/Cascade/Core/Volume/VolumeChangeReducer.swift"
    "$project_directory/Cascade/Models/Volume/Enums/VolumeKeyCommand.swift"
    "$project_directory/Cascade/Models/Volume/VolumeMediaKey.swift"
    "$project_directory/Cascade/Core/Volume/VolumeKeyRouter.swift"
    "$project_directory/Cascade/Core/Volume/VolumeMediaKeyTap.swift"
    "$project_directory/Cascade/Models/Volume/Enums/VolumeMonitoringStatus.swift"
    "$project_directory/Cascade/Models/Volume/Enums/VolumeMonitorUpdate.swift"
    "$project_directory/Cascade/Core/Protocols/VolumeMonitoring.swift"
    "$project_directory/Cascade/Core/Protocols/SystemVolumeControlling.swift"
    "$project_directory/Cascade/Core/Volume/VolumeTapRecovery.swift"
    "$project_directory/Cascade/Checks/Volume/VolumeCheckFailure.swift"
    "$project_directory/Cascade/Checks/Volume/VolumeBehaviorChecks.swift"
    "$project_directory/Cascade/Checks/Volume/PermissionRefreshCounter.swift"
    "$project_directory/Cascade/Checks/Volume/FakeVolumeController.swift"
    "$project_directory/Cascade/Checks/Volume/VolumeReadOnlyProbe.swift"
)

DEVELOPER_DIR="$developer_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc \
    -swift-version 6 \
    -target arm64-apple-macosx15.0 \
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
