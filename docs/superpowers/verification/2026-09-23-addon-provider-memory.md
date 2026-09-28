# Provider RAM: 23 September 2026

Status: internal implementation verified, signed build and updated launch succeeded.

Choice "1" approves the [progressive 64/96 MiB profile](../../../.scratch/cascade-product/issues/65-addon-provider-memory-policy.md), limited to the physical owner already decided. Wayfinder is used only for the addons. Terra medium implements the [classifier](../../../.scratch/cascade-product/issues/66-provider-memory-episodes.md); Sol medium implements the [composition in the runtime](../../../.scratch/cascade-product/issues/67-runtime-provider-memory.md). Root and an independent Sol review the results.

## Contract

The moderate RAM incident opens an episode above 64 MiB and up to 96 MiB inclusive, without multiplying incidents while it persists. Recovery requires a current measurement of its own at 64 MiB or less. Above 96 MiB the expected-stop request prevails; no crash retry and no early physical release. A missing or stale measurement does not count as zero. Wake and a new registration do not reset the episode of the same incarnation; a new incarnation does not by itself remove the per-owner pause.

CPU and RAM have independent pauses and share the history: a single moderate incident per owner/round, per-version quarantine preserved. RAM is not propagated to the consumers. New admissions and new interests respect both pauses; work already admitted and canonical reuse keep the earlier contracts.

## Evidence

- [Baseline and ledger](../../../.scratch/codex-addon/20260923-provider-memory/ledger.md): 497 initial inputs, 1,209 tests/113 suites of the previous delivery.
- [Classifier: implementation and tests](../../../.scratch/codex-addon/20260923-provider-memory/task-66-report.md), 3 tests PASS.
- [Root review 66](../../../.scratch/codex-addon/20260923-provider-memory/task-66-root-review.md) and [independent review 66](../../../.scratch/codex-addon/20260923-provider-memory/task-66-independent-review.md): PASS.
- [Runtime design](../../../.scratch/codex-addon/20260923-provider-memory/task-67-design.md) and [execution brief](../../../.scratch/codex-addon/20260923-provider-memory/task-67-brief.md).

## Final verification and delivery

[Runtime report 67](../../../.scratch/codex-addon/20260923-provider-memory/task-67-report.md): 10 RAM tests and 176 targeted tests PASS. The review corrected lifecycle tests that used the wrong entry point, activated real interests in the chain and bounded the memory of the tests' stop recorders. The policy was not modified to satisfy the tests. The report distinguishes the test-first classifier from the integration tested after the implementation and preserves the fixture's intermediate failure.

[Root review 67](../../../.scratch/codex-addon/20260923-provider-memory/task-67-root-review.md) and [independent review 67](../../../.scratch/codex-addon/20260923-provider-memory/task-67-independent-review.md) document the checks of the contract. The [final full suite](../../../.scratch/codex-addon/20260923-provider-memory/full-package-summary.json) passes with 1,222 tests in 115 suites: Runtime 832/73, Contracts 112/11, Kit 170/19, SDK 91/10, Tools 17/2.

Final command with Xcode-beta: `xcrun swift test --disable-sandbox --skip-build --package-path CascadeKit --scratch-path /private/tmp/cascade-addon-tests --no-parallel`, after the targeted compilation of the final files. The explicit caches and the outcomes are preserved in the tranche's evidence.

The [input verification](../../../.scratch/codex-addon/20260923-provider-memory/build-input-verification.json) compares 500 files of the build copy with the checkout: three files modified, three added and none removed relative to the baseline. `scripts/build-development.sh` completed the official signed build and updated `/Applications/Cascade.app`.

[Launch verified](../../../.scratch/codex-addon/20260923-provider-memory/delivery.json): Cascade was already closed; the updated build launched with PID 21839, signature and executable path verified, process stable after 5 seconds. Remaining weekly quota 77%; no reset credit consumed.

## Frontier

The [later audit](../../../.scratch/codex-addon/20260923-provider-memory/post-67-frontier-audit.md), including its correction on the UI baseline, finds no other increment of addon code that is already decided and independent. The remaining steps depend on the platform tests of tickets 19/22, still on hold. The approved launcher block remains valid; the same choice is not reopened and no UI classifier is invented before the required measurements.

## Limits

No launcher, new protocol, UI/audio profile or native control enabled. The tests with controlled adapters do not qualify OS identity, the footprint of a real addon or physical stop. The UI budget remains shared with the provider; the calibration and the semantics of the continuous profile await the planned measurements. No commit, reset, deletion of the checkout or consumption of reset credits.
