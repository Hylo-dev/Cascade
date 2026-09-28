# FFmpeg in Cascade

Cascade packages `ffmpeg` and `ffprobe` 9.0.2 as separate helper executables.
They are source-built for macOS 14 and copied to
`Cascade.app/Contents/Helpers/FFmpeg`. The helpers are not on Cascade's runtime
search path and have no Homebrew or other non-system dynamic dependencies.

## Authenticated source

The build manifest is [`Config/FFmpeg/manifest.json`](../../Config/FFmpeg/manifest.json).
It pins the official release tarball, detached signature, release key, their
SHA-256 digests, and the release-signing fingerprint published by FFmpeg:

- release: `https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz`
- release SHA-256: `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`
- signing fingerprint: `FCF986EA15E6E293A5644F10B4322F04D67658D8`

`scripts/build-ffmpeg.sh` checks all three file digests, reads the fingerprint
from the downloaded key, and verifies the detached signature with an isolated
GnuPG keyring before extracting or running source code. GnuPG is a build-only
prerequisite; shipped helpers do not depend on it.

## Reproduction

On an Apple Silicon Mac with Xcode and GnuPG 2.5 or newer installed at
`/opt/homebrew/bin/gpg` and `/opt/homebrew/bin/gpgv`, run:

```sh
CASCADE_FFMPEG_JOBS=4 /bin/zsh scripts/build-ffmpeg.sh \
  --output Config/FFmpeg/Artifacts/arm64 \
  --arch arm64
```

The script uses at most the requested 1–8 parallel jobs, downloads only the
pinned official source inputs when absent, builds in temporary directories,
and verifies a candidate helper pair before replacing the previous pair.
`Config/FFmpeg/Artifacts` and the source cache are ignored because they are
generated and large. An ordinary Xcode build never downloads or compiles
FFmpeg. Its `Verify FFmpeg Inputs` phase re-runs the local verifier before
embedding and rejects every app architecture for which the helper has no
matching thin slice.

The `--arch x86_64` build path is available for producing a separate Intel
candidate, but the delivered and tested artifact is arm64 only. Do not claim or
package Intel support until that artifact is built and verified on Intel and
the Xcode packaging strategy is updated accordingly.

To verify the staged arm64 pair independently:

```sh
/bin/zsh scripts/verify-ffmpeg.sh Config/FFmpeg/Artifacts/arm64
```

After an app build, verify the copied and signed pair with:

```sh
/bin/zsh scripts/verify-ffmpeg.sh \
  /path/to/Cascade.app/Contents/Helpers/FFmpeg \
  --require-signature
```

The verifier checks the exact version, thin architecture, macOS 14 deployment
target, dynamic dependencies, configure policy, required encoders, and a real
H.264 VideoToolbox plus native AAC MP4 conversion read back by `ffprobe`.

## Configuration and capabilities

The complete configure options are recorded in the manifest and remain visible
through `ffmpeg -buildconf`. The build disables automatic dependency discovery,
networking, output devices, GPL and nonfree components. It enables no external
libraries. Its selected output encoders are native AAC, FLAC, PCM signed 16-bit
little-endian, and H.264 VideoToolbox. MP3 is not included. Callers creating
MP4 or MOV video must select `-c:v h264_videotoolbox` explicitly; FFmpeg's
default for those muxers is not H.264 when libx264 is absent.

The bundled upstream notices are:

- `Config/FFmpeg/Notices/FFmpeg-LICENSE.md`
- `Config/FFmpeg/Notices/COPYING.LGPLv2.1`
- `Config/FFmpeg/Notices/NOTICE.txt`

The Xcode target copies them to
`Cascade.app/Contents/Resources/ThirdParty/FFmpeg`. The helpers are signed by
Xcode with the app's development identity through `CodeSignOnCopy`.
