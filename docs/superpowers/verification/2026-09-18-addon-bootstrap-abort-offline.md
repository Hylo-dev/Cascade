# Offline bootstrap abort model — verification

Status: **PASS**, exact root replay and independent specification/quality review completed. Scope is the finite pre-attach model and synthetic evidence evaluator; native execution and the full managed-worker lifetime are unqualified.

The [binding plan](../plans/2026-09-18-addon-bootstrap-abort-offline.md) derives from the earlier design investigation. Two new Python files beside the Tracing diagnostics implement a bounded control stream and a separate closed synthetic fixture evaluator. The model has no native adapter and imports only dataclasses; tests import copy/dataclasses/unittest and the model. Root checked the exact source AST/imports. This establishes the inspected import graph, not a Python security boundary.

## Finite behavior

Two-byte big-endian lengths frame exact ASCII advance/complete records, with a32-hex nonce and fixed bootstrap phase/sequence. There is no attach/exec/tracing command. Limits are96 payload bytes,196 lifetime bytes,two frames and97 retained partial bytes. Header/total limits precede payload retention. The absolute model guard is derived as start+2seconds, including direct dataclass construction; it cannot be extended by progress or replace(deadline_ns=...). Earlier terminal results remain sticky, while adverse facts in one current batch precede success.

Explicit EOF at a frame boundary predicts70; invalid/truncated input71; absolute deadline72; local setup/read failure73; normal baseline completion0. These are proposed diagnostic conventions, not OS-defined status meanings. HUP and no-data/EINTR notifications are not EOF. A completion followed by EOF cannot serve as the modeled abort case.

The evaluator accepts only labeled synthetic observations, exact retained run/role/instance/pid identities and required receipts in the same observer domain strictly before1.5seconds. The synthetic injection action and both supervisor status receipts must all indicate signal9; child status70 must match an internally possible EOF-only model projection. Missing, duplicate, malformed, wrong-identity, late, guard/fallback/cleanup or contradictory observations are rejected. Time counters from different domains are never subtracted. All caller-provided records/model objects are unauthenticated; tagged statuses are not native raw wait status.

Even a consistent result leaves trustedBootstrapAbortObserved, supervisorDeathStopsWorker, nativeLauncherAdmitted and nativeSuccess false. The only positive result is modelAbortEvidenceConsistent. No fake native proof is produced or accepted by an admission path.

## Executed tests and correction history

The worker's first compiling new stub failed its first behavioral EOF test; the expanded stub failed214 assertions/subtests across23 test methods. This is new-feature TDD, not a claim that an old production implementation had been changed or that each default-rejected negative case was independently reproduced.

Subsequent real regressions exercised malformed identities, exact built-in input shapes, the fixed two-second guard and a constructor path that could originally provide an arbitrary deadline. Root's source review then identified impossible EOF decision projections and a matching but normal supervisor exit admitted as synthetic consistency. Thirty tests reproduced19 failed assertions/subtests; the corrected evaluator validates every model field and the exact synthetic injected termination. All historical snapshots/statuses/logs are retained.

The frozen worker suite passes31 tests. Root independently reran the exact named suite with Python -B: **31 tests PASS**,0.13s command/0.028s reported test execution. This count is separate from the1084 app/package tests in the earlier subscription delivery. Source SHA256s:

- bootstrap_abort_model.py:37b189bdb34c4aabb5fde52021f8cf0454d36238e76d74f2c9ac37a5c6da5eb3
- test_bootstrap_abort_model.py:87a51b2563f7042c33240b4a2a7d91281ff3e5a1aada95e58a0a213791036c0e

Coverage includes every split position across the two coalesced frames, bytewise reads, every incomplete first-frame EOF point, byte/frame limits, ordering/unknown commands, absolute deadline equality/nonrenewal, terminal immutability, local failure and notification distinctions. Evidence tests include absent/log-only/invalid exits, every missing/duplicate observation, injected-action/status mismatches, impossible model states, identity/clock/window failures and same-batch adverse facts. This is finite case coverage, not exhaustive native scheduling, allocator or hostile-process proof.

Exact evidence is in `.scratch/codex-addon/20260918-continuation/`: `bootstrap-abort-worker-handoff.md`, `bootstrap-abort-worker-frozen-files.json`, `bootstrap-abort-worker-joined-command-status.json`, per-phase source snapshots/logs, `bootstrap-abort-root-unittest{.log,-status.json}` and `bootstrap-abort-root-import-review.json`. Initial/root findings are preserved separately. The worker’s protected551-file manifest and archived preimages match; root separately checked its11 original native/diagnostic and484 delivered app inputs unchanged. These are explicit manifest scopes, not a claim that every checkout file was frozen.

## Independent acceptance

The [independent review](../../../.scratch/codex-addon/20260918-continuation/bootstrap-abort-independent-review.md) is PASS with no residual finding. It verified both source hashes before/after, all12 worker phase records, archived snapshots/logs, the50-entry artifact manifest and the overlapping551/11/484 protected input sets. It also checked the publication drafts against the frozen implementation. Those sets overlap and must not be added as independent file counts. No reviewer execution is represented as another test run.

[Reproduction and model guide](../../../Prototypes/AddonPlatform/Tracing/BootstrapAbortModel.md).

## Qualification boundary

No native fixture, tracing call, signal, pipe, process observer, codesigning change or launcher was executed for the model. `scripts/test-addon-managed-death.sh` remains byte-identical with unconditional exit78. The model cannot prove liveness before bootstrap/main, physical exit, safe attachment/exec, hostile provider behavior, exact native observation or protection preservation. Supervisor3s/observer5s guards and the full creation→attach→exec contract remain separate unmeasured requirements. The [managed-process decision](../../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) stays open.

The two diagnostic Python files are outside the app's compilation inputs. The previously signed subscription/build-guard delivery remains the same executable. After review and publication, the project-required normal quit/relaunch passed: PID85871→96743, exact expected executable and Applications target, five-second stability, unchanged executable SHA2563c9f6cd268825a526ad6e491a9a87fe0ea9f5932752d5c82b8f96e87c28cbbac. Evidence: bootstrap-abort-root-restart-evidence.json in the continuation artifacts. This proves app availability only; no new app build or native diagnostic execution is attributed to these Python files.
