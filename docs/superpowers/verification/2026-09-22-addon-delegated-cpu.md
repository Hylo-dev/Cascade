# Delegated CPU accounting: 22 September 2026

**Status: coordinator, reviews, full suite and signed delivery PASS. Broker integration still separate.** The user chose the conservative attribution in [Define the CPU attribution of services to consumers](../../../.scratch/cascade-product/issues/55-addon-delegated-cpu-attribution.md): the whole cost of the process to every canonical consumer active in the interval, with the process counted once in the physical total.

## Scope

[Charge CPU intervals to verified consumers](../../../.scratch/cascade-product/issues/56-addon-delegated-cpu-accounting.md) extends the internal coordinator with verified recipients associated with complete bindings. Sol medium implements; root and an independent Sol review. The accounting uses the existing accounts, with credit 100ms and refill 5ms/s, and preserves debt, validation and classification per owner/round. Repeated identities and the direct owner are deduplicated per physical row. Incomplete samples do not become zero, nor do they authorize a reopening.

The internal input is not proof of causality: the future host producer will have to demonstrate interest in the interval and authority. **The attribution is not yet automatically wired to the broker/runtime.** The new path does not activate the launcher, does not modify the public SDK and does not declare the native measurement of the addons qualified.

## Review

Delivered baseline: 1,153 tests/104 suites, 487 inputs. Initial budget 87%. The graph does not contain Cascade; discovery through the rg fallback. Dirty checkout preserved, no commit/reset or cache removal. [Brief](../../../.scratch/codex-addon/20260922-delegated-cpu/task-56-brief.md), [worker report](../../../.scratch/codex-addon/20260922-delegated-cpu/task-56-report.md), [root review](../../../.scratch/codex-addon/20260922-delegated-cpu/root-review.md).

The first delta summed the consumption in UInt64 before calling the account: root and the reviewer found an improper narrowing of the valid range, because the balance with credit can sustain a total just above UInt64.max. The verified fix reuses the original account's sequential charges, keeping a single final classification. The final corrected and frozen delta passes the independent review and the full suite.

## Frontier

The audits of the canonical records and of the specs identified a remaining choice: [Decide the CPU attribution in service chains](../../../.scratch/cascade-product/issues/57-addon-transitive-cpu-attribution.md). The approved conservative rule determines how much to charge a consumer, but does not decide whether A should pay for C's CPU when A uses B and B uses C. The broker composition must know that rule before producing the set of recipients.

The [integration survey](../../../.scratch/codex-addon/20260922-delegated-cpu/integration-audit.md) also preserves the technical constraints: interests that outlive processes, work completed between samples, time windows, health without a process, and synchronization. None of the technical alternatives is implemented or presented as a native guarantee.


## Final code checks

Root and [independent reviewer](../../../.scratch/codex-addon/20260922-delegated-cpu/task-56-independent-review.md): PASS, no open findings. Eight new tests; final targeted run **126 tests PASS** (124/11 suites and 2 transport), exit0. The red test temporarily disables the inclusion of recipients, detects the expected failure and restores the code; it is behavioral sensitivity after implementation, not initial TDD. [Final targeted log](../../../.scratch/codex-addon/20260922-delegated-cpu/task-56-fix-green.log).

Root full suite: **1,161 tests in 105 suites PASS**, exit0. Totals of the five products 771/63, 112/11, 170/19, 91/10, 17/2. [Full log](../../../.scratch/codex-addon/20260922-delegated-cpu/package-tests.log). Build snapshot: 488 inputs verified byte for byte, with the pre-existing dirty checkout preserved.


## Verified delivery

The official script `scripts/build-development.sh` ran the SDK boundary check before Xcode and ended with **BUILD SUCCEEDED**, exit0, with the Apple Development signature verified. `/Applications/Cascade.app` points to the build just produced in DerivedData/CascadeDevelopment. All 488 inputs match between the snapshot and the original checkout after the build: compared with the baseline, only ProcessMetricsCoordinator.swift changes and the suite ProcessMetricsDelegatedCPUAccountingTests.swift is added; no file removed.

Cascade quit normally and relaunched: PID **42941 → 46952**, executable path matching the updated build and stability verified for 5 seconds. [Build log](../../../.scratch/codex-addon/20260922-delegated-cpu/application-build.log), [input verification](../../../.scratch/codex-addon/20260922-delegated-cpu/build-input-verification.json), [relaunch evidence](../../../.scratch/codex-addon/20260922-delegated-cpu/delivery.json).

Tracker updated: 57 tickets, 40 resolved, 17 open and unassigned, 7 available and 10 blocked, no residual claims, acyclic dependencies. Final budget 14% consumed, **86% remaining**; no reset. The work stops at the design choice on chains, not at the 75% threshold. Sol/Terra ran distinct audits, Sol implemented and a separate Sol reviewed; root checked the delta, corrected the arithmetic finding through the worker and verified the delivery. No changes to subsystems outside the addons in this tranche.
