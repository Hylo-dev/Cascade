# Temporary rejection of new addon work: 21 September 2026

**Status: implementation, reviews, full suite and signed delivery PASS.** The user chose the first alternative in [Define the reduction of new work after a CPU overrun](../../../.scratch/cascade-product/issues/52-addon-cpu-reduced-admission.md). An immediate rejection applies until a strictly positive credit is proven by complete measurements, without a queue or additional replay. Work already admitted keeps its deadlines and completions.

## Scope

The [execution ticket](../../../.scratch/cascade-product/issues/53-addon-cpu-admission.md) concerns new actions and new provider work, using the internal metrics and health already verified. The journal and the scheduler already consider accepted actions as admitted even while they are still pending: the pump does not become a second admission. The host bootstrap remains possible to obtain measurements after the exit of the provider, keeping the debt and the block on new work. No native activation or change to the limits.

## Evidence

Baseline: 1,135 tests in 101 suites, 484 frozen inputs, weekly residual 90%. [Admission analysis](../../../.scratch/codex-addon/20260921-cpu-admission/admission-design-review.md), [brief](../../../.scratch/codex-addon/20260921-cpu-admission/task-53-brief.md). Wayfinder addon only, Sol medium implements; root and an independent review verify before delivery.


## Verified admission

Sol medium completed the check of new admissions; root and Sol medium reviewed the frozen delta: PASS. Eight new tests verify rejection without retention, duplicates, already accepted actions, zero credit and positive credit below 100 ms, missing measurements, quarantine, distinct owners, restart, already admitted invocations and new invocations, reuse of sources, effective v1.4 rejection and a race during the growth of the reservations.

The check in the broker is an internal overload: the pre-existing public API keeps its behavior. It avoids both rejecting reuses that carry no new provider work and accepting a new launch that is already forbidden and needlessly turning it into an indeterminate outcome. The four files of the tranche are frozen and compared with the preimages, without commit/reset of the dirty checkout.

Final targeted run: **191 tests** (189 in 12 suites, two in a transport suite), exit 0. The red test temporarily disables the check to demonstrate the sensitivity of the test and is followed by the restoration/green; it is not presented as an initial TDD sequence. [Report](../../../.scratch/codex-addon/20260921-cpu-admission/task-53-report.md), [review](../../../.scratch/codex-addon/20260921-cpu-admission/task-53-independent-review.md), [root](../../../.scratch/codex-addon/20260921-cpu-admission/root-review.md).

The follow-up [links the measurements to the common deadline](../../../.scratch/cascade-product/issues/54-addon-metrics-deadline.md), without a timer or activation in the app. The next distinct design point is [the CPU attribution of services to consumers](../../../.scratch/cascade-product/issues/55-addon-delegated-cpu-attribution.md), expressly left open by the previous decisions.


## Deadlines and wake verified

Terra medium connected the fifth aggregate to the common queue and Sol medium wrote the concurrent tests. Root and an independent Sol verified all three frozen files: PASS. Ten new tests cover cadence, explicit samples, precedence of the action deadline, owner migration, last exit, cold start, new baseline, negative debt, a read interrupted by wake, a second wake during reset and a stopped runtime. The first Terra attempt used the wrong command/scratch; the later valid checks use Xcode-beta and the official temporary scratch. No artifacts were deleted.

Targeted run: **118 tests** (116/10 suites and 2 transport), exit 0. [Production report](../../../.scratch/codex-addon/20260921-cpu-admission/task-54-report.md), [wake report](../../../.scratch/codex-addon/20260921-cpu-admission/task-54-wake-report.md), [independent review](../../../.scratch/codex-addon/20260921-cpu-admission/task-54-independent-review.md). The red wake test temporarily omits the event in the test and observes six behavioral failures, then restores the test. It does not modify production and is not described as initial TDD.

Root full suite: **1,153 tests in 104 suites PASS**, exit 0. Totals of the five products: 763/62, 112/11, 170/19, 91/10, 17/2. [Log](../../../.scratch/codex-addon/20260921-cpu-admission/package-tests.log). The 487 build inputs are copied and verified byte for byte into a local snapshot, preserving the dirty checkout and all the pre-existing work.

The increment concerns the dormant internal runtime. Remaining: the qualified native binding, the delivery of macOS events, the external waiting on the deadlines and physically observed stops. The launcher remains blocked. The follow-up requires the choice on shared CPU attribution to consumers; no alternative was implemented.


## Verified delivery

The official script `scripts/build-development.sh`, run on the exact snapshot, concludes **BUILD SUCCEEDED** and verifies the Apple Development signature. The mandatory SDK check precedes Xcode. `/Applications/Cascade.app` points to the build just produced in DerivedData/CascadeDevelopment. All 487 inputs of the snapshot and of the original checkout match after the build; compared with the baseline, three files change and three tests are added, no file removed.

At the final check Cascade was already closed (`beforePIDs: []`); it was launched from the Applications link, without forced terminations. PID **42941**, executable path matching the updated build, signature verified and process stable for 5 seconds. [Build log](../../../.scratch/codex-addon/20260921-cpu-admission/application-build.log), [input identity](../../../.scratch/codex-addon/20260921-cpu-admission/build-input-verification.json), [launch evidence](../../../.scratch/codex-addon/20260921-cpu-admission/delivery.json).

Tracker updated: 55 tickets, 38 resolved, 17 open unassigned, 7 available/10 blocked, no residual claim and acyclic dependencies. Final Codex budget: 13% consumed, **87% remaining**; no reset used. Stopped at the next design choice, not at the 75% threshold. No changes outside the addon system and its documents in this tranche; the pre-existing checkout is preserved.
