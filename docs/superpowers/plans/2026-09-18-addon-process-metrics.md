# C4 — Read-only process observations and CPU intervals

User’s sustained Codex-only continuation authorizes this independent increment of the approved C4 plan;35%reserve waived. Design input: [.scratch resource metrics investigation](../../../.scratch/codex-addon/20260918-continuation/resource-metrics-design.md). No native launch/stop qualification is implied.

## Accepted scope

Internal Runtime reader of public proc_pid_rusage RUSAGE_INFO_V0 plus bounded pure interval reducer. A supplied positive PID, nonzero birth-abstime, nonzero executable UUID and local binding/clock-domain identify an observational expectation. Do not auto-adopt PID occupants. These fields are neither publisher authentication nor an exec-generation capability, and grant no termination authority. No integration with governor, health incidents, runtime composition, scheduling or UI in this increment. C0d stays unconditionally exit78.

Reader performs one raw call, captures errno immediately, brackets acquisition with Mach absolute ticks, matches identity in the returned record, rejects exit records and invalid timebase/clocks. Use SDK-imported pointer ABI. Missing and failed reads yield unavailable, never zero. Tests inject fixed raw records/clock; an optional self-process read verifies ABI only, no spawned fixture/process signals. No polling, retry loops, task_for_pid, private APIs or timer.

Reducer stores one baseline and immutable binding. First observation yields footprint only. Difference user/system counters separately, validate monotonicity, checked-add deltas, convert Mach ticks once using full-width multiplication/division by validated timebase. Report UInt64 CPU/elapsed nanoseconds and footprint; aggregate CPU may exceed one core. Carry acquisition bounds. Reject unordered/overlapping time windows, zero elapsed and overflow without trapping. Missing/errors break continuity; counter regression resets baseline; identity mismatch/exit invalidates binding until owner creates a new one. Explicit reset breaks continuity for future lifecycle integration. Preserve a separately valid footprint when CPU-only arithmetic fails, never expose footprint from a rejected identity.

## Execution

1. Capture exact absence/preimages; preserve dirty checkout, no Git edits/worktree. Add ProcessMetrics.swift, ProcessMetricsReader.swift and focused ProcessMetricsTests.swift only. Existing public surfaces/products unchanged.
2. Compiling meaningful regression tests for reader/reducer behavior before implementation where feasible; record test provenance honestly. Cover identity/failure, counter/time resets, non-unit timebase, full-width representable/overflow edges, missing-vs-zero, binding invalidation and repeated reset. No implementation-mirroring or load abuse.
3. Scoped SwiftPM tests serial after root releases shared scratch; independent review and focused fixes. Cross-check native self reader ABI if safe without inventing independent-unit qualification.
4. Root full suite, signed build/application link and normal restart; record exact source hashes and target counts. Add docs clearly separating observation from enforcement and macOS14/API floor from runtime qualification. Continue remaining work under user authorization.

Pending future C4: authenticated process-to-addon association, common active-set cadence<=1Hz/disarm, independent measured CPUunit validation, health/enforcementintegration and observedexit. No broad C4completion claim.

## Delivered

Reader/reducer scope complete, independent review PASS, 33 focused tests and 929 full-suite tests/85 suites PASS. Signed build and normal restart verified. [Delivery evidence](../verification/2026-09-18-addon-process-metrics.md). Broader C4 gaps above remain open.
