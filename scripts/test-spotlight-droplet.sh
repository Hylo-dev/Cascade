#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
export CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-spotlight-droplet-module-cache
check_directory=$(mktemp -d /private/tmp/cascade-spotlight-droplet-checks.XXXXXX)
trap 'rm -rf "$check_directory"' EXIT

/usr/bin/xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
    -default-isolation MainActor -warnings-as-errors -parse-as-library \
    -D SPOTLIGHT_DROPLET_TESTS \
    "$project_directory/Cascade/Views/Spotlight/SpotlightDropletGlassView.swift" \
    "$project_directory/Cascade/Core/Spotlight/SpotlightDropletLayout.swift" \
    "$project_directory/Cascade/Views/Spotlight/SpotlightDropletPanel.swift" \
    "$project_directory/Cascade/Core/Extensions/NSScreen+RuntimeDisplayID.swift" \
    "$project_directory/Cascade/Models/Spotlight/SpotlightDisplayAnchor.swift" \
    "$project_directory/Cascade/Core/Protocols/SpotlightDropletPresenting.swift" \
    "$project_directory/Cascade/Models/Spotlight/SpotlightDropletFrame.swift" \
    "$project_directory/Cascade/Core/Spotlight/SpotlightDropletTimeline.swift" \
    "$project_directory/Cascade/Views/Spotlight/SpotlightDropletWindow.swift" \
    "$project_directory/Cascade/Checks/Spotlight/SpotlightDropletChecks.swift" \
    -o "$check_directory/spotlight-droplet-checks"

"$check_directory/spotlight-droplet-checks"
