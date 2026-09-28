# Bounded shutdown archive checkpoint

Status: implemented, independently reviewed and delivered under the corrected [C5 plan](../plans/2026-09-13-addon-archive-shutdown.md).

The delivered [C4 baseline](2026-09-13-addon-archive-event-flushing.md) passes 694 serial tests in 70 suites, 382 identical frozen build/test inputs, signed build/link and normal restart to PID 99945. Weekly use at C5 dispatch: 45%; the 60% ceiling includes review and verification.

## Boundaries to verify

Quiescence closes normal authority while retaining private canonical data for one bounded checkpoint pass. Logical stop and logical coordinator closure use prepaid scalar state; actual backend cleanup is an explicit later operation. Runtime admission distinguishes busy-before-acceptance from failed accepted work. An in-flight coordinator operation keeps its original identity and cleanup while a shutdown context is acquired.

The supplied monotonic deadline gates new runtime work and final handoff to the backend. A backend call already handed off may still commit, and its known result and actual resource charges must remain truthful. No hard framework completion deadline, task-group timeout, automatic application event driver or provider-launch qualification follows from these internal APIs.

Final evidence must include real behavioral RED/GREEN, exact frozen hashes and independent review, full serial package tests, signed build, Applications link update and verified normal restart. The existing single SwiftPM scratch, shared module cache and Xcode derived data are reused.


## Delivered evidence

Independent review approved all seven frozen source/test hashes with no introduced blockers. Two real compiling RED runs covered runtime authority/private checkpoint and coordinator capability/pass behavior. Final focused/adjacent verification passed **178 tests in 13 suites**, including **16** new shutdown tests. Exact report, diff, hashes and preimages use `/private/tmp/cascade-runtime-archive-c5-*`.

Full serial package suite passed **710 tests in 71 suites**: 463 runtime, 22 SDK, 170 transport, 51 contracts and 4 tools. All **383** selected build/test inputs match the original workspace, normalized build copy and freeze before/after build. **34** final source/test hashes match the accumulated approved manifests.

Signed development build, strict/deep signature verification and `/Applications/Cascade.app` link update succeeded. Normal restart verified **PID 99945 → 2818**, with the new process still running after two seconds; no forced termination. Weekly allowance checked at delivery: **47%**.

Logs/manifests in `/private/tmp`: `cascade-runtime-archive-c5-final-green.log`, `cascade-runtime-archive-c5-full-tests.log`, `cascade-runtime-archive-c5-build-inputs.json`, `cascade-runtime-archive-c5-reviewed-inputs.json`, `cascade-runtime-archive-c5-app-build.log` and `cascade-runtime-archive-c5-restart.json`. Only the existing scratch/cache/derived data were used. Expected corrupt-store fixture diagnostics and existing build warnings do not alter the passing outcomes.

## Reviewed refinements and accounting

The runtime operation carries a narrow quiescence purpose. A post-cleanup claim recheck preserves concurrent ownership; exact busy-before-admission differs from failure after acceptance. The private actor-isolated commit helper validates purpose/clock immediately before invoking the backend, while preserving the existing protected output scope and captured marker.

Prompt finish performs logical stop only. Later explicit coordinator close owns the existing runtime.stop drain, refreshes its scalar progress, then closes the backends. Known pending runtime cleanup keeps receipts in draining even if backend cleanup completed. Real forwarded resource and broker gates cover prompt finish, eventual cleanup and sent-work retention; a test-only synchronous clock gate covers a late acquired ticket without a production hook or timing sleep.

C5 adds 256 bytes per owner and 1024 fixed coordinator bytes on the tested ABI, admitted before retained controls. Three old composition assertions increased by exactly 256; the 1024 reservation bookkeeping delta remains. Existing C4 and B2 buffer charges remain separate and unchanged. The next dedicated storage-frame contract slice is separately dispatched; no production event/shutdown driver or native provider qualification is implied by this delivery.
