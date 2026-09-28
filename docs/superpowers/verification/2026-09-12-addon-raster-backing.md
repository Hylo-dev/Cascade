# C5c1: image memory, 12 September 2026

This increment delivers the internal raster backing of the future asset system.
A real image keeps its memory and the matching quota until the last CoreGraphics
reference; the actual release triggers the refund in the shared governor. The host
contract and the boundaries are described in [assets](../../addons/assets.md).
It is not yet an SDK/publication/renderer path that addons can use.

## Implementation and focused checks

Six source/test files: extension of ResourcePolicy and ResourceGovernor, two Assets
primitives and two new suites. Admission before allocation, fixed RGBA8 format with
a maximum of 1 MP, execution off the MainActor, protected reservations and a single
shared drain. The individual management records do not keep a table sized
to the peak. Closing and cancellation do not free quotas of images still alive.

During implementation, the omission of the pixels from the overall budget, the lack
of lifetime protections and the possible confusion between successive instances of the
governor at the same address were demonstrated and fixed. The lifetime identity
now uses a nonce and each protected reservation has its own canonical secret.
The initial compiler sandbox error is a failure to start the check,
not a failed behavioral test.

37 focused tests passed, exit 0: 19 AssetRasterBackingTests, 5 RetainedAssetReservationTests,
13 pre-existing ResourceGovernorTests. They include real CGImages, two references,
replacement with the old image still retained, 1,638 real slots, construction
failures, cancellation, suspended admission/refund, closing, conservative faults,
concurrency during draining and attempts at early release.
Final log `focused-final.log`, SHA-256
`d9fd8707a0ebee157dd0344a3f5b2702ebbe456023688df7573e2d6f14135611`,
kept in the delivery checkpoint together with the nine logs and the source hashes.

## Review

Independent review: conformance and quality approved, no findings to fix.
The six source hashes, the preimages, the diff and the nine logs were verified. The
construction-failure tests are induced: they are not equivalent to real heap exhaustion
or to a forced native CGDataProvider failure. The constructor's trusted contract
excludes deferred callbacks after a null result.

## Full verification

Final package: **498 tests passed**, exit 0, `--no-parallel`: Runtime 267,
Presentation 20, Engine 169, Contracts 38, tool 4. Session 81680; log
`/private/tmp/cascade-c5c1-final-full-package.log`, SHA-256
`aa7859da06355d2c937a758b555d923ba350f8929366ecc0b6b0525e798bfbb4`.
The six source hashes are unchanged after the verification. The final full log
contains no warnings; the earlier focused log includes the historical, unchanged
warning in PublicationStoreTests about the weakProducer variable. The serial result
does not qualify the old limitation of the concurrent UI tests.

## Delivery and requested stop

10 files integrated (6 sources/tests and 4 documents), preserving the pre-existing work.
404 source inputs compared, including the prototypes, identical between the original
checkout and the local copy. Official signed build succeeded, exit 0, session 34450.
Strict signature verification and the update of `/Applications/Cascade.app` performed
by the project script. The Xcode warnings about destination selection and about the two
SWIFT_DEBUG_INFORMATION variables are also present in the previous build.

Relaunch verified, session 1216 exit 0: PID 53808 closed normally without forcing,
new instance PID 56048 stable in the expected CascadeAddonDevelopment path. Logs
`/private/tmp/cascade-c5c1-20260912-app-build.log` and
`/private/tmp/cascade-c5c1-20260912-restart.json`. No commit or staging.

This concludes the C5c1 task. The work stops here at the user's request;
no later task or automatic resumption is started.

## Limits and follow-up

The input contains already decoded, trusted pixels; no decoder for hostile input
is proven. The quotas concern controlled memory and allowances, not internal
CoreGraphics/GPU copies or the overall footprint. The real SwiftUI view cycle,
SDK import, compressed transfer, private authorizations, references to
asset/publication revisions, cache and restore remain to be connected.
The future AssetState must enter AddonRuntime's canonical transaction.

The native-process gate stays HOLD for safety in the case of early loss of the
supervisor; no new tracing evidence was run. The macOS 14 floor
is not qualified by tests run on this beta machine. C5 and the complete feature
remain open. At the user's request the work stops at the delivery of C5c1,
without starting C5c2.
