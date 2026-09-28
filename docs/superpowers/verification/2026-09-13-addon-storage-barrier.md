# Global storage admission barrier — verification

Status: implemented, independently reviewed, fully tested, built and restarted.

## Scope

The approved C5 storage barrier composes `AddonStateStore` and `AddonKeyedStorage`
behind an internal persistent coordinator. It reuses their filesystem formats,
quota accounting, recovery algorithms and the common `ResourceGovernor`.

The registry is fixed and complete. Normal operations remain unavailable until
both roots have reconciled; a new readiness epoch invalidates previous owner
capabilities. Failed startup preserves committed files, and subsequent startup
reuses any established keyed ledger instead of admitting a duplicate backend.

This slice does not connect authenticated SDK storage, support dynamic registry
changes, restore publications or qualify the native launcher. C0d remains closed.

## Focused tests and independent review

Eight focused tests passed after review fixes, exit 0. They use real private
directories, existing backends and the real governor, with a seam that delays real
resource-admission results. Coverage includes second-root failure and repair,
committed-value preservation, repeated close/reopen with the same keyed ledger,
startup cancellation/closure, competing operations, stale/foreign owner capabilities,
shared disk quota and unrelated reservations.

The initial compiling behavioral RED produced two failures in the real-directory
failure/repair test. A later regression exposed ten URL-bound failures across both
roots. The fix bounds complete absolute file URLs and rejects retained base/query/
fragment data before metadata admission. Independent review also found excess
caller-array capacity retained by the registry; a compact row copy now occurs after
admission. The existing eight tests passed again after that correction. No public
test hook or implementation-mirroring capacity probe was introduced.

The independent specification/quality reviewer approved the refreshed two-file diff
with no remaining findings. Existing backend algorithms were not changed.

Evidence:

- `/private/tmp/cascade-storage-barrier-red.log`
- `/private/tmp/cascade-storage-barrier-url-red.log`
- `/private/tmp/cascade-storage-barrier-capacity-green.log`
- `/private/tmp/cascade-storage-barrier-task1.diff`
- `/private/tmp/cascade-storage-barrier-task1-report.md`

## Full delivery verification

The normalized copy is `/private/tmp/cascade-storage-barrier-integration`.
All 358 build/test input files match the workspace and frozen SHA-256 snapshot
at `/private/tmp/cascade-storage-barrier-build-inputs.json`. The existing single
scratch `/private/tmp/cascade-storage-barrier-tests` is reused to limit disk usage.

The full serial package suite passed, exit 0: **560 tests** (322 runtime,
22 presentation, 170 CascadeKit, 42 contracts, 4 addon tool). The log is
`/private/tmp/cascade-storage-barrier-full-tests.log`. The 358 frozen inputs were
checked again after testing and remained identical. The existing unrelated
weak-producer test warnings remain; there were no test failures.

The signed development build passed, exit 0, using the project
`scripts/build-development.sh` from the frozen copy and derived data at
`/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeAddonDevelopment`.
The script verified the signature with `codesign --verify --deep --strict` and
updated `/Applications/Cascade.app` to that build. Log:
`/private/tmp/cascade-storage-barrier-app-build.log`.

All 358 inputs still matched after the build. Normal application termination and
launch succeeded, exit 0: **PID 73683 → 76239**, with the new process observed still
running after two seconds. No forced termination was used. Record:
`/private/tmp/cascade-storage-barrier-restart.json`.

The prior shared-asset increment passed 552 serial tests and restarted Cascade
from PID 69877 to 73683. That evidence is recorded separately in
[asset sharing](2026-09-13-addon-asset-sharing.md); it does not verify this increment.

## Allowance

Latest allowance check: **25%** of the weekly allowance consumed, reported at
2026-09-13T10:18:22.212Z. The user's ceiling remains 60% consumed.

## Next architectural decision

The restart archive's durable transaction model is genuinely unspecified in C5.
The independent audit confirmed that per-record checkpoint/keyed atomicity does not
settle publication/asset consistency, durable privacy identities or alias reconstruction.
The [concrete archive proposal](../plans/2026-09-13-addon-restoration-archive-decision.md)
recommends a private SQLite archive through GRDB, with records and raster BLOBs in
one transaction. It has been reviewed as a direction, not implemented or qualified.
The [restoration draft](../plans/2026-09-13-addon-publication-restoration.md) remains
explicitly pending that decision; no restoration commit API or dependency was added.
Other approved runtime work remains possible. This intervention pauses at the real
architectural choice, as the user requested, rather than claiming C5 is complete.
