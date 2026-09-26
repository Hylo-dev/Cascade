#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
manifest_path=${CASCADE_FFMPEG_MANIFEST:-${project_directory}/Config/FFmpeg/manifest.json}
expected_architecture=""
require_signature=false

function usage {
    print -u2 "Usage: $0 <helper-directory> [--arch arm64|x86_64] [--manifest <path>] [--require-signature]"
}

function fail {
    print -u2 "FFmpeg verification failed: $1"
    exit 1
}

if (( $# < 1 )); then
    usage
    exit 64
fi

helper_directory=$1
shift

while (( $# > 0 )); do
    case $1 in
        --arch)
            (( $# >= 2 )) || fail "--arch requires a value"
            expected_architecture=$2
            shift 2
            ;;
        --manifest)
            (( $# >= 2 )) || fail "--manifest requires a path"
            manifest_path=$2
            shift 2
            ;;
        --require-signature)
            require_signature=true
            shift
            ;;
        *)
            usage
            fail "unknown argument: $1"
            ;;
    esac
done

[[ -f "$manifest_path" ]] || fail "manifest not found: $manifest_path"
[[ -d "$helper_directory" ]] || fail "helper directory not found: $helper_directory"

function manifest_value {
    /usr/bin/plutil -extract "$1" raw -o - "$manifest_path" 2>/dev/null \
        || fail "manifest field is missing: $1"
}

expected_version=$(manifest_value version)
expected_deployment_target=$(manifest_value deploymentTarget)
if [[ -z "$expected_architecture" ]]; then
    expected_architecture=$(manifest_value deliveredArchitectures.0)
fi

if [[ "$expected_architecture" != arm64 && "$expected_architecture" != x86_64 ]]; then
    fail "unsupported expected architecture: $expected_architecture"
fi

function verify_helper_structure {
    local helper_name=$1
    local helper_path=${helper_directory}/${helper_name}

    [[ -f "$helper_path" ]] || fail "Missing FFmpeg helper: $helper_name"
    [[ -x "$helper_path" ]] || fail "FFmpeg helper is not executable: $helper_name"

    local architectures
    architectures=$(/usr/bin/lipo -archs "$helper_path" 2>/dev/null) \
        || fail "$helper_name is not a Mach-O executable"
    [[ "$architectures" == "$expected_architecture" ]] \
        || fail "$helper_name must be thin '$expected_architecture', found '$architectures'"

    local minimum_version
    minimum_version=$(/usr/bin/vtool -show-build "$helper_path" 2>/dev/null \
        | /usr/bin/awk '$1 == "minos" { print $2; exit }')
    [[ "$minimum_version" == "$expected_deployment_target" ]] \
        || fail "$helper_name has minimum macOS '$minimum_version', expected '$expected_deployment_target'"

    local dependency
    while IFS= read -r dependency; do
        dependency=$(print -r -- "$dependency" \
            | /usr/bin/sed -E 's/^[[:space:]]*//; s/[[:space:]]+\(compatibility version.*$//')
        [[ -z "$dependency" ]] && continue
        case "$dependency" in
            /usr/lib/*|/System/Library/Frameworks/*) ;;
            *) fail "$helper_name has non-system dynamic dependency: $dependency" ;;
        esac
    done < <(/usr/bin/otool -L "$helper_path" | /usr/bin/tail -n +2)

    if $require_signature; then
        /usr/bin/codesign --verify --strict "$helper_path" 2>/dev/null \
            || fail "$helper_name does not have a valid code signature"
    fi
}

verify_helper_structure ffmpeg
verify_helper_structure ffprobe

ffmpeg_path=${helper_directory}/ffmpeg
ffprobe_path=${helper_directory}/ffprobe

ffmpeg_version=$("$ffmpeg_path" -version 2>/dev/null | /usr/bin/head -n 1)
ffprobe_version=$("$ffprobe_path" -version 2>/dev/null | /usr/bin/head -n 1)
[[ "$ffmpeg_version" == "ffmpeg version ${expected_version} "* ]] \
    || fail "ffmpeg version differs from manifest: $ffmpeg_version"
[[ "$ffprobe_version" == "ffprobe version ${expected_version} "* ]] \
    || fail "ffprobe version differs from manifest: $ffprobe_version"

build_configuration=$("$ffmpeg_path" -buildconf 2>&1)
for required_flag in \
    --disable-autodetect \
    --disable-ffplay \
    --disable-network \
    --disable-gpl \
    --disable-nonfree \
    --enable-videotoolbox; do
    [[ "$build_configuration" == *"$required_flag"* ]] \
        || fail "ffmpeg build configuration is missing $required_flag"
done
[[ "$build_configuration" != *"--enable-gpl"* ]] \
    || fail "ffmpeg build configuration enables GPL components"
[[ "$build_configuration" != *"--enable-nonfree"* ]] \
    || fail "ffmpeg build configuration enables nonfree components"

encoder_list=$("$ffmpeg_path" -hide_banner -encoders 2>&1)
for required_encoder in aac flac pcm_s16le h264_videotoolbox; do
    print -r -- "$encoder_list" \
        | /usr/bin/grep -Eq "^[[:space:]][A-Z.]{6}[[:space:]]+${required_encoder}([[:space:]]|$)" \
        || fail "ffmpeg encoder is missing: $required_encoder"
done

if [[ -n ${CASCADE_FFMPEG_VERIFY_SCRATCH:-} ]]; then
    scratch_root=${CASCADE_FFMPEG_VERIFY_SCRATCH:A}
    /bin/mkdir -p "$scratch_root"
    scratch_directory=$(/usr/bin/mktemp -d "${scratch_root}/run.XXXXXX")
else
    scratch_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cascade-ffmpeg-verify.XXXXXX")
fi
function cleanup {
    /bin/rm -rf "$scratch_directory"
}
trap cleanup EXIT

fixture_path=${scratch_directory}/fixture.mp4
"$ffmpeg_path" \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -f lavfi \
    -i "testsrc2=size=64x64:rate=1:duration=1" \
    -f lavfi \
    -i "sine=frequency=1000:sample_rate=48000:duration=1" \
    -c:v h264_videotoolbox \
    -pix_fmt nv12 \
    -b:v 200k \
    -c:a aac \
    -b:a 64k \
    -shortest \
    -movflags +faststart \
    "$fixture_path" \
    || fail "H.264 VideoToolbox/AAC fixture conversion failed"

probe_output=$("$ffprobe_path" \
    -v error \
    -show_entries stream=codec_name,codec_type \
    -of csv=p=0 \
    "$fixture_path") \
    || fail "ffprobe could not read the generated fixture"
[[ "$probe_output" == *"h264,video"* ]] \
    || fail "fixture does not contain readable H.264 video"
[[ "$probe_output" == *"aac,audio"* ]] \
    || fail "fixture does not contain readable AAC audio"

print "Verified FFmpeg ${expected_version} (${expected_architecture}, macOS ${expected_deployment_target})"
print "Verified encoders: h264_videotoolbox, aac, flac, pcm_s16le"
print "Verified fixture: H.264 VideoToolbox + AAC in MP4, readable by ffprobe"
