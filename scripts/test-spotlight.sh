#!/bin/zsh
set -euo pipefail
script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
module_cache=/private/tmp/cascade-spotlight-test-module-cache
mkdir -p "$module_cache"
DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun swiftc \
    -swift-version 6 -default-isolation MainActor -warnings-as-errors \
    -module-cache-path "$module_cache" -parse-as-library \
    -D SPOTLIGHT_BEHAVIOR_TESTS \
    "$project_directory/Cascade/Core/Spotlight/SpotlightHandoffState.swift" \
    "$project_directory/Cascade/Models/Spotlight/SpotlightShortcut.swift" \
    "$project_directory/Cascade/Core/Spotlight/SpotlightAXOperationGate.swift" \
    "$project_directory/Cascade/Core/Protocols/SpotlightKeyTapping.swift" \
    "$project_directory/Cascade/Core/Spotlight/SpotlightKeyGate.swift" \
    "$project_directory/Cascade/Core/Spotlight/SpotlightKeyTap.swift" \
    "$project_directory/Cascade/Core/Input/EventTapThread.swift" \
    "$project_directory/Cascade/Checks/Spotlight/SpotlightBehaviorChecks.swift" \
    -o /private/tmp/cascade-spotlight-behavior-tests
/private/tmp/cascade-spotlight-behavior-tests
