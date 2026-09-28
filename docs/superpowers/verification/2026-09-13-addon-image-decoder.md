# C5: image decoder, 13 September 2026

Implemented the internal host decoder for assets using ImageIO and CoreGraphics.
The [contract](../../addons/assets.md) describes the supported PNG/JPEG profile,
the quotas and the limits; the [increment plan](../plans/2026-09-12-addon-image-decoder.md)
records the decisions. It is not yet an SDK/publication/renderer path.

## Changes

`BoundedAssetImageDecoder` admits a single operation ahead of the worker's queue,
with a `.rateLimited` error for concurrent requests. `NativeAssetImageWorker`
uses the Apple codecs and CGContext to produce premultiplied sRGB RGBA8, off the MainActor.
No new package or custom codec. Maximum input 1 MiB, one megapixel,
RGB8 sRGB, single frame and orientation already correct.

Two small hooks reuse the existing system:
`AssetDisposalCoordinator.assetGovernor` ensures the same governor for staging
and raster; `ResourceGovernor.withAssetDecodeReservation` protects the temporary quota
also from the owner's global cleanup. The final pixels keep the protected lifetime
already verified in C5c1. Errors, cancellation and shutdown do not refund live memory.

## Reproduced defects and review

ImageIO accepts some files without a PNG/JPEG terminator. In addition, a JPEG with a truncated
scan and a restored end marker can appear complete before drawing,
then report `statusUnexpectedEOF`. Both behaviors reproduced; added
fixed signature/terminator checks and a check of the native status after drawing.
They are not an independent validation of chunks, CRC or data after an earlier terminator.

Final independent review: approved, no open findings. The documentation was also corrected
so as not to attribute to the fixed checks guarantees they do not offer.
The tests include expected RGBA bytes, row order, the exact one-megapixel threshold,
disallowed inputs, quotas, concurrent requests and shutdown/cancellation in progress.

## Evidence

- Baseline: 498 serial tests passed. Two AppKit cases did not see `NSScreen.main`
  in the sandbox; the suite with access to the graphical session passes without changes.
- Initial RED: five tests against the decoder not yet implemented,
  `/private/tmp/cascade-asset-decoder-red.log`.
- RED for truncated files/corrupted scan and busy classification:
  `/private/tmp/cascade-asset-decoder-payload-red.log`.
- Temporary mutations reproduced the early refund and the delivery after
  shutdown: `/private/tmp/cascade-asset-decoder-mutation-red.log`. Sources restored
  before the final verification. These later tests are not described as the
  initial RED of the two race tests.
- Final targeted GREEN: 46 tests in four suites, exit 0,
  `/private/tmp/cascade-asset-decoder-regression.log`; SHA-256
  `5d76572d78b87cd90520b4b22a131fc06fce1375c9a2c583380562e472bb7942`.
- Final package: **507 tests passed**, exit 0, `--no-parallel`: Runtime 276,
  Presentation 20, Engine 169, Contracts 38, tool 4. Log
  `/private/tmp/cascade-plugin-decoder-final-tests.log`; SHA-256
  `fc1e9db3a6f742d513a44a3657785d429970e66d7f748dd2364dfc9df23a9d9d`.
  The historical `weakProducer` warning in PublicationStoreTests is present.

Suite command: Xcode-beta, `swift test --package-path
/private/tmp/cascade-plugin-decoder-integration/CascadeKit --disable-sandbox
--scratch-path /private/tmp/cascade-plugin-decoder-baseline --no-parallel`, with
module cache in `/private/tmp/cascade-plugin-module-cache`. Environment macOS 27.0
build 26A5425a, arm64. This is not evidence of execution on macOS 14.

## Build and relaunch

345 build/test inputs identical between the checkout and the local copy; hashes unchanged after
suite and build, inventory `/private/tmp/cascade-plugin-decoder-build-inputs.json`.
Signed build through `scripts/build-development.sh`, exit 0. Strict verification
of the signature and update of the Applications link performed by the script.
Log `/private/tmp/cascade-plugin-decoder-app-build.log`; SHA-256
`f6dce82131524b23644f988731f917f9ec44ab2b301ab9ba2448fd8c0224f86d`.
The warnings concern the Xcode destination and the absence of the AppIntents dependency.

Relaunch verified: PID 56048 quit normally, new instance PID 60288 stable
at the expected path `CascadeAddonDevelopment/Build/Products/Debug/Cascade.app`.
No forced termination. Record `/private/tmp/cascade-plugin-decoder-restart.json`.
No commit or staging; the pre-existing work was preserved.

## Limits and follow-up

Still remaining: AssetState and references to revisions/publications, authorizations,
SDK transport, renderer, cache/restore and qualification of the decoder against hostile
input. The allowances do not impose hard limits on the private memory or CPU time
of the Apple libraries; cancellation does not interrupt a synchronous codec.
No native tracing test run and no launcher enabled. C5 as a
whole and the distributable plugin system remain open.

Codex weekly usage recorded at delivery: 16%, window of 10,080 minutes,
telemetry of 12 September at 22:13 UTC. Below the required 60% ceiling.
