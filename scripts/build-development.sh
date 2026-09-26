#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
derived_directory=${CASCADE_DERIVED_DATA:-${HOME}/Library/Developer/Xcode/DerivedData/CascadeDevelopment}

DEVELOPER_DIR="$developer_directory" /bin/zsh "$script_directory/check-addon-boundaries.sh" \
    --root "$project_directory"

# Use the target's Apple Development identity. Ad-hoc signing binds TCC to a
# single cdhash and invalidates the previous build's Accessibility authorization.
DEVELOPER_DIR="$developer_directory" /usr/bin/xcodebuild \
    -project "$project_directory/Cascade.xcodeproj" \
    -scheme Cascade \
    -configuration Debug \
    -derivedDataPath "$derived_directory" \
    build

/usr/bin/codesign --verify --deep --strict \
    "$derived_directory/Build/Products/Debug/Cascade.app"

# Also run explicitly so a post-action failure cannot be hidden by Xcode.
/bin/zsh "$script_directory/update-application-link.sh" \
    "$derived_directory/Build/Products/Debug/Cascade.app"
