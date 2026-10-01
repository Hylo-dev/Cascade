#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
module_cache=/private/tmp/cascade-bluetooth-module-cache
test_binary=/private/tmp/cascade-bluetooth-tests

mkdir -p "$module_cache"

source_files=(
    "$project_directory/Cascade/Models/Bluetooth/Enums/BluetoothAudioRouteReadResult.swift"
    "$project_directory/Cascade/Core/Protocols/BluetoothAudioRouteSource.swift"
    "$project_directory/Cascade/Core/Bluetooth/CoreAudioBluetoothRouteSource.swift"
    "$project_directory/Cascade/Core/Bluetooth/BluetoothAudioRouteWorker.swift"
    "$project_directory/Cascade/Core/Bluetooth/BluetoothAudioRouteMonitor.swift"
    "$project_directory/Cascade/Models/Bluetooth/BluetoothAudioRouteSnapshot.swift"
    "$project_directory/Cascade/Core/Bluetooth/BluetoothAudioRouteReducer.swift"
    "$project_directory/Cascade/Core/Bluetooth/BluetoothMetadataEnricher.swift"
    "$project_directory/Cascade/Core/Bluetooth/SystemBluetoothDeviceMetadataReader.swift"
    "$project_directory/Cascade/Models/Bluetooth/BluetoothBatterySnapshot.swift"
    "$project_directory/Cascade/Models/Bluetooth/Enums/BluetoothDeviceModel.swift"
    "$project_directory/Cascade/Models/Bluetooth/BluetoothDeviceMetadata.swift"
    "$project_directory/Cascade/Core/Protocols/BluetoothDeviceMetadataReading.swift"
    "$project_directory/Cascade/Core/Bluetooth/BluetoothMetadataParser.swift"
    "$project_directory/Cascade/Models/Bluetooth/Enums/BluetoothMonitoringStatus.swift"
    "$project_directory/Cascade/Core/Protocols/BluetoothMonitoring.swift"
    "$project_directory/Cascade/Models/Bluetooth/BluetoothConnectionEvent.swift"
    "$project_directory/Cascade/Models/Bluetooth/BluetoothConnectedDevice.swift"
    "$project_directory/Cascade/Models/Bluetooth/BluetoothConnectionCallbackIdentity.swift"
    "$project_directory/Cascade/Core/Bluetooth/BluetoothConnectionCallbackGate.swift"
    "$project_directory/Cascade/Core/Bluetooth/BluetoothConnectionReducer.swift"
    "$project_directory/Cascade/Core/Bluetooth/IOBluetoothConnectionObserver.swift"
    "$project_directory/Cascade/Models/Bluetooth/Enums/IOBluetoothConnectionCallback.swift"
    "$project_directory/Cascade/Core/Bluetooth/IOBluetoothDeviceSnapshot.swift"
    "$project_directory/Cascade/Core/Bluetooth/IOBluetoothConnectionMonitor.swift"
    "$project_directory/Cascade/Checks/Bluetooth/BluetoothMonitorTestSupport.swift"
    "$project_directory/Cascade/Checks/Bluetooth/BluetoothConnectionReducerTests.swift"
    "$project_directory/Cascade/Checks/Bluetooth/BluetoothMonitorLifecycleTests.swift"
    "$project_directory/Cascade/Checks/Bluetooth/BluetoothBatteryMetadataTests.swift"
    "$project_directory/Cascade/Checks/Bluetooth/BluetoothMetadataEnricherTests.swift"
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
    -target arm64-apple-macosx15.0 \
    -default-isolation MainActor \
    -warnings-as-errors \
    -parse-as-library \
    -D BLUETOOTH_NOTICE_POLICY_TESTS \
    "$project_directory/Cascade/Models/Bluetooth/BluetoothNoticeConnectionHint.swift" \
    "$project_directory/Cascade/Models/Bluetooth/BluetoothNoticeSnapshot.swift" \
    "$project_directory/Cascade/Core/Bluetooth/BluetoothNoticeMatchPolicy.swift" \
    "$project_directory/Cascade/Checks/Bluetooth/NativeBluetoothNoticePolicyChecks.swift" \
    -o "$notice_test_binary"

"$notice_test_binary"
