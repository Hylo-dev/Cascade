#!/bin/zsh
# PluginHost may import only the plugin SDK, the contracts, the host library built on them and
# system modules (plugin engine spec §12). Pass another directory to check it instead.
set -euo pipefail

directory=${1:-${0:A:h:h}/PluginHost}
allowed=(CascadePluginHost CascadePluginSDK CascadeContracts Foundation Darwin Dispatch Synchronization Security)
failed=0
for file in "$directory"/**/*.swift(N); do
    for module in $(sed -nE 's/^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((class|struct|enum|protocol|func|var|let|typealias)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\4/p' "$file"); do
        if (( ! ${allowed[(Ie)$module]} )); then
            print -u2 "${file#$directory/}: PluginHost must not import $module"
            failed=1
        fi
    done
done
exit $failed
