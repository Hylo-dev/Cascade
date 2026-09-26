#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h:h}
verifier=${project_directory}/scripts/verify-ffmpeg.sh
builder=${project_directory}/scripts/build-ffmpeg.sh
manifest=${project_directory}/Config/FFmpeg/manifest.json
verified_helpers=${CASCADE_FFMPEG_TEST_HELPERS:-${project_directory}/Config/FFmpeg/Artifacts/arm64}
scratch_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cascade-ffmpeg-tests.XXXXXX")

function cleanup {
    /bin/rm -rf "$scratch_directory"
}

trap cleanup EXIT

function expect_failure_containing {
    local expected_message=$1
    shift

    local output_file=${scratch_directory}/failure-output.txt
    if "$@" >"$output_file" 2>&1; then
        print -u2 "Expected command to fail: $*"
        return 1
    fi

    if ! /usr/bin/grep -Fq -- "$expected_message" "$output_file"; then
        print -u2 "Expected failure containing: $expected_message"
        /bin/cat "$output_file" >&2
        return 1
    fi

    print "Rejected as expected: $expected_message"
}

missing_directory=${scratch_directory}/missing
/bin/mkdir -p "$missing_directory"
expect_failure_containing "Missing FFmpeg helper: ffmpeg" \
    /bin/zsh "$verifier" "$missing_directory"

populated_output=${scratch_directory}/populated-output
invalid_source_cache=${scratch_directory}/invalid-source-cache
/bin/mkdir -p "$populated_output"
/bin/mkdir -p "$invalid_source_cache"
/usr/bin/touch "$populated_output/unrelated-file"
/usr/bin/touch \
    "$invalid_source_cache/ffmpeg-9.0.2.tar.xz" \
    "$invalid_source_cache/ffmpeg-9.0.2.tar.xz.asc" \
    "$invalid_source_cache/ffmpeg-devel.asc"
expect_failure_containing "output directory contains unrelated files" \
    /bin/zsh "$builder" \
        --output "$populated_output" \
        --arch arm64 \
        --source-cache "$invalid_source_cache"
[[ -f "$populated_output/unrelated-file" ]] \
    || { print -u2 "Builder removed the unrelated output sentinel"; exit 1; }

directory_helper_output=${scratch_directory}/directory-helper-output
/bin/mkdir -p "$directory_helper_output/ffmpeg"
/usr/bin/touch "$directory_helper_output/ffmpeg/unrelated-file"
expect_failure_containing "existing ffmpeg output must be a regular non-symbolic-link file" \
    /bin/zsh "$builder" \
        --output "$directory_helper_output" \
        --arch arm64 \
        --source-cache "$invalid_source_cache"
[[ -f "$directory_helper_output/ffmpeg/unrelated-file" ]] \
    || { print -u2 "Builder removed data below a helper-named directory"; exit 1; }

symlink_helper_output=${scratch_directory}/symlink-helper-output
/bin/mkdir -p "$symlink_helper_output"
/bin/ln -s "$populated_output/unrelated-file" "$symlink_helper_output/ffmpeg"
expect_failure_containing "existing ffmpeg output must be a regular non-symbolic-link file" \
    /bin/zsh "$builder" \
        --output "$symlink_helper_output" \
        --arch arm64 \
        --source-cache "$invalid_source_cache"

symlink_target=${scratch_directory}/symlink-target
symlink_output=${scratch_directory}/symlink-output
/bin/mkdir -p "$symlink_target"
/bin/ln -s "$symlink_target" "$symlink_output"
expect_failure_containing "output must not be a symbolic link" \
    /bin/zsh "$builder" \
        --output "$symlink_output" \
        --arch arm64 \
        --source-cache "$invalid_source_cache"
expect_failure_containing "output must not be a symbolic link" \
    /bin/zsh "$builder" \
        --output "${symlink_output}/" \
        --arch arm64 \
        --source-cache "$invalid_source_cache"

/bin/ln "$verified_helpers/ffmpeg" "$missing_directory/ffmpeg"
expect_failure_containing "Missing FFmpeg helper: ffprobe" \
    /bin/zsh "$verifier" "$missing_directory"

expect_failure_containing "must be thin 'x86_64'" \
    /bin/zsh "$verifier" "$verified_helpers" --arch x86_64

wrong_version_manifest=${scratch_directory}/wrong-version.json
/bin/cp "$manifest" "$wrong_version_manifest"
/usr/bin/plutil -replace version -string 0.0.0 "$wrong_version_manifest"
expect_failure_containing "ffmpeg version differs from manifest" \
    /bin/zsh "$verifier" "$verified_helpers" --manifest "$wrong_version_manifest"

if [[ -x /opt/homebrew/bin/gpg ]]; then
    external_dependency_directory=${scratch_directory}/external-dependency
    /bin/mkdir -p "$external_dependency_directory"
    /bin/cp /opt/homebrew/bin/gpg "$external_dependency_directory/ffmpeg"
    /bin/ln "$verified_helpers/ffprobe" "$external_dependency_directory/ffprobe"

    external_dependency_manifest=${scratch_directory}/external-dependency.json
    /bin/cp "$manifest" "$external_dependency_manifest"
    external_dependency_minimum=$(/usr/bin/vtool -show-build /opt/homebrew/bin/gpg \
        | /usr/bin/awk '$1 == "minos" { print $2; exit }')
    /usr/bin/plutil -replace deploymentTarget -string "$external_dependency_minimum" \
        "$external_dependency_manifest"
    expect_failure_containing "non-system dynamic dependency: /opt/homebrew/" \
        /bin/zsh "$verifier" "$external_dependency_directory" \
            --manifest "$external_dependency_manifest"
else
    print "SKIP: genuine Homebrew dynamic-dependency rejection (gpg unavailable)"
fi

/bin/zsh "$verifier" "$verified_helpers" --manifest "$manifest"

space_directory=${scratch_directory}/helpers\ with\ spaces
/bin/mkdir -p "$space_directory"
/bin/ln "$verified_helpers/ffmpeg" "$space_directory/ffmpeg"
/bin/ln "$verified_helpers/ffprobe" "$space_directory/ffprobe"
/bin/zsh "$verifier" "$space_directory" --manifest "$manifest"

print "FFmpeg verifier positive and negative checks passed"
