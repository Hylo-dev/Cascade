# Offline pre-attach bootstrap abort model

Status: complete within the offline scope.31 tests, exact root replay and independent review PASS; protected inputs unchanged and project app restart verified. [Final evidence](../verification/2026-09-18-addon-bootstrap-abort-offline.md). Codex continuation authorizes this source-only diagnostic; no native execution or product-policy decision is included. Hard stop2026-09-18T22:00Z.

The [prior design investigation](../../../.scratch/codex-addon/20260918-continuation/managed-process-design.md) specifies the chosen scope. This is an independent finite model beside Tracing diagnostics. It must not import the operational driver modules or create OS authority. No native process, pipe, signal, ptrace, wait/kqueue, subprocess, filesystem execution input or app code belongs to the model. Native/model evidence cannot be interchanged.

## Protocol and state

- A trusted bootstrap is modeled before attach only. Its closed bounded control format contains a fixed version,32-hex nonce, explicit bootstrap phase, strict increasing sequence and a closed command set: one bootstrap advance and one normal baseline completion. No attach, trace or worker-exec command is admissible.
- Use explicit bounded length framing on bytes, accumulate fragmented reads and handle coalesced records. Set and document small fixed frame/total/frame-count limits. Retain at most the fixed partial-frame bound; reject oversize before copying/retaining it. This is Python model storage, not an allocator/RSS proof.
- Use caller-supplied monotonic integer time and a fixed absolute deadline. Partial reads, EINTR and valid progress never renew it. The deadline is terminal at equality; invalid/backwards time fails closed. States and predicted exit codes are terminal/immutable after completion or abort.
- Predictions: EOF at a valid frame boundary70; malformed/truncated/wrong nonce/phase/sequence/unknown command71; absolute timeout72; setup/local I/O failure73; explicit normal baseline completion0. HUP alone is not EOF. Buffered bytes must be processed before EOF; partial bytes plus EOF select71. Adverse facts in the same observed batch dominate success. A token cannot prove its writer is alive.
- A leaked writer produces no EOF and therefore no70; deadline leads72. No watchdog, sleep or polling is implemented. The caller advances modeled time deterministically.

## Evidence boundary

A separate pure evaluator accepts only explicitly labeled simulated fixture observations with exact retained synthetic run/child identity. No output may set `trustedBootstrapAbortObserved`, `supervisorDeathStopsWorker`, `nativeLauncherAdmitted` or native success true. Expose a separate narrow `modelAbortEvidenceConsistent` result and reasons. Clearly document that caller-provided records are not authenticated kernel evidence.

A consistent simulated death case requires exact matched observer identity retained before injection; child and supervisor exits with valid statuses, supervisor status agreeing with direct wait; child70, actual modeled EOF decision, no normal-completion/attach/exec grant; injection and all required receipts/directwait in one explicit observer-clock window strictly before1.5seconds; no receipt preceding injection; no timeout/guard/fallback/cleanup/error or contradictory same-batch record. Missing/duplicate/malformed fields fail closed, including bool-as-int, wrong clock/domain, nonfinite times, swapped/recycled identities and log-only exit. Original native clocks must never be subtracted from observer timestamps. Keep other modeled status codes rejected for abort-evidence success. Inputs and event-count limits must be explicit.

The evaluator is not a general decoder of historical C0d reports. Do not change the existing record schema or introduce a report that the admission path could accept. Fresh synthetic schema names and synthetic-only outputs are required. The existing native reducer is not imported because that imports operational capabilities; only separately justified pure normalization may be reused by copying a narrow convention with provenance, not by mutating historical code.

## Files and ownership

Only new `Prototypes/AddonPlatform/Tracing/bootstrap_abort_model.py` and `Prototypes/AddonPlatform/Tracing/test_bootstrap_abort_model.py` are worker source ownership. Root owns this plan, ticket, standalone model README/public verification and tracker. Keep `TraceProbe.c`, all current run modules, scripts/test-addon-managed-death.sh, entitlements and app/package source byte-identical. Archive initial baselines of protected files and candidate snapshots. No Git commands/mutations or shared SwiftPM caches.

## Finite acceptance

- [x] Pin protected native/app inputs and implement compiling behavioral RED, then GREEN without fictional native evidence.
- [x] Cover EOF before first token, after one token, valid token+EOF in one batch, all frame split positions/coalescing, truncated frame+EOF, timeout precedence, repeated/out-of-order tokens, invalid fields, oversize bounds, setup/read failure, HUP without EOF, leaked writer and immutable terminal state.
- [x] Cover absent child exit, invalid status, log-only success, guard/fallback/cleanup, mismatched retained child identity, same-batch contradictory facts, clock/domain and strict1.5s window, duplicate/malformed observations. Positive synthetic consistency must leave every native success field false.
- [x] Independently review exact source/specification and executed evidence; correct concrete findings.
- [x] Root reruns the offline tests on exact frozen sources, verifies protected hashes, documents finite limits, updates tracker. No app rebuild is required for Python diagnostics; normal app restart/verification still follows the project completion rule.

Design choice: a fresh pure module prevents accidentally reaching the older operational driver from these tests. This is neither a launch mechanism nor a proof of startup liveness before bootstrap code can run. The full creation→attach→exec lifetime contract remains unresolved.
