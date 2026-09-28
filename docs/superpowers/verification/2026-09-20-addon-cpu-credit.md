# Addon CPU credit: continuation of 20 September 2026

**Outcome: PASS for the internal components**, after root and independent review, full tests, signed build and verified relaunch. The decision on the [shared credit](../../../.scratch/cascade-product/issues/46-addon-cpu-burst-policy.md) is approved: initial capacity of 100 ms CPU and a recharge of 5 ms CPU per monotonic second, preserved across jobs and relaunches of the provider. It replaces the previous ambiguous combination of a sliding window and a per-job burst.

## Increments

- [CPU credit](../../../.scratch/cascade-product/issues/47-addon-cpu-credit.md): Terra medium implemented the internal value `AddonCPUBudget`; root and independent review by Sol medium PASS. 12 targeted tests PASS. `Duration` arithmetic, instants bounded and ordered even below the nanosecond, observed debt preserved, exact conversion of `UInt64.max`, atomic error if a new charge exceeds the representable limit. No per-job reset.
- [Wiring into the common observations](../../../.scratch/cascade-product/issues/48-addon-cpu-accounting.md): Sol medium implemented the wiring; root and a second Sol medium reviewed the final code: PASS. The event-driven owner is explicit and the account belongs to the existing coordinator, with bounded identities and capacity. No second sampler or entry point to reapply already produced batches. The per-owner result distinguishes complete coverage of the round, incomplete coverage without a balance and a persistent accounting error without a balance; valid charges remain acquired even when a measurement of another process is missing.

## Tests and delivery

- **71 targeted tests in 4 suites PASS**: 12 for the credit, 12 for the wiring and 47 for the pre-existing observations/reducer/coordinator. The wiring has a compiled behavioral red and a subsequent green.
- **1,122 full tests in 99 suites PASS**, compared with the baseline of 1,098 tests in 97 suites. Root recompiled and reran all the products of the package in the desktop session, with Xcode-beta and `swift test --disable-sandbox --package-path CascadeKit --scratch-path /private/tmp/cascade-addon-tests --no-parallel`. The five Swift Testing results are summed in the [summary](../../../.scratch/codex-addon/20260920-cpu-credit/test-summary.json).
- Root required the overflow atomicity test at a later instant; in the wiring it fixed the retention of the account in the error state and the order of the publisher validation. The overflow fixtures now also account for the recharge during the debt. No important residual finding in the independent reviews.
- **Official build and Apple Development signature PASS.** `scripts/build-development.sh` was run on a local copy with 482 SHA-256 inputs identical to the project before and after the compilation. This avoids the iCloud block of `NSFileCoordinator` documented in the previous delivery. SDK check: 4 packages, 11 targets, 90 Swift sources and 140 imports PASS; `codesign --verify --deep --strict` PASS.
- The script updated `/Applications/Cascade.app` to the build in `CascadeDevelopment/Build/Products/Debug/Cascade.app`. Normal quit and relaunch verified: **PID 18882 → 25071**, matching executable path and stability for five seconds. [Result](../../../.scratch/codex-addon/20260920-cpu-credit/delivery.json).
- The hashes of the four reviewed source/test files match those delivered. The other recorded inputs are unchanged; no change to the pre-existing reader/reducer or to other subsystems. No commit or native experiment.

## Limits

The components remain internal and observational. The process/publisher binding remains an expectation supplied by the host, not a native authentication. No production wiring to the launcher, the governor or the health, no timer or new process. The credit lives in the incarnation of the coordinator: the relaunch of the provider preserves it, the relaunch of the host app is not persistence on disk. No automatic application of the event-driven profile to continuous UI/audio.

The balance accounts for the CPU actually observed. It does not constitute an instantaneous guarantee or a proof of coverage of the whole life of the process. Public profiles, native macOS 14/Intel behavior, energy cost and supervised stop remain to be qualified.

## Evidence

[Brief and review of the calculation](../../../.scratch/codex-addon/20260920-cpu-credit/task-47-independent-review.md), [wiring design](../../../.scratch/codex-addon/20260920-cpu-credit/ownership-design-review.md). The first red of the calculation was only a compilation failure because of a missing type; it is not presented as a TDD behavioral failure. A later check in a temporary package altered only the recharge: six behavioral failures; byte-identical restoration and 12 tests PASS. It is a check of the sensitivity of the tests, not a historical TDD red.

## Next design point

Before wiring the overruns into `AddonHealthStore` it is necessary to [define the distinct CPU violations](../../../.scratch/cascade-product/issues/49-addon-cpu-violation-counting.md). A single burst can leave debt for several samples: repeating the read of the negative balance does not prove new consumption. The recommendation is to count new consumption beyond the credit, once per addon and measurement round; the product choice remains open.

[Root review and input comparison](../../../.scratch/codex-addon/20260920-cpu-credit/root-review.md), [independent review of the wiring](../../../.scratch/codex-addon/20260920-cpu-credit/task-48-independent-review.md), [full test log](../../../.scratch/codex-addon/20260920-cpu-credit/final-package-tests.log), [build log](../../../.scratch/codex-addon/20260920-cpu-credit/final-app-build.log).

The derived tracker contains 49 tickets: 32 resolved, 17 open, of which 7 available and 10 blocked; no ticket remains assigned. Dependencies verified as existing and free of cycles. Weekly budget available at delivery: **92%** (8% consumed), above the stop threshold of 75%. The stop concerns the next design choice requested by the user, not the budget.
