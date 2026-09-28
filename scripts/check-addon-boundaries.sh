#!/bin/zsh
# Audit trusted development manifests and source imports with the selected Xcode.
set -euo pipefail

script_dir="${0:A:h}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
fi
swiftc_path="$(xcrun --find swiftc)"
swift_path="$(xcrun --find swift)"
sdk_path="$(xcrun --show-sdk-path)"
host_libraries="${swiftc_path:h:h}/lib/swift/host"
if [[ ! -d "$host_libraries/SwiftParser.swiftmodule" ]]; then
    print -u2 'The selected toolchain must provide SwiftParser and SwiftSyntax host libraries.'
    exit 1
fi
task_directory="$(mktemp -d "${TMPDIR:-/private/tmp}/cascade-addon-boundaries.XXXXXX")"
trap 'rm -rf -- "$task_directory"' EXIT
"$swiftc_path" -sdk "$sdk_path" -I "$host_libraries" -L "$host_libraries" \
    -lSwiftParser -lSwiftSyntax -Xlinker -rpath -Xlinker "$host_libraries" \
    -module-cache-path "$task_directory/scanner-modules" \
    "$script_dir/check-addon-imports.swift" -o "$task_directory/scanner"
if [[ "${1:-}" == --test ]]; then
    shift
    CASCADE_BOUNDARY_SCANNER="$task_directory/scanner" CASCADE_BOUNDARY_SWIFT="$swift_path" \
        python3 "$script_dir/tests/test_addon_boundaries.py" "$@"
else
    python3 "$script_dir/check_addon_boundaries.py" \
        --scanner "$task_directory/scanner" --swift "$swift_path" \
        --cache-root "$task_directory/packages" "$@"
fi
