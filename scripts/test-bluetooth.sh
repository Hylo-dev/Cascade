#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
module_cache=/private/tmp/cascade-bluetooth-module-cache
test_binary=/private/tmp/cascade-bluetooth-tests

mkdir -p "$module_cache"

source_files=(
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothAudioRouteMonitor.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothAudioRouteReducer.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothMetadataEnricher.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/SystemBluetoothDeviceMetadataReader.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothBatterySnapshot.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothDeviceModel.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothDeviceMetadata.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothMetadataParser.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothMonitoring.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothConnectionEvent.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothConnectionReducer.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/IOBluetoothConnectionMonitor.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/Tests/BluetoothMonitorTestSupport.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/Tests/BluetoothConnectionReducerTests.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/Tests/BluetoothMonitorLifecycleTests.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/Tests/BluetoothBatteryMetadataTests.swift"
    "$project_directory/Cascade/Integrations/Bluetooth/Tests/BluetoothMetadataEnricherTests.swift"
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
    -D BLUETOOTH_MONITOR_TESTS \
    "${source_files[@]}" \
    -framework AppKit \
    -framework IOBluetooth \
    -framework IOKit \
    -framework CoreAudio \
    -o "$test_binary"

"$test_binary"

notice_test_binary=/private/tmp/cascade-bluetooth-notice-tests

DEVELOPER_DIR="$developer_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc \
    -swift-version 6 \
    -target arm64-apple-macosx14.0 \
    -default-isolation MainActor \
    -warnings-as-errors \
    -parse-as-library \
    -D BLUETOOTH_NOTICE_POLICY_TESTS \
    "$project_directory/Cascade/Integrations/Bluetooth/NativeBluetoothNoticePolicy.swift" \
    "$project_directory/Cascade/Integrations/Bluetooth/Tests/NativeBluetoothNoticePolicyChecks.swift" \
    -o "$notice_test_binary"

"$notice_test_binary"
