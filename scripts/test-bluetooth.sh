#!/bin/zsh

# The native Bluetooth banner's match policy stays in Cascade beside its Accessibility
# suppressor. The Bluetooth source, its reducer, metadata and audio route listener live in
# PluginHost now and are covered by the CascadeKit package tests.

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
module_cache=/private/tmp/cascade-bluetooth-module-cache
notice_test_binary=/private/tmp/cascade-bluetooth-notice-tests

mkdir -p "$module_cache"

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
