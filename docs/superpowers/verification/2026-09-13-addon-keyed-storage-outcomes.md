# Concrete keyed-request outcomes

Status: implemented, independently reviewed and delivered under the [C7a plan](../plans/2026-09-13-addon-keyed-storage-outcomes.md).

The coordinator distinguishes definite refusal before backend handoff, known successful mutations, conservative uncertainty after a mutating backend throws, and read data that remains authorized after suspension. This narrow operation does not change generic coordinator operations, the backend commit protocol or C6 wire contracts. No new retained coordinator state or reservation is introduced; the caller must protect request/result values through their actual lifetimes.

Compiling behavioral RED is recorded in `/private/tmp/cascade-keyed-storage-outcomes-actual-red.log`: all four write/remove × close/cancel cases verify actual new record bytes or absence while a real forwarded final cleanup gate is held, then fail the expected acknowledged outcome through the deliberately naive generic wrapper. The preceding `-red.log` is a test-fixture compilation correction, not behavioral RED. Gates were released and tasks exited.

Before delivery: freeze exact changes and hashes, independently review implementation and test evidence, run the complete serial package suite, verify all original/normalized/frozen build inputs, build and sign the app, update the Applications link, normally restart and verify its new process. Reuse the existing shared scratch/cache/derived data and preserve the weekly 60% ceiling with verification headroom.


Frozen verification: 72 focused/adjacent tests in five suites pass, including nine new test methods with 15 expanded cases. Full serial package passes 732 tests in 74 suites (475 runtime, 22 SDK, 170 transport, 61 contracts, four tools). All 389 selected build/test inputs match original workspace, normalized copy and freeze. Independent source review and signed app delivery are completed below. Exact final focused log: `/private/tmp/cascade-keyed-storage-outcomes-freeze-green.log`; full log: `/private/tmp/cascade-keyed-storage-outcomes-full-tests.log`.


## Delivered evidence

Independent review approved all three frozen files without introduced blockers. Removing the additive coordinator block reproduces its original source byte-for-byte. The existing generic methods, archive lifecycle and backend remain unchanged. The fixture baseline correction accounts for preexisting first-use data-pool metadata; no production quota changed.

Full serial verification passed **732 tests in 74 suites**. All **389** frozen build/test inputs match original workspace and normalized copy before/after build; **42** accumulated approved source/test hashes match. Signed development build, strict/deep signature verification and Applications link update succeeded. Normal restart verified **PID 4658 → 6324**, stable after two seconds, with no forced termination. Weekly allowance at delivery: **50%**.

Artifacts use `/private/tmp/cascade-keyed-storage-outcomes-`: `report.md`, `hashes.json`, `preimage/`, `frozen/`, `implementation-review.md`, `freeze-green.log`, `full-tests.log`, `build-inputs.json`, `reviewed-inputs.json`, `app-build.log` and `restart.json`. Exact patch: `/private/tmp/cascade-keyed-storage-outcomes.diff`. Only the existing scratch/module cache/derived data were used. Exact runtime transport ownership is the separately preflighted next prerequisite; no authenticated SDK transport is claimed here.
