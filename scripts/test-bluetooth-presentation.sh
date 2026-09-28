#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
output_directory=/private/tmp/cascade-bluetooth-presentation
module_cache=/private/tmp/cascade-airpods-module-cache
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}

# Default to the products of the workspace's own Debug build, wherever Xcode
# keeps its DerivedData, instead of a fixed scratch path.
if (( $# > 0 )); then
    build_products=$1
else
    build_products=$(DEVELOPER_DIR="$developer_directory" /usr/bin/xcodebuild \
        -workspace "$project_directory/Cascade.xcworkspace" \
        -scheme Cascade \
        -configuration Debug \
        -showBuildSettings 2>/dev/null \
        | /usr/bin/awk '$1 == "BUILT_PRODUCTS_DIR" { print $3; exit }')
fi

# CascadeKit is split into modules; its object depends on these two siblings.
package_objects=(
    "$build_products/CascadeKit.o"
    "$build_products/CascadeContracts.o"
    "$build_products/CascadePresentation.o"
)
for object in $package_objects; do
    if [[ ! -f "$object" ]]; then
        print -u2 "error: missing $object. Build the Cascade scheme (Debug) first, or pass its Build/Products/Debug directory."
        exit 1
    fi
done

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
    $package_objects \
    -o "$output_directory/verify"

LLVM_PROFILE_FILE="$output_directory/verify.profraw" \
"$output_directory/verify" \
    "$output_directory/notices.png"
