#!/bin/zsh

set -euo pipefail

# Shared by the Xcode scheme's successful-build post-action and the CLI build.
app_path=${1:?Pass the built Cascade.app path}
app_path=${app_path:A}
applications_directory=${CASCADE_APPLICATIONS_DIRECTORY:-/Applications}
destination="$applications_directory/Cascade.app"

if [[ ! -x "$app_path/Contents/MacOS/Cascade" ]] || \
   [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist")" != hylo.Cascade ]]; then
    print -u2 "error: A complete Cascade build is required: $app_path"
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_path"

if [[ "$app_path" == "$destination" ]]; then
    exit 0
fi
if [[ -e "$destination" && ! -L "$destination" ]]; then
    print -u2 "error: $destination is a real app, not the managed Cascade shortcut. It was left untouched."
    exit 1
fi

/bin/mkdir -p "$applications_directory"
/bin/ln -sfn "$app_path" "$destination"
[[ "$(/usr/bin/readlink "$destination")" == "$app_path" ]]
print "Cascade shortcut updated: $destination -> $app_path"
