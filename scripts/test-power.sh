#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
module_cache=/private/tmp/cascade-power-module-cache
test_binary=/private/tmp/cascade-power-tests

mkdir -p "$module_cache"

DEVELOPER_DIR="$developer_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc \
    -swift-version 6 \
    -target arm64-apple-macosx15.0 \
    -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility \
    -warnings-as-errors \
    -parse-as-library \
    -D POWER_MONITOR_TESTS \
    "$project_directory/Cascade/Core/Power/IOKitPowerMonitor.swift" \
    "$project_directory/Cascade/Models/Power/MacPowerSnapshot.swift" \
    "$project_directory/Cascade/Models/Power/Enums/PowerConnectionUpdate.swift" \
    "$project_directory/Cascade/Core/Power/PowerConnectionReducer.swift" \
    "$project_directory/Cascade/Core/Protocols/PowerMonitoring.swift" \
    "$project_directory/Cascade/Core/Protocols/MacPowerReading.swift" \
    "$project_directory/Cascade/Core/Power/SystemMacPowerReader.swift" \
    "$project_directory/Cascade/Checks/Power/PowerBehaviorChecks.swift" \
    -framework AppKit \
    -framework IOKit \
    -o "$test_binary"

"$test_binary"
