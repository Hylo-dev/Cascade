# SDK storage request lifecycle

Status: delivered after independent approval, full serial verification, signed build and verified normal restart. [Plan](../plans/2026-09-13-addon-sdk-storage-lifecycle.md).

Baseline: authenticated host handler delivered with 765 passing serial tests / 76 suites, 391 matching inputs and 45 reviewed hashes, signed build and verified normal restart to PID 11511. Weekly meter 55% at dispatch; preserve headroom below 60% for final review/build/restart.

The internal synchronous lifecycle reuses C6 validation and ConnectionGeneration. Its stored state must remain scalar-only, with one exact pending ticket. Cancellation after possible handoff retains the occupied slot until exact reply, proven pre-handoff rejection or logical close; writes/removes report uncertainty without retry. A reply may precede the asynchronous handoff observation. No public SDK API, transport/channel implementation, Data retention or native integration is included.

## Final evidence

Exactly two new files implement the internal lifecycle and its tests. Independent frozen implementation review approved both without findings. Actual compiling RED: 3 methods / 6 expanded executions, 11 behavioral failures covering foreign tickets, wrong response correlation and old callbacks affecting newer work. Final focused GREEN: 42 tests / 6 suites (24 presentation/SDK and 18 Contracts). The new lifecycle suite contains 16 methods / 36 parameter-expanded executions; expanded cases are not added to Swift Testing's method totals.

The final full serial suite passed **781 tests / 77 suites**: 508 Runtime / 44 suites, 38 SDK/presentation / 6, 170 Kit / 19, 61 Contracts / 7 and 4 Tool / 1. All **393 build/test inputs** matched original, normalized integration copy and frozen snapshot before and after the signed app build. The cumulative **47 reviewed source/test hashes** matched their final approved bytes.

Build succeeded, `/Applications/Cascade.app` points to the freshly compiled Debug build and normal restart was verified **PID 11511 → 12667**, without forced termination. Latest weekly usage: **56%**, below the requested 60% ceiling. Existing scratch/cache/derived data were reused. No commit or staging.

Artifacts share `/private/tmp/cascade-sdk-storage-lifecycle`: `-report.md`, `-implementation-review.md`, `-hashes.json`, `.diff`, `-structural-audit.json`, `-red.log`, `-final-green.log`, `-full-tests.log`, `-build-inputs.json`, `-reviewed-inputs.json`, `-app-build.log`, `-restart.json`.

The source audit confirms five scalar root fields and one bounded pending record, with no retained request/value/response/key, queue, continuation or history. Sequence overflow uses the actual checked helper before state mutation. This is structural evidence, not a memory benchmark. The helper authenticates no peer and closes no physical channel; concrete SDK transport and app lifecycle wiring remain outstanding.

Subsequent update, 2026-09-14: the user resolved the asset-transfer choice in [the dedicated decision ticket](../../../.scratch/cascade-product/issues/21-asset-transfer.md), with [reviewed alternatives](../plans/2026-09-13-addon-asset-transfer-decision.md) as evidence. This SDK slice did not implement asset transfer.
