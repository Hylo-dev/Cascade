#!/bin/zsh
#
# test-addon-tracing.sh
# Cascade
#
set -euo pipefail
source_dir=${0:A:h:h}/Prototypes/AddonPlatform/Tracing
products=$(mktemp -d /private/tmp/cascade-tracing-untraced-XXXXXX)
identity=4A857D842A5406C2D3071776FDE7B27B3098FE63
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
exec > >(tee "$products/build-run.log") 2>&1
print "Products: $products"
trap 'result=$?; print "Script exit: $result"; if [[ ! -f "$products/report.json" ]]; then print "{\"result\":\"unknown\",\"nativeLauncherAdmitted\":false,\"setupExit\":$result}" > "$products/report.json"; fi' EXIT
set -x
sw_vers > "$products/os.txt"
uname -a >> "$products/os.txt"
xcrun --show-sdk-path > "$products/sdk.txt"
xcrun --show-sdk-version >> "$products/sdk.txt"
xcrun clang --version > "$products/compiler.txt"
python3 -c 'import sys; print(sys.executable)' > "$products/observer.txt"
codesign -dvvv "$(python3 -c 'import sys; print(sys.executable)')" >> "$products/observer.txt" 2>&1 || true
for role in Supervisor Stub Worker; do
    cp "$source_dir/Info.plist" "$products/$role.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier hylo.Cascade.Tracing.$role" "$products/$role.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Trace$role" "$products/$role.plist"
    xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 \
        -DPROBE_ROLE=\"$role\" -DSIGNER_HASH=\"$identity\" \
        -Wl,-sectcreate,__TEXT,__info_plist,"$products/$role.plist" \
        "$source_dir/TraceProbe.c" -framework Security -framework CoreFoundation -o "$products/Trace$role"
    if [[ "$role" == Supervisor ]]; then
        codesign --force --timestamp=none --options runtime --sign "$identity" --identifier "hylo.Cascade.Tracing.$role" "$products/Trace$role"
    else
        codesign --force --timestamp=none --options runtime --sign "$identity" --entitlements "$source_dir/Worker.entitlements" --identifier "hylo.Cascade.Tracing.$role" "$products/Trace$role"
    fi
    codesign --verify --strict "$products/Trace$role"
    codesign -dvvv --entitlements - --xml "$products/Trace$role" > "$products/$role-signature.txt" 2>&1
    shasum -a 256 "$products/Trace$role" >> "$products/hashes.txt"
done
python3 "$source_dir/run.py" "$products"
