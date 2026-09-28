# Service invocations between SDK and runtime

18 September 2026. **Implementation reviewed and delivered: 1034 tests / 93 suites PASS, signed build and relaunch verified.** The [plan](../plans/2026-09-18-addon-service-invocation-host.md) covers the internal invocation path, not the complete public client or the native transport.

## Implementation

Six new files and six updated Runtime files connect the consumer request, the provider invocation, the raw completion and the consumer response. The runtime cumulatively enables 1.3 only with complete assembly, pre-admitted capabilities and canonical negotiation; earlier connections keep the expected behavior. The new complete connections compose the same generation for publications and services without rewriting grants already issued.

The routes retain bounded metadata, with consumer/provider slots reserved before the work. Exact receipts distinguish payload release, command completion and process exit. The internal SDK executor owns the whole operation, validates the complete response before projection and preserves the uncertainty after a possible exposure, even for operations called read. It does not retry automatically.

The review found two windows that could leave a completion queued: while another response is being sent and in the final part of the cleanup. The drain owner now records the events for the whole cycle and resumes the work after the guards. Failed refunds are retried at most once per cycle; a new refund that arrives during cleanup keeps its right to a first attempt. The final review closes both findings and the fix for the new refund.

## Current evidence

| Check | Result |
| --- | --- |
| Original selection of the increment | 275 functions / 17 suites / 417 cases, original snapshot |
| Actual AddonContext assembly | One targeted test PASS; the fixture's private adapter for invoke |
| Final cleanup fix | 54 functions / 6 suites / 120 cases PASS |
| Full suite on the final code | **1034 tests / 93 suites PASS**, exit 0, 17.61 s |
| Final code inputs | 463 sources/configs verified against the freeze |
| Exact copy for the app build | 433 inputs, separate and immutable snapshot |
| Runtime Release | PASS, exit 0, 16.11 s |
| Final review | PASS; no remaining P1/P2 found |
| Signed build and Applications link | PASS, exit 0, 12.27 s |
| Normal relaunch | PID 68582 → 18542, correct path and 5 s of stability |

The selections overlap and must not be added together. The behavioral REDs reproduce the stuck completions and the new refund wrongly skipped; the compilation and fixture preparation errors are kept separately. The final freeze contains Runtime `fc280f69be0b441822a0d536766f33d5069891b4b2490baed7f10c8764637906` and integration tests `bafa5bcdc1b82417dc2ee2f1ccbc626e3b0055e66d82af175b882e4e6f8d8d68`.

[Original review](../../../.scratch/codex-addon/20260918-continuation/service-host-independent-review.md) · [First fix and cleanup finding](../../../.scratch/codex-addon/20260918-continuation/service-host-review-fix-independent-review.md) · [Final handoff with evidence and hashes](../../../.scratch/codex-addon/20260918-continuation/service-host-cleanup-fix-report.md) · [Root verification](../../../.scratch/codex-addon/20260918-continuation/service-host-cleanup-root-verification.json).

## Precise qualification

The AddonContext test uses real storage and assets and forwards invoke to the real executor through an adapter private to the test; unused subscribe/unsubscribe raise explicit errors. It is not a partial public conformance. The global route limit of 32 is qualified statically; the real process cap is 3 and is not raised for the tests.

The cleanup's DEBUG checkpoint is immediately before the assembler's real refund. The fixture verifies pending resources and counters of the real governor, without claiming a pause inside the governor or during its actor hop. The checkpoints expose only scalar phases, without authority; the Release compilation of the final code passed.

Dedicated frames of 196608 bytes and payloads of 65536 bytes are not measured Foundation/RSS allocation limits. Still to be built: the complete public client with controls and subscriptions, the native transport and bootstrap, and the qualification of the platform/real processes. The observeExit calls in the tests are modeled inputs, not proof of process death. Global C3 and the C0d gate remain open.

[Final review PASS](../../../.scratch/codex-addon/20260918-continuation/service-host-cleanup-fix-independent-review.md) · [Relaunch evidence](../../../.scratch/codex-addon/20260918-continuation/service-host-cleanup-restart-evidence.json). `/Applications/Cascade.app` points to the Debug Apple Development build just compiled. SHA256 of the executable: `e15bd834d0ace8067a8376786c39b93e7f83d530f48aa5eb83c39a96fed9c2f4`.
