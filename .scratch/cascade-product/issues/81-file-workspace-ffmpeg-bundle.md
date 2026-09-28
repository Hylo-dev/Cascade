# Prepare verified FFmpeg and ffprobe in the bundle

ID: 81
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: none

## Question

Implement task 5 of the [file shelf plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): acquisition from the official release with signature/hash actually verified, a version/configuration/license manifest, build and verification of ffmpeg/ffprobe, staging and signing in the bundle with no dependency on Homebrew or on downloads during the ordinary build. Acceptance: the verifier rejects missing binaries, a wrong version/architecture and non-system libraries; conversion fixture readable by ffprobe; architectures and codecs attested only if proven. No implicit GPL/nonfree. Root review and selective commit. This work is independent of the native path qualification.

## Answer

Implemented with GPT-5.6 Sol in commits `c1c8d51` and `30ba37f`, after GPT-6 Sol research and a personal root review. FFmpeg/ffprobe 9.0.2 from official sources authenticated with hash and signature, arm64 build for macOS 14, dynamic dependencies exclusively from the system. H.264 VideoToolbox, AAC, FLAC and PCM encoders; MP3 excluded. Generated artifacts ignored by Git, reproduction documented in [FFmpeg in Cascade](../../../docs/third-party/ffmpeg.md).

The root verified ten negative cases, paths with spaces, real MP4 conversions and the sandbox. The real Xcode build detected the temporary directory problem and had it fixed: sandbox kept active, scratch in the target's TEMP_DIR. Final build `scripts/build-development.sh` exit 0, consistent app/helper signatures, conversion from the signed pair in the bundle succeeded, licenses in the Resources. Link `/Applications/Cascade.app` updated and restart verified at PID 27461.

Only arm64 is qualified; x86_64 not delivered. No conversion coordinator or native path activated. [Evidence and limits of the tranche](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).
