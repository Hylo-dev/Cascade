# Significant-event archive flushing

Status: implemented, independently reviewed and delivered under the [C4 plan](../plans/2026-09-13-addon-archive-event-flushing.md).

## Delivered baseline

The preceding [SwiftData runtime and fixed-registry increment](2026-09-13-addon-swiftdata-runtime.md) passed 679 serial package tests in 69 suites. All 381 selected inputs matched the workspace and normalized build copy. Signed build, strict signature verification, Applications link update and normal restart to PID 97296 succeeded. Weekly allowance at C4 dispatch: 43%; the user's 60% ceiling includes verification work.

## Required evidence

- Real behavioral RED before implementation; committed significant changes create bounded pending state, while projections, notice-only traffic and rejected mutations do not.
- A known commit acknowledges its captured change only; a later expiry/prune remains pending. Wrong binding and pre-admission busy do not consume an attempt.
- Real lazy-start/debt/save failures retain the prior archive and suppress automatic repetition of the same change. Explicit retry and subsequent genuine changes remain possible.
- One attempt per host call and a fixed-registry round-robin cursor; no pending graphs, payloads, per-owner timers or task queues. Retained scalar metadata is admitted before construction.
- Independent review of exact frozen source/test hashes and meaningful test boundaries, then one full serial package suite, signed build and verified normal restart.

Implementation report: `/private/tmp/cascade-runtime-archive-c4-report.md`; exact five-file diff/hashes/preimages share that prefix. Independent review approved all five frozen hashes without introduced blockers. The final focused/adjacent run passed **131 tests in 10 suites**. The actual compiling RED failed on missing pending state and no commit; separate fixture compile errors and one corrected Swift dictionary exclusivity crash are recorded honestly in the report.

Full serial package suite: **694 tests in 70 suites** (447 runtime, 22 SDK, 170 transport, 51 contracts, 4 tools), 15 more tests than the delivered baseline. All **382** selected build/test inputs match the source workspace, normalized copy and freeze before/after build; **32** final source/test hashes match the combined approved baseline and C4 manifests.

Signed development build, strict/deep signature verification and Applications link update succeeded. Normal restart verified **PID 97296 → 99945** with the new process still running after two seconds; no forced termination. Weekly allowance at delivery: **45%**.

Artifacts in `/private/tmp`: `cascade-runtime-archive-c4-final-accounting-green.log`, `cascade-runtime-archive-c4-full-tests.log`, `cascade-runtime-archive-c4-build-inputs.json`, `cascade-runtime-archive-c4-reviewed-inputs.json`, `cascade-runtime-archive-c4-app-build.log`, `cascade-runtime-archive-c4-restart.json`. Only the existing SwiftPM scratch, shared module cache and Xcode derived data were used.

## Scope

This slice supplies internal dirty-state queries and an explicit host-event flush operation. Production application wake/bootstrap wiring and shutdown quiescing remain separate integration work. Existing explicit save/restore signatures and known-commit semantics are preserved; no new crash-loss window or durable provider-acknowledgment guarantee is introduced.


## Accounting and limits

Runtime progress adds 256 bytes per owner on the tested ABI; the coordinator adds 256 fixed bytes, and the existing B2 output scope adds 128 bytes for captured markers. Three prior composition assertions were updated by precisely 256 bytes after they failed; original refund and bookkeeping deltas remain. Test-injected observed debt exercises the real governor ledger, without claiming equivalent files occupy that many bytes.

C5 bounded shutdown checkpoint work is now separately dispatched after this completed delivery; it has its own independently preflighted plan. The production event driver and native-provider qualification remain outside these internal APIs.
