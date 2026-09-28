#!/bin/zsh
set -euo pipefail
script_directory=${0:A:h}
probe_source=${script_directory:h}/Prototypes/AddonPlatform/DirectChild
probe_products=${CASCADE_DIRECT_CHILD_PRODUCTS:-${HOME}/Library/Developer/Xcode/DerivedData/CascadeAddonDirectChild/Products}
probe_identity=${CASCADE_PROBE_SIGN_IDENTITY:-4A857D842A5406C2D3071776FDE7B27B3098FE63}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
mkdir -p "$probe_products/DirectWorker.app/Contents/MacOS" "$probe_source/Results"
for program in Host Supervisor Worker; do
    target="$probe_products/Direct$program"
    framework_arguments=()
    [[ "$program" == Worker ]] && target="$probe_products/DirectWorker.app/Contents/MacOS/DirectWorker"
    [[ "$program" == Worker ]] && framework_arguments=(-framework CoreServices)
    /usr/bin/xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 \
        "$probe_source/$program.c" "${framework_arguments[@]}" -o "$target"
done
/bin/cp "$probe_products/DirectWorker.app/Contents/MacOS/DirectWorker" "$probe_products/DirectWorker.app/Contents/MacOS/DirectWorker-replacement"
/bin/cp "$probe_source/Worker.entitlements" "$probe_products/Replacement.entitlements"
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.inherit bool true' "$probe_products/Replacement.entitlements"
/usr/bin/codesign --force --timestamp=none --options runtime --sign "$probe_identity" \
    --entitlements "$probe_products/Replacement.entitlements" \
    --identifier hylo.Cascade.AddonDirectChildProbe.Replacement "$probe_products/DirectWorker.app/Contents/MacOS/DirectWorker-replacement"
launch_fixture="$probe_products/DirectWorker.app/Contents/Resources/LaunchFixture.app"
mkdir -p "$launch_fixture/Contents/MacOS"
/usr/bin/xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 \
    -fobjc-arc "$probe_source/LaunchFixture.m" -framework Foundation \
    -o "$launch_fixture/Contents/MacOS/LaunchFixture"
/bin/cp "$probe_source/Info.plist" "$launch_fixture/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier hylo.Cascade.AddonDirectChildProbe.LaunchFixture' "$launch_fixture/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable LaunchFixture' "$launch_fixture/Contents/Info.plist"
/usr/bin/codesign --force --timestamp=none --options runtime --sign "$probe_identity" "$launch_fixture"
/bin/cp "$probe_source/Info.plist" "$probe_products/DirectWorker.app/Contents/Info.plist"
/usr/bin/codesign --force --timestamp=none --options runtime --sign "$probe_identity" \
    --entitlements "$probe_source/Worker.entitlements" "$probe_products/DirectWorker.app"
for program in Host Supervisor; do
    /usr/bin/codesign --force --timestamp=none --options runtime --sign "$probe_identity" \
        --identifier "hylo.Cascade.AddonDirectChildProbe.$program" "$probe_products/Direct$program"
done
/usr/bin/codesign --verify --deep --strict "$probe_products/DirectWorker.app"
/usr/bin/codesign --display --entitlements - --verbose=2 "$probe_products/DirectWorker.app" \
    > "$probe_source/Results/signature.txt" 2>&1
/usr/bin/python3 "$probe_source/run.py" "$probe_products" \
    | /usr/bin/tee "$probe_source/Results/latest.jsonl"
