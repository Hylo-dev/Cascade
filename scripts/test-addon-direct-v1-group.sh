#!/bin/zsh
set -euo pipefail
source_dir=${0:A:h:h}/Prototypes/AddonPlatform/DirectV1
products=$(mktemp -d /private/tmp/cascade-direct-v1-group.XXXXXX)
identity=${CASCADE_PROBE_SIGN_IDENTITY:-4A857D842A5406C2D3071776FDE7B27B3098FE63}
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 "$source_dir/GroupProbe.c" -o "$products/GroupHelper"
cp "$source_dir/../DirectChild/Info.plist" "$products/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier hylo.Cascade.DirectV1.Worker' "$products/Info.plist"
xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 -Wl,-sectcreate,__TEXT,__info_plist,"$products/Info.plist" "$source_dir/GroupProbe.c" -o "$products/GroupWorker"
codesign --force --timestamp=none --options runtime --sign "$identity" --identifier hylo.Cascade.DirectV1.Helper "$products/GroupHelper"
codesign --force --timestamp=none --options runtime --sign "$identity" --entitlements "$source_dir/../DirectChild/Worker.entitlements" --identifier hylo.Cascade.DirectV1.Worker "$products/GroupWorker"
codesign --verify --strict "$products/GroupWorker"
print "Products: $products"
python3 "$source_dir/run_group.py" "$products"
