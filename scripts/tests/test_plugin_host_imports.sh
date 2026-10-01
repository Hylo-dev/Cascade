#!/bin/zsh
# Checks that check-plugin-host-imports.sh refuses every way Swift spells an import of a module
# PluginHost may not use, and accepts the allowed ones.
set -euo pipefail

script="${0:A:h:h}/check-plugin-host-imports.sh"
directory=$(mktemp -d "${TMPDIR:-/private/tmp}/plugin-host-imports.XXXXXX")
trap 'rm -rf -- "$directory"' EXIT
failed=0

expect() {
    local outcome=$1 source=$2
    rm -f -- "$directory"/*.swift(N)
    print -r -- "$source" > "$directory/Probe.swift"
    if "$script" "$directory" 2>/dev/null; then verdict=accepted; else verdict=refused; fi
    if [[ $verdict != $outcome ]]; then
        print -u2 "expected $outcome, got $verdict: $source"
        failed=1
    fi
}

expect accepted 'import CascadePluginHost'
expect accepted 'import Foundation.NSString'
expect accepted '@preconcurrency import Dispatch'
expect refused  'import CascadePluginEngine'
expect refused  'internal import CascadePluginEngine'
expect refused  'public import SwiftUI'
expect refused  '@_spi(Testing) import CascadePluginEngine'
expect refused  'import Foundation; import AppKit'
expect refused  'import `CascadeKit`'
expect refused  'import struct CascadeKit.GridSpan'

exit $failed
