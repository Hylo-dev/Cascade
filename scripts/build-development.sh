#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
developer_directory=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
derived_directory=${CASCADE_DERIVED_DATA:-${HOME}/Library/Developer/Xcode/DerivedData/CascadeDevelopment}

DEVELOPER_DIR="$developer_directory" /bin/zsh "$script_directory/check-addon-boundaries.sh" \
    --root "$project_directory"

# Signing comes from Config/Signing.xcconfig: ad hoc on a fresh clone, or your
# Apple Development identity once Config/Signing.local.xcconfig sets a team.
# Ad-hoc signing binds TCC to a single cdhash, so Accessibility is re-asked
# after every rebuild until a team is configured.
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
