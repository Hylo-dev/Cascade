#!/bin/zsh
# PluginHost may import only the plugin SDK, the contracts, the host library built on them and
# system modules (plugin engine spec §12). Pass another directory to check it instead.
set -euo pipefail

directory=${1:-${0:A:h:h}/PluginHost}
allowed=(CascadePlugins CascadePluginHost CascadePluginSDK CascadeContracts Foundation Darwin Dispatch Synchronization Security)
failed=0
for file in "$directory"/**/*.swift(N); do
    # One import per statement, whatever its attributes (with arguments, as in @_spi(Name)), its
    # access level (Swift 6 writes internal import), its declaration kind or its backticks.
    for module in $(tr ';' '\n' < "$file" | sed -nE 's/^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((class|struct|enum|protocol|func|var|let|typealias)[[:space:]]+)?`?([A-Za-z_][A-Za-z0-9_]*)`?.*/\7/p'); do
        if (( ! ${allowed[(Ie)$module]} )); then
            print -u2 "${file#$directory/}: PluginHost must not import $module"
            failed=1
        fi
    done
done
exit $failed
