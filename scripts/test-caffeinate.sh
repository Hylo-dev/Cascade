#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
check_directory=$(mktemp -d "${TMPDIR:-/private/tmp}/cascade-caffeinate.XXXXXX")
trap 'rm -rf -- "$check_directory"' EXIT

xcrun swiftc -swift-version 6 -target arm64-apple-macos15.0 \
    -module-cache-path "$check_directory/modules" -parse-as-library \
    "$project_directory/Cascade/Core/Caffeinate/CaffeinateAssertionManaging.swift" \
    "$project_directory/Cascade/Core/Caffeinate/CaffeinateFailure.swift" \
    "$project_directory/Cascade/Core/Caffeinate/CaffeinateSessionSnapshot.swift" \
    "$project_directory/Cascade/Core/Caffeinate/CaffeinateSession.swift" \
    "$project_directory/Cascade/Core/Caffeinate/IOKitCaffeinateAssertions.swift" \
    "$script_directory/verify-caffeinate.swift" -o "$check_directory/check"

"$check_directory/check" "$@"
