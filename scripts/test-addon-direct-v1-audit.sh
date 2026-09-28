#!/bin/zsh
set -euo pipefail
source_dir=${0:A:h:h}/Prototypes/AddonPlatform/DirectV1
products=$(mktemp -d /private/tmp/cascade-direct-v1-audit.XXXXXX)
identity=${CASCADE_PROBE_SIGN_IDENTITY:-4A857D842A5406C2D3071776FDE7B27B3098FE63}
label="hylo.Cascade.DirectV1.Audit.$(uuidgen)"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
cp "$source_dir/../DirectChild/Info.plist" "$products/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier hylo.Cascade.DirectV1.AuditWorker' "$products/Info.plist"
xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 -framework Security -framework CoreFoundation -lbsm -Wl,-sectcreate,__TEXT,__info_plist,"$products/Info.plist" "$source_dir/AuditProbe.c" -o "$products/AuditServer"
cp "$products/AuditServer" "$products/AuditWorker"
cp "$products/AuditServer" "$products/AuditReplacement"
cp "$source_dir/../DirectChild/Worker.entitlements" "$products/Worker.entitlements"
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.temporary-exception.mach-lookup.global-name array' "$products/Worker.entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.temporary-exception.mach-lookup.global-name:0 string $label" "$products/Worker.entitlements"
cp "$source_dir/../DirectChild/Worker.entitlements" "$products/Replacement.entitlements"
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.inherit bool true' "$products/Replacement.entitlements"
codesign --force --timestamp=none --options runtime --sign "$identity" --identifier hylo.Cascade.DirectV1.AuditServer "$products/AuditServer"
codesign --force --timestamp=none --options runtime --sign "$identity" --identifier hylo.Cascade.DirectV1.AuditWorker --entitlements "$products/Worker.entitlements" "$products/AuditWorker"
codesign --force --timestamp=none --options runtime --sign "$identity" --identifier hylo.Cascade.DirectV1.AuditReplacement --entitlements "$products/Replacement.entitlements" "$products/AuditReplacement"
for binary in AuditServer AuditWorker AuditReplacement; do codesign --verify --strict "$products/$binary"; done
print "Products: $products"
python3 "$source_dir/run_audit.py" "$products" "$label"
