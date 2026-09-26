#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
build_products=${1:-/private/tmp/cascade-airpods-derived/Build/Products/Debug}
output_directory=/private/tmp/cascade-bluetooth-presentation
module_cache=/private/tmp/cascade-airpods-module-cache
developer_directory=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}

mkdir -p "$output_directory" "$module_cache"

DEVELOPER_DIR="$developer_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc \
    -swift-version 6 \
    -target arm64-apple-macosx14.0 \
    -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility \
    -warnings-as-errors \
    -parse-as-library \
    -profile-generate \
    -I "$build_products" \
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothDeviceModel.swift" \
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothConnectionEvent.swift" \
    "$project_directory/Cascade/Integrations/Bluetooth/BluetoothBatterySnapshot.swift" \
    "$project_directory/Cascade/Features/OfficialHeadphoneAssetResolver.swift" \
    "$project_directory/Cascade/Features/OfficialHeadphoneArtwork.swift" \
    "$project_directory/Cascade/Features/AirPodsModelView.swift" \
    "$project_directory/Cascade/Features/BluetoothBatteryRing.swift" \
    "$project_directory/Cascade/Features/BluetoothConnectionActivity.swift" \
    "$script_directory/verify-bluetooth-presentation.swift" \
    "$build_products/CascadeKit.o" \
    -o "$output_directory/verify"

LLVM_PROFILE_FILE="$output_directory/verify.profraw" \
"$output_directory/verify" \
    "$output_directory/notices.png"
