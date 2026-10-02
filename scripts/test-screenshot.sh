#!/bin/zsh
set -euo pipefail
script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
module_cache=/private/tmp/cascade-screenshot-test-module-cache
mkdir -p "$module_cache"
DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun swiftc \
    -swift-version 6 -default-isolation MainActor -warnings-as-errors \
    -module-cache-path "$module_cache" -parse-as-library \
    -D SCREENSHOT_BEHAVIOR_TESTS \
    "$project_directory/Cascade/Models/Screenshot/ScreenshotShortcuts.swift" \
    "$project_directory/Cascade/Core/Screenshot/ScreenshotKeyGate.swift" \
    "$project_directory/Cascade/Core/Protocols/ScreenshotKeyTapping.swift" \
    "$project_directory/Cascade/Core/Screenshot/ScreenshotKeyTap.swift" \
    "$project_directory/Cascade/Core/Input/EventTapThread.swift" \
    "$project_directory/Cascade/Checks/Screenshot/ScreenshotBehaviorChecks.swift" \
    -o /private/tmp/cascade-screenshot-behavior-tests
/private/tmp/cascade-screenshot-behavior-tests
