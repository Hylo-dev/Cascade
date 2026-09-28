#!/bin/zsh
set -euo pipefail
script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
module_cache=/private/tmp/cascade-spotlight-test-module-cache
mkdir -p "$module_cache"
DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun swiftc \
    -swift-version 6 -default-isolation MainActor -warnings-as-errors \
    -module-cache-path "$module_cache" -parse-as-library \
    -D SPOTLIGHT_BEHAVIOR_TESTS \
    "$project_directory/Cascade/Integrations/Spotlight/SpotlightHandoffState.swift" \
    "$project_directory/Cascade/Integrations/Spotlight/SpotlightShortcut.swift" \
    "$project_directory/Cascade/Integrations/Spotlight/SpotlightAXOperationGate.swift" \
    "$project_directory/Cascade/Integrations/Spotlight/Tests/SpotlightBehaviorChecks.swift" \
    -o /private/tmp/cascade-spotlight-behavior-tests
/private/tmp/cascade-spotlight-behavior-tests
