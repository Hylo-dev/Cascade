#!/bin/zsh
set -euo pipefail
script_directory=${0:A:h}
prototype_directory=${script_directory:h}/Prototypes/AddonPlatform
probe_derived_data=${CASCADE_PROBE_DERIVED_DATA:-${HOME}/Library/Developer/Xcode/DerivedData/CascadeAddonPlatform}
probe_configuration=${CASCADE_PROBE_CONFIGURATION:-Debug}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
probe_case=${2:-}
if [[ ${1:-} != --case || "$probe_configuration" != (Debug|Release) || "$probe_case" != (standalone-echo|lifecycle|application-stop|sandbox|malformed|browser) ]]; then
    print -u2 'Usage: test-addon-platform.sh --case standalone-echo|lifecycle|application-stop|sandbox|malformed|browser'
    exit 64
fi
mkdir -p "$prototype_directory/Results"
/usr/bin/xcrun xcodebuild -project "$prototype_directory/AddonPlatform.xcodeproj" \
    -scheme AddonPlatform -configuration "$probe_configuration" -derivedDataPath "$probe_derived_data" build \
    > "$prototype_directory/Results/build.log" 2>&1
probe_products="$probe_derived_data/Build/Products/$probe_configuration"
host_app="$probe_products/CascadeAddonProbe.app"
container_app="$probe_products/CascadeAddonProbeContainer.app"
/usr/bin/codesign --verify --deep --strict "$host_app"
/usr/bin/codesign --verify --deep --strict "$container_app"
# Avoid accidentally measuring another configuration of this exact test fixture.
other_configuration=Release
[[ "$probe_configuration" == Release ]] && other_configuration=Debug
other_container="$probe_derived_data/Build/Products/$other_configuration/CascadeAddonProbeContainer.app"
if [[ -d "$other_container" ]] && /usr/bin/pluginkit -m -A -D -vv -i hylo.Cascade.AddonProbeContainer.Provider 2>/dev/null | /usr/bin/grep -Fq -- "$other_container"; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$other_container"
fi
/usr/bin/open -g "$container_app"
if [[ "$probe_case" == browser ]]; then
    /usr/bin/open "$host_app" --args --browse
elif [[ "$probe_case" == application-stop ]]; then
    /usr/bin/python3 "$prototype_directory/Tests/run_lifecycle.py" "$host_app/Contents/MacOS/ProbeHost" application-stop-spin \
        | /usr/bin/tee "$prototype_directory/Results/$probe_configuration-application-stop.jsonl"
elif [[ "$probe_case" == lifecycle ]]; then
    /usr/bin/python3 "$prototype_directory/Tests/run_lifecycle.py" "$host_app/Contents/MacOS/ProbeHost" \
        | /usr/bin/tee "$prototype_directory/Results/$probe_configuration-lifecycle.jsonl"
else
    /usr/bin/python3 "$prototype_directory/Tests/run_request.py" "$host_app/Contents/MacOS/ProbeHost" "$probe_case" \
        | /usr/bin/tee "$prototype_directory/Results/$probe_configuration-$probe_case.jsonl"
fi
