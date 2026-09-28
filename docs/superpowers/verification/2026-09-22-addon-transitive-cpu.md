# Transitive CPU and crash recovery: 22 September 2026

**Status: internal implementation, reviews, full suite and signed delivery PASS.** The [decision on chains](../../../.scratch/cascade-product/issues/57-addon-transitive-cpu-attribution.md) attributes CPU to the consumers reachable through simultaneously active interests, deduplicating identity/process/interval. The launcher remains blocked.

## Scope and CPU reviews

Wayfinder used only for addons. Sol medium implements ledger, coordinator and runtime; Terra medium integrates broker and demand projections; root and a separate Sol review. Dirty checkout preserved, no commit/reset, no cache cleanup. The knowledge graph does not contain Cascade; discovery through the rg fallback.

The [ledger](../../../.scratch/cascade-product/issues/58-addon-cpu-attribution-ledger.md) accumulates the union of the instantaneous closures between observations, avoiding chains built from edges that never overlapped. The [coordinator](../../../.scratch/cascade-product/issues/59-addon-coordinator-attribution-ledger.md) atomically pre-admits the verified domain and keeps the exact physical contributors. The [broker](../../../.scratch/cascade-product/issues/60-addon-broker-attribution-ledger.md) publishes and withdraws interests at the same canonical boundary, keeping them, where intended, beyond disconnect/exit.

The [runtime](../../../.scratch/cascade-product/issues/61-addon-runtime-transitive-cpu.md) shares the ledger and verifies again the authority of recipients and contributors after every read. A consumer without a process can receive delegated charges; a present process without its own valid measurement does not reopen admissions on the provider's credit alone. New acquisitions and invocations respect the pause of consumer and provider, preserving accepted work and the reuse of interests.

The review corrected a premature launch of providers before the consumer's rejection. It also kept the v1.4 ack after a commit followed by rollback, before the indeterminate terminal: adapting the test to the absence of the ack would have been a wrong protocol change. Three exact memory expectations were updated by 4 KiB, equal to the additional reservation per owner, keeping the refund check. [Root review](../../../.scratch/codex-addon/20260922-transitive-cpu/root-review.md), [independent runtime review](../../../.scratch/codex-addon/20260922-transitive-cpu/task-61-independent-review.md).

Targeted tests: ledger 29/3 suites, coordinator 49/5, broker 39/3, runtime 152/15. The deliberate mutation that removed transitivity made the expected assertions fail; it is not an initial TDD proof. Full suite before the retries: **1,195 tests/112 suites PASS**, exit 0, sum of the five products 805/70, 112/11, 170/19, 91/10, 17/2. [Full log](../../../.scratch/codex-addon/20260922-transitive-cpu/package-tests-before-retry-fixed.log).

## Crash recovery

The [demand and ticket support](../../../.scratch/cascade-product/issues/62-addon-crash-retry-projections.md) exposes bounded projections and cancellation of pending retries only. The [runtime wiring](../../../.scratch/cascade-product/issues/63-addon-runtime-crash-retry.md) passes root and [independent](../../../.scratch/codex-addon/20260922-transitive-cpu/task-63-independent-review.md) review. Only an unexpected exit classified by the host uses the session issued at handoff to apply 1/5/30 seconds with current demand, and quarantine at the fourth crash with demand. The default caller remains unclassified. No replay of work already delivered.

The crash decision is serialized by the shared cleanup after the broker's reconciliation. During the wait, the exact token prevents replacement launches and CPU sessions. A queued command must be unexpired; for broker interests the canonical expiry is compared with a fresh instant after the wait. The tickets use the same identifier as actions/cold start. The demand check before the resources and the later one share the same launch admission. Consumption and binding are prepared on a copy of the store and made canonical right before the handoff. Earlier rejections return the reservations; a rejected delivery spends the attempt. With no demand, the ticket is removed without launching a process.

Stop, disable and wake also cancel suspended decisions; wake preserves the health of active processes and CPU debt. The delegated CPU of a consumer without a process during the backoff goes through an operation authorized by the exact ticket, kept on `keep` and removed in quarantine. The review corrections include orphaned tokens, refund after pool growth, a false “no demand” outcome concurrent with a new interest, and deferred cleanup after a stop during the pre-check.

Final targeted check: **230 tests/20 suites PASS**, exit 0 (228/19 from the runtime and 2/1 transport). [Report and seven frozen hashes](../../../.scratch/codex-addon/20260922-transitive-cpu/task-63-report.md), [targeted log](../../../.scratch/codex-addon/20260922-transitive-cpu/task-63-final-cleanup-broad.log). The gates are deterministic; the timed waits bound only the watchdog. The stop test also verifies the draining of the cleanup and the absence of provider reservations.

## Final checks and delivery

Root full suite: **1,209 tests/113 suites PASS**, exit 0. Totals of the five products 819/71, 112/11, 170/19, 91/10, 17/2. [Final full log](../../../.scratch/codex-addon/20260922-transitive-cpu/package-tests.log). The seven frozen hashes match the worker's report and the independent one. The build that preceded the last corrections is preserved separately in the evidence; it is not the delivered one.

The official script `scripts/build-development.sh` runs the SDK boundary check and ends **BUILD SUCCEEDED**, exit 0, with verified Apple Development signing. Final snapshot of 497 inputs identical to the checkout even after compilation: 7 files modified, 9 added, none removed relative to the tranche baseline. The earlier dirty checkout is preserved. `/Applications/Cascade.app` points to the updated build in DerivedData/CascadeDevelopment. [Build log](../../../.scratch/codex-addon/20260922-transitive-cpu/application-build.log), [input verification](../../../.scratch/codex-addon/20260922-transitive-cpu/build-input-verification.json).

Cascade was already closed at the time of delivery. The updated version was launched, verifying the exact executable path, the signature and stability for 5 seconds: PID **62002**. [Launch evidence](../../../.scratch/codex-addon/20260922-transitive-cpu/delivery.json). No normal close is declared as performed on a process that was already absent.

Tracker: 64 tickets, 47 resolved, 17 open and unassigned, 7 available/10 blocked; no residual claim and acyclic dependencies. Final weekly quota 21% consumed, **79% remaining**; no reset. The work stops at the new RAM choice, not at the 75% threshold.

## Limits and frontier

The tests use controlled host bindings and adapters. They do not qualify OS identity, native exit classification, process termination, C0d or continuous UI/audio profiles. The CPU accounts persist for the lifetime of the runtime, not across a Cascade relaunch.

The next [attribution of observed RAM](../../../.scratch/cascade-product/issues/64-addon-memory-attribution.md) is a separate decision. The resident footprint is not a CPU interval and the earlier decisions do not authorize transferring it to the consumers. Candidate thresholds, aggregation and episode counting remain to be defined; no RAM implementation added in this tranche.
