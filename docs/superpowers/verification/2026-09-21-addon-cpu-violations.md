# Addon CPU violations: continuation of 21 September 2026

**Status: implementation, reviews, tests and local delivery complete.** The user approved the [counting of new consumption beyond credit](../../../.scratch/cascade-product/issues/49-addon-cpu-violation-counting.md): at most one moderate incident per addon and round, without counting the residual debt alone again.

## Increments

The [classifier](../../../.scratch/cascade-product/issues/50-addon-cpu-violation-classification.md) is implemented by Terra medium and reviewed by root and Sol medium: PASS, 76 targeted tests in five suites, including five new tests. The per-owner observation directly contains `noNewViolation`, `moderate` or `unavailable`. The predicate requires a new, positive charge, successfully acquired, that leaves the account beyond credit. A positive proof remains valid even when a measurement of another process is missing; in the absence of such proof, an incomplete round is not declared healthy. The persistent accounting error remains unavailable.

Root asked to avoid a second, parallel list of owners and to actually prove debt repayment down to a balance of exactly zero. The tests also verify multiple processes in the same round, isolation between owners, and explicit/periodic samples at the same instant without replaying a native measurement already consumed. The report distinguishes the first compilation, due to a missing API, from the subsequent behavioral red with the classification branch disabled and from the final green.

The [wiring to runtime health](../../../.scratch/cascade-product/issues/51-addon-runtime-cpu-health.md) is implemented by Sol medium and reviewed by root and Sol medium: PASS. The runtime owns the coordinator and `AddonHealthStore`, with sessions tied to identity/version and canonical incarnation, with no external batches to reapply. One operation at a time prevents duplicate deliveries or partial registrations; revalidation after the waits discards stale measurements. Debt and history survive the provider's restart. The third violation records the version's internal quarantine, without yet introducing a sanction on admissions.

The review corrected a cleanup omission: deadline stops could leave an observation binding registered. Detachment now goes through `hasDeferredCleanup` and the common protected drain; registration and sampling reject pending or active cleanup. The binding cannot be reused before the previous detachment. Eight new tests also verify distinct owners, missing data, duplicate/rejected registrations, rollback, stop during a read and exit during registration. The fixtures' pauses are limited to five seconds. A behavioral red with incident recording suppressed produces eight expected errors; the restored version passes.

## Boundaries

All the work concerns the addons. No launcher, native adapter or timer is activated; the observations do not prove process authentication, stop or physical exit. Qualification on other platforms and the energy cost remain separate. The tests with synthetic adapters and reads prove the internal logic, not native guarantees.

The concrete reaction to the first overruns requires [defining the reduction of new work](../../../.scratch/cascade-product/issues/52-addon-cpu-reduced-admission.md). The existing limit is already one job per addon: the generic "reduction of grants" does not specify when to reopen. None of the alternatives is implemented yet. The launcher block remains unchanged.

## Evidence

[Classifier report](../../../.scratch/codex-addon/20260921-cpu-violations/task-50-report.md), [independent review](../../../.scratch/codex-addon/20260921-cpu-violations/task-50-independent-review.md), [composition design](../../../.scratch/codex-addon/20260921-cpu-violations/health-integration-design.md). Baseline: 1,122 tests in 99 suites and 482 build inputs frozen before the work.


## Final verification and delivery

- 100 targeted tests in total PASS: 98 in seven runtime suites and two in a transport suite.
- Full package suite run by root, exit0: **1,135 tests in 101 suites**, the sum of the five products (745/59, 112/11, 170/19, 91/10, 17/2). The CoreData message about the corrupted database belongs to an expected negative fixture.
- Root and independent reviews PASS on the four frozen files: two modified sources and two new test files. No pre-existing input removed; other sources of the dirty checkout preserved.
- Official build `scripts/build-development.sh` on an identical local copy of the **484 inputs**: SDK check PASS (4 packages, 11 targets, 90 Swift sources, 140 imports), Xcode Debug PASS, Apple Development signature and `codesign --verify --deep --strict` PASS. Original/copy hashes and reviewed files rechecked after the build.
- `/Applications/Cascade.app` updated to the verified build. Normal quit and relaunch **PID 25071 → 32112**, executable path matching the build and stable presence verified after five seconds.
- Remaining weekly budget **90%** at the last check; no reset used. Work stopped at the new design decision 52, not because of budget. Wayfinder used only for the addons; launcher and native qualification remain separate.

[Runtime report](../../../.scratch/codex-addon/20260921-cpu-violations/task-51-report.md), [runtime review](../../../.scratch/codex-addon/20260921-cpu-violations/task-51-independent-review.md), [root review](../../../.scratch/codex-addon/20260921-cpu-violations/root-review.md), [full suite log](../../../.scratch/codex-addon/20260921-cpu-violations/package-tests.log), [build log](../../../.scratch/codex-addon/20260921-cpu-violations/application-build.log), [verified delivery](../../../.scratch/codex-addon/20260921-cpu-violations/delivery.json), [input check](../../../.scratch/codex-addon/20260921-cpu-violations/input-verification.json).
