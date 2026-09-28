#!/bin/zsh
set -euo pipefail
script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
module_cache=/private/tmp/cascade-bluetooth-audio-route-module-cache
test_binary=/private/tmp/cascade-bluetooth-audio-route-tests
mkdir -p "$module_cache"
source_files=(
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothBatterySnapshot.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothDeviceModel.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothDeviceMetadata.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothConnectionEvent.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothConnectionReducer.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothAudioRouteReducer.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/Tests/BluetoothAudioRouteChecks.swift"
)
if [[ -f "$project_directory/Cascade/Integrations/Bluetooth/BluetoothAudioRouteMonitor.swift" ]]; then
    source_files+=("$project_directory/Cascade/Integrations/Bluetooth/BluetoothAudioRouteMonitor.swift")
fi
DEVELOPER_DIR="$developer_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
    -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -warnings-as-errors -parse-as-library -D BLUETOOTH_AUDIO_ROUTE_TESTS \
    "${source_files[@]}" -framework AppKit -framework CoreAudio -framework IOBluetooth -o "$test_binary"
"$test_binary"
