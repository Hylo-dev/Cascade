# Connect the asset messages to the runtime and the SDK client

ID: 23
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-01a0b0f2
Blocked by: 21

## Question

Complete the message path for importing, sharing and releasing images between the SDK client and the canonical runtime, verifying it end to end with a test channel to the real runtime. This is an execution tranche explicitly admitted in the map's Notes, not a new choice of mechanism or a qualification of the native transport.

## Context

- Decision acquired: [Choose the image transfer between addon and host](21-asset-transfer.md).
- Implementation spec already prepared: [Authenticated asset messages and concrete SDK client](../../../docs/superpowers/plans/2026-09-15-addon-asset-message-integration.md).
- Plan, criteria and autonomous assignment of the pipeline: [Authenticated asset wiring: Astra Pipeline](../../astra-pipeline/20260915-124500/plan.md).

## Progress

15 September 2026: taken on by pi/Astra xhigh. Preflight succeeded; the expected configurations and authentication available. Pre-existing checkout saved separately from the Git baseline, without staging or commit. Plan explicitly approved by the user. Stop required below 35% of the available weekly GPT quota or when the DeepSeek credit runs out; official pre-dispatch check: 38% GPT available and 1.45 USD DeepSeek. First implementation produced by DeepSeek: 809 tests / 82 suites passed. The [Astra evaluation](../../astra-pipeline/20260915-124500/review.md) is PARTIAL because of cleanup/accounting/close-drain defects and missing evidence. First round of fixes paused at the user's request after the only worker already active finished. Latest suite: 811 tests / 82 suites; the cleanup fix has not been re-evaluated yet. Five waves not started, no subagent left active, no delivery approved. [Progress report and pause checkpoint](../../astra-pipeline/20260915-124500/progress.md). Resumption later authorized by the user, keeping the 35% GPT reserve and the DeepSeek credit. Checkpoint verified with no drift; the continuation completed further waves and received a new PARTIAL evaluation. Automatic stop at the 35% GPT reserve during the first wave of the last round: worker interrupted before its report, no subagent active. [Current report and checkpoint](../../astra-pipeline/20260915-124500/budget-stop.md). Ticket taken on but suspended for budget; no closing or delivery approved. The C0d gate remains closed.

17 September 2026: continuation request received in Codex and state recovered through Wayfinder. The live check of the authorized monitor confirms GPT 65% used / 35% available and DeepSeek 0.51 USD. Resumption gate closed because of the GPT reserve: no worker or evaluator started, no source changed, no build or restart of the unapproved version. The checkpoint and the PARTIAL evaluation remain valid as a resumption point, not as an approved delivery. Current reading: `../../astra-pipeline/20260915-124500/budget-latest.json`.

17 September 2026, resumption authorized: the user explicitly waives the 35% GPT reserve. Claim transferred to the Codex coordinator; no previous worker active. The existing final round resumes from the verification of the interrupted first wave; unchanged: technical criteria, worker/evaluator model and the stop when the DeepSeek credit runs out or at the provider's actual limits.

Current resumption: [provider verification and authorization](../../astra-pipeline/20260915-124500/resume-20260917.md). DeepSeek launch rejected by the auto-review pending explicit consent to transferring the sources; local tests started, no worker active.

Local verification of the resumption: checkpoint of the four files unchanged and `git diff --check` succeeded; targeted tests interrupted by the 300 s timeout during compilation (exit 124), with no new verdict. The already installed Cascade restarted normally and verified (PID 55327). No application source changed in this resumption.

18 September 2026: the user explicitly asks for Codex only, with 5.6 Sol medium or other models according to difficulty. DeepSeek routing and the related gate/credit replaced; no further consent to the external provider is required, since it is not used. Resumed in the [Codex plan](../../codex-addon/20260918/plan.md), keeping the technical criteria and the independent review.

## Answer

18 September 2026: Completed the authenticated internal message path for importing, sharing and releasing images between the SDK and the canonical runtime. Verified: exact slots and receipts, immutable assignments, non-terminal revocation of publications, connection closing distinct from disabling the owner, actual resource lifetime, bounded refunds and SDK finalization atomic with respect to closing.

Continuation carried out exclusively with Codex: Sol medium/high for bounded changes and reviews, Astra high for the security matrix and the overall evaluation. Final review **PASS** after the fix of the SDK P2, **883 tests / 83 suites passed**, 285 identical final inputs, Apple Development build succeeded, Applications link updated and restart verified (PID 50978). [Final verification and evidence](../../../docs/superpowers/verification/2026-09-18-addon-asset-message-integration.md), [independent evaluation](../../codex-addon/20260918/final-review-round2.md).

The production OS/bootstrap/launcher channel, the qualification of the decoder against hostile input, C0d, the final MainActor/SwiftUI integration and the macOS 14 runtime verification remain out of scope. No other global ticket is closed and no release is published.
