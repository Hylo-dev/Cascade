#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
manifest_path=${project_directory}/Config/FFmpeg/manifest.json
source_cache=${CASCADE_FFMPEG_SOURCE_CACHE:-${project_directory}/Config/FFmpeg/Downloads}
output_directory=""
target_architecture=""
parallel_jobs=${CASCADE_FFMPEG_JOBS:-4}

function usage {
    print -u2 "Usage: $0 --output <directory> --arch arm64|x86_64 [--source-cache <directory>] [--jobs 1-8]"
}

function fail {
    print -u2 "FFmpeg build failed: $1"
    exit 1
}

while (( $# > 0 )); do
    case $1 in
        --output)
            (( $# >= 2 )) || fail "--output requires a directory"
            output_directory=$2
            shift 2
            ;;
        --arch)
            (( $# >= 2 )) || fail "--arch requires arm64 or x86_64"
            target_architecture=$2
            shift 2
            ;;
        --source-cache)
            (( $# >= 2 )) || fail "--source-cache requires a directory"
            source_cache=$2
            shift 2
            ;;
        --jobs)
            (( $# >= 2 )) || fail "--jobs requires a value"
            parallel_jobs=$2
            shift 2
            ;;
        *)
            usage
            fail "unknown argument: $1"
            ;;
    esac
done

[[ -n "$output_directory" ]] || { usage; fail "--output is required"; }
[[ "$target_architecture" == arm64 || "$target_architecture" == x86_64 ]] \
    || { usage; fail "--arch must be arm64 or x86_64"; }
[[ "$parallel_jobs" == <-> ]] || fail "--jobs must be an integer from 1 through 8"
(( parallel_jobs >= 1 && parallel_jobs <= 8 )) \
    || fail "--jobs must be an integer from 1 through 8"
[[ -f "$manifest_path" ]] || fail "manifest not found: $manifest_path"

function manifest_value {
    /usr/bin/plutil -extract "$1" raw -o - "$manifest_path" 2>/dev/null \
        || fail "manifest field is missing: $1"
}

version=$(manifest_value version)
source_url=$(manifest_value source.url)
source_sha256=$(manifest_value source.sha256)
signature_url=$(manifest_value source.signatureURL)
signature_sha256=$(manifest_value source.signatureSHA256)
signing_key_url=$(manifest_value source.signingKeyURL)
signing_key_sha256=$(manifest_value source.signingKeySHA256)
signing_fingerprint=$(manifest_value source.signingFingerprint)
deployment_target=$(manifest_value deploymentTarget)

while [[ "$output_directory" != / && "$output_directory" == */ ]]; do
    output_directory=${output_directory%/}
done
function validate_output_directory {
    [[ ! -L "$output_directory" ]] || fail "output must not be a symbolic link"
    [[ ! -e "$output_directory" || -d "$output_directory" ]] \
        || fail "output must be a dedicated directory"
    [[ ! -d "$output_directory" ]] && return

    local unexpected_output
    unexpected_output=$(/usr/bin/find "$output_directory" \
        -mindepth 1 \
        -maxdepth 1 \
        ! -name ffmpeg \
        ! -name ffprobe \
        -print \
        -quit)
    [[ -z "$unexpected_output" ]] \
        || fail "output directory contains unrelated files: $unexpected_output"

    local helper_name
    local helper_path
    for helper_name in ffmpeg ffprobe; do
        helper_path=${output_directory}/${helper_name}
        if [[ -e "$helper_path" || -L "$helper_path" ]]; then
            [[ -f "$helper_path" && ! -L "$helper_path" ]] \
                || fail "existing $helper_name output must be a regular non-symbolic-link file"
        fi
    done
}

validate_output_directory
source_cache=${source_cache:A}
output_directory=${output_directory:A}
/bin/mkdir -p "$source_cache" "${output_directory:h}"

tarball_path=${source_cache}/ffmpeg-${version}.tar.xz
signature_path=${tarball_path}.asc
signing_key_path=${source_cache}/ffmpeg-devel.asc

function download_if_missing {
    local url=$1
    local destination=$2

    [[ -f "$destination" ]] && return
    local temporary_path=${destination}.download
    /usr/bin/curl \
        --fail \
        --location \
        --proto '=https' \
        --tlsv1.2 \
        --output "$temporary_path" \
        "$url" \
        || fail "download failed: $url"
    /bin/mv "$temporary_path" "$destination"
}

download_if_missing "$source_url" "$tarball_path"
download_if_missing "$signature_url" "$signature_path"
download_if_missing "$signing_key_url" "$signing_key_path"

function verify_sha256 {
    local artifact_path=$1
    local expected_hash=$2
    local actual_hash
    actual_hash=$(/usr/bin/shasum -a 256 "$artifact_path" | /usr/bin/awk '{ print $1 }')
    [[ "$actual_hash" == "$expected_hash" ]] \
        || fail "SHA-256 mismatch for ${artifact_path:t}: expected $expected_hash, got $actual_hash"
}

verify_sha256 "$tarball_path" "$source_sha256"
verify_sha256 "$signature_path" "$signature_sha256"
verify_sha256 "$signing_key_path" "$signing_key_sha256"

gpg_path=${CASCADE_GPG:-/opt/homebrew/bin/gpg}
gpgv_path=${CASCADE_GPGV:-/opt/homebrew/bin/gpgv}
[[ -x "$gpg_path" && -x "$gpgv_path" ]] \
    || fail "GnuPG is required only to authenticate the source build (expected $gpg_path and $gpgv_path)"

verification_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cascade-ffmpeg-pgp.XXXXXX")
build_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cascade-ffmpeg-build.XXXXXX")
replacement_directory=""
function cleanup {
    /bin/rm -rf "$verification_directory" "$build_directory"
    if [[ -n "$replacement_directory" && -e "$replacement_directory" ]]; then
        /bin/rm -rf "$replacement_directory"
    fi
}
trap cleanup EXIT

/bin/chmod 700 "$verification_directory"
actual_fingerprint=$("$gpg_path" \
    --homedir "$verification_directory" \
    --batch \
    --with-colons \
    --show-keys \
    --fingerprint \
    "$signing_key_path" 2>/dev/null \
    | /usr/bin/awk -F: '$1 == "fpr" { print $10; exit }')
[[ "$actual_fingerprint" == "$signing_fingerprint" ]] \
    || fail "release signing fingerprint mismatch: $actual_fingerprint"

keyring_path=${verification_directory}/ffmpeg-release-key.gpg
"$gpg_path" \
    --homedir "$verification_directory" \
    --batch \
    --yes \
    --dearmor \
    --output "$keyring_path" \
    "$signing_key_path" \
    || fail "could not create isolated release keyring"

signature_status=$("$gpgv_path" \
    --keyring "$keyring_path" \
    --status-fd 1 \
    "$signature_path" \
    "$tarball_path" 2>&1) \
    || fail "official FFmpeg release signature is invalid"
[[ "$signature_status" == *"[GNUPG:] VALIDSIG ${signing_fingerprint} "* ]] \
    || fail "signature did not produce the pinned VALIDSIG fingerprint"

source_directory=${build_directory}/ffmpeg-${version}
install_directory=${build_directory}/install
/usr/bin/tar -xf "$tarball_path" -C "$build_directory"
[[ -x "$source_directory/configure" ]] || fail "authenticated archive has no executable configure script"

developer_directory=${CASCADE_DEVELOPER_DIR:-${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}}
[[ -d "$developer_directory" ]] || fail "Xcode developer directory not found: $developer_directory"
clang_path=$(DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun --sdk macosx --find clang)
sdk_path=$(DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun --sdk macosx --show-sdk-path)
configure_architecture=$target_architecture
[[ "$target_architecture" == arm64 ]] && configure_architecture=aarch64

configure_arguments=(
    "--prefix=$install_directory"
    "--cc=$clang_path"
    "--arch=$configure_architecture"
    "--target-os=darwin"
    "--sysroot=$sdk_path"
    "--extra-cflags=-arch $target_architecture -mmacosx-version-min=$deployment_target"
    "--extra-ldflags=-arch $target_architecture -mmacosx-version-min=$deployment_target"
    --disable-autodetect
    --disable-debug
    --disable-doc
    --disable-ffplay
    --disable-network
    --disable-gpl
    --disable-nonfree
    --disable-shared
    --enable-static
    --enable-videotoolbox
    --disable-encoders
    --enable-encoder=aac,flac,pcm_s16le,h264_videotoolbox
    --disable-muxers
    --enable-muxer=mov,mp4,ipod,flac,wav
    --disable-outdevs
    --disable-indevs
    --enable-indev=lavfi
)

if [[ "$target_architecture" == x86_64 ]]; then
    configure_arguments+=(--enable-cross-compile --disable-x86asm)
fi

print "Authenticated FFmpeg ${version} source with ${signing_fingerprint}"
print "Configuring ${target_architecture} for macOS ${deployment_target}"
(
    cd "$source_directory"
    export MACOSX_DEPLOYMENT_TARGET=$deployment_target
    export SDKROOT=$sdk_path
    export PKG_CONFIG=false
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    ./configure "${configure_arguments[@]}"
    /usr/bin/make -j "$parallel_jobs"
    /usr/bin/make install
)

candidate_directory=${build_directory}/verified-helpers
/bin/mkdir -p "$candidate_directory"
/usr/bin/install -m 755 "$install_directory/bin/ffmpeg" "$candidate_directory/ffmpeg"
/usr/bin/install -m 755 "$install_directory/bin/ffprobe" "$candidate_directory/ffprobe"
/usr/bin/strip -x "$candidate_directory/ffmpeg" "$candidate_directory/ffprobe"

/bin/zsh "$script_directory/verify-ffmpeg.sh" \
    "$candidate_directory" \
    --arch "$target_architecture" \
    --manifest "$manifest_path"

validate_output_directory
replacement_directory=$(/usr/bin/mktemp -d \
    "${output_directory:h}/.${output_directory:t}.new.XXXXXX")
/bin/rmdir "$replacement_directory"
/bin/mv "$candidate_directory" "$replacement_directory"
backup_directory=""
if [[ -e "$output_directory" ]]; then
    backup_directory=$(/usr/bin/mktemp -d \
        "${output_directory:h}/.${output_directory:t}.previous.XXXXXX")
    /bin/rmdir "$backup_directory"
    /bin/mv "$output_directory" "$backup_directory"
fi
if ! /bin/mv "$replacement_directory" "$output_directory"; then
    if [[ -n "$backup_directory" && -e "$backup_directory" ]]; then
        /bin/mv "$backup_directory" "$output_directory" \
            || fail "publication failed; previous helpers preserved at $backup_directory"
    fi
    fail "could not publish the verified helper pair"
fi
replacement_directory=""
if [[ -n "$backup_directory" && -e "$backup_directory" ]]; then
    /bin/rm -rf "$backup_directory"
fi

print "Installed verified helpers in $output_directory"
