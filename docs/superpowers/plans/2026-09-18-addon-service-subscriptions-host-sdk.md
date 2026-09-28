# Complete service subscriptions implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development, test-driven-development and verification-before-completion. The user already selected continued Codex execution. Do not ask again for execution mode or routine internal choices.

**Status:** Delivered and independently reviewed PASS.1084 tests/96 suites, Release Runtime and guarded Apple Development app build PASS; normal restart PID85871 verified. [Final evidence and finite limits](../verification/2026-09-18-addon-service-subscriptions-host-sdk.md).

**Goal:** Complete the public service message client with real acquire/control/source/event host paths, then activate cumulative protocol1.4 only for a complete canonical assembly.

**Architecture:** Existing ServiceBroker retains canonical permission, interest, source, grant and invocation history authority. New bounded runtime state holds connection/alias/source correlations and a paid latest-state cache. Invocation and controls share one connection admission/sequence domain; events use exact receipts and bounded coalescing. The SDK exposes all three existing AddonServiceClient methods only when implemented together.

**Tech Stack:** Swift6, Foundation, Swift Testing, existing Runtime/Contracts/SDK targets and real ResourceGovernor; macOS14 package floor with execution evidence limited to the current machine.

**Spec:** Read the complete [subscription preflight](../../../.scratch/codex-addon/20260918-continuation/service-subscription-preflight.md), [root technical disposition](../../../.scratch/codex-addon/20260918-continuation/root-subscription-integration-boundary.md), and [closed syntax plan](2026-09-18-addon-service-subscription-frames.md). The root decisions below supersede the preflight's older P1 codec-extension and implicit reply-phase suggestions.

## Global constraints

- Keep ServiceFrameCodec and the invocation lifecycle ledger unchanged. Use the delivered separate ServiceSubscriptionFrameCodec and explicit admission/terminal reply phase.
- Preserve all existing permission, trusted partition, source/version/feature binding, command/lifetime/deadline, process/job and resource ceilings. No new consent or quota policy.
- Keep legacy0/1/2/3 behavior; a syntax profile or offer cannot enable runtime1.4. Existing common generation composition applies to complete negotiated connections, not copied grants.
- No per-route timer, polling, unbounded AsyncStream, event history, payload queue or second transport delivery slot. Shared deadline queue and bounded canonical owner remain authoritative.
- Failed refund retention never drives an unbounded retry loop. Preserve the reviewed invocation-host drain and its completion/close/cleanup-tail regression behavior.
- No native adapter/bootstrap/launcher/process-death qualification, no C0d change, no app operations by workers. Root owns final full checks, independent review and signed delivery.
- Preserve the dirty checkout and historical evidence. No Git mutation or cache competition. Shared SwiftPM caches have one explicit owner. No commit step.

## Owned files after explicit handoff

Create under `CascadeKit/Sources/CascadeRuntime/Services/`: RuntimeServiceAcquisitionState.swift, RuntimeServiceSourceBinding.swift, RuntimeServiceConnectionState.swift, ServiceSubscriptionRegistry.swift and ServiceLatestStateCache.swift. Their responsibilities and limits are specified in the preflight; these are internal state owners/projections, not alternative authority issuers.

Create under `CascadeKit/Sources/CascadeAddonSDK/Services/`: AddonServiceMessageChannel.swift, ServiceConnectionExchange.swift and TransportServiceClient.swift. Preserve AddonContext's public constructor invariants and all three AddonServiceClient signatures.

Create tests: `CascadeKit/Tests/CascadeRuntimeTests/ServiceSubscriptionMessageIntegrationTests.swift` and `CascadeKit/Tests/CascadePresentationTests/TransportServiceClientTests.swift`. A shared internal `CascadeKit/Tests/CascadeRuntimeTests/ServiceMessageTestSupport.swift` is permitted if needed to reuse the invocation fixture without duplicating its authority/governor setup; no production fixture API or fake broker/governor.

Modify only: Runtime/AddonRuntime.swift, AddonRuntimeTransport.swift, Services/ServiceBroker.swift, Services/RuntimeServiceInvocationExchange.swift, Admission/ProtocolNegotiator.swift, Admission/PublicationSessionRegistry.swift, Publications/PublicationState.swift; and the owned ServiceProtocolNegotiationTests.swift/ServiceInvocationMessageIntegrationTests.swift where complete assembly expectations or shared fixture extraction require it. Existing legacy tests cannot be weakened. Confirm exact repository paths from the pinned snapshot before editing.

Root narrow ownership addendum after final-regression20: AddonRuntimeSlotOwnershipTests.swift and AddonRuntimeStorageRequestTests.swift may update exact process-growth expectations only if the observed64-byte delta is independently derived from actual changed retained-record/receipt layout. Preserve exact equality, direct/indirect policy parity and every lifecycle assertion; no resource-policy increase, generic weakened inequality or production undercharge to preserve a stale literal. Capture preimages and final hashes. This authorizes a factual accounting expectation correction, not unrelated test changes.

No Contracts/Package/Xcode/example modifications belong to this unit. If the reviewed syntax exposes a real integration defect, report a concrete case to root before widening source ownership; do not silently relax the protocol.

## Milestone 1 — Canonical projections and paid retained state

- [x] Pin the reviewed baseline and preserve actual preimages before editing. Start a focused compiling behavioral test for unauthorized acquisition/subscription and replacement retention.
- [x] Add internal broker lookups for the exact existing permission key, canonical subscription binding and source binding, plus current pending-wake checks. Return validated scalar/value projections; never make the returned projection itself a later authorization token.
- [x] Implement bounded acquisition/connection/source/alias state and cache ownership. Source binding survives startup job retirement; alias authority is per physical connection and canonical interest; latest cache is one paid compact value per exact SourceKey. Admission reserves metadata and replacement overlap before retention. Revalidate after every suspension; revision exhaustion fails closed.
- [x] Test real governor denial/replacement, stale source/alias/grant, exact version including build metadata, feature and trusted partition separation; retained old backing stays paid across replacement. Freeze this internal dormant milestone for source review. No public-ready claim.

## Milestone 2 — Actual host controls, source legs and event scheduling

- [x] Add real byte-path tests for cold acquisition and two-phase acknowledgment. Before effects, authenticate the connection, resolve existing permission and prepay route/reply/path capacity. Commit canonical intent before launch exposure; accepted is not a ready grant. Source readiness and exact acknowledgment receipt precede terminal grant delivery.
- [x] Implement source-start/source-output handling with persistent current-provider incarnation/token/startNonce binding and the canonical publication sequence domain. Ready updates validate source/contract/operation and execute broker decisions. Startup receipt and startup completion retire different ownership.
- [x] Implement subscribe as a binding of an existing canonical grant without renewal or launch. Repeat subscription returns the same current alias and updates only its delivery-grant association. Unsubscribe removes the entire canonical interest and all its grants, invalidates pending invocations and executes real stop decisions; acknowledgment does not mean process exit.
- [x] Implement the shared invocation/control slot, phase-tagged exact receipts, paid latest cache and fair event drain. Replies have priority; after terminal retirement, one owed event precedes the next operation's effects. A request arriving behind an accepted event parks only its already-paid raw ingress handle and resumes on that exact event's receipt. No broker work or second request buffer is retained while parked.
- [x] Cover completion/close/revoke/expiry/source update and receipt events arriving during guarded cleanup/drain awaits. Demonstrate finish-event progress without an unrelated later event and at-most-once failed refund attempts per cycle. Preserve current authority checks after awaits and before handoff.
- [x] Run the relevant preflight integration cases against the actual runtime and governor, with normal negotiation still capped at the reviewed invocation level. Test fixtures may explicitly compose the complete dormant unit; profile/offer alone must remain inert.

## Milestone 3 — Full SDK and canonical activation

- [x] Write SDK whole-operation tests across invocation/control using one immutable connection descriptor, sequence domain, cancellation arbitration and shared physical drain. Do not compose two independently sequenced executors.
- [x] Implement TransportServiceClient.invoke, subscribe and unsubscribe together. Validate full correlated replies before projection; admission acknowledgments remain internal to acquisition plumbing. Possible exposure followed by unresolved cancellation/close is outcomeUnknown for every method, with no implicit replay.
- [x] Implement receipt-backed bounded event dispatch outside host admission, client locks and synchronous handoff. Release physical event staging before provider callbacks so a callback can await invoke/unsubscribe. Handle pre-subscribe-finalization events only within bounded paid ownership; unknown/stale aliases and generation/token mismatches never create authority. Close must not self-join a handler or claim to terminate already-running user code.
- [x] Assemble actual AddonContext with the complete real client, storage, assets and canonical ready grants. Exercise all three service methods through the real message path; fixture-only unsupported-method adapters cannot satisfy this milestone.
- [x] Activate1.4 only with complete handler, subscription adapter, cumulative storage/assets/invocation support, compatible host environment and prepaid maximum capacities. Both peers must qualify; preserve legacy/mixed-peer fallback, handshake constraints and attach rollback.

## Verification and delivery

The preflight's fourteen finite acceptance scenarios are binding; preserve each stated limit rather than targeting a test count. They include full slash-escaped64KiB source/event payloads, cold start partial effects, source-update identity after startup retirement, grant loss during preparation, real cache-overlap denial, exact phase/kind receipts, owed-event and parked-ingress fairness, callback reentrancy, cancellation/drain arbitration, canonical generation and legacy negotiation.

Use compiling behavioral RED then GREEN on stable input snapshots. Capture failed attempts honestly; do not relabel toolchain failures or mutation replays. Review internal milestone boundaries where useful, then obtain independent whole-unit specification and quality review before claiming a complete public client. The final source must pass affected tests, full GUI/package checks and Release Runtime compilation for conditional seams. Root alone performs immutable local app snapshot, signed build, Applications link update and verified normal restart. Native C3 and whole addon completion remain separate from this internal delivery.

Execution chronology qualification: the internal dormant milestones were not each independently frozen/reviewed before activation. This deviation remains disclosed in the final review; the complete combined unit and subsequent corrections received independent acceptance. Checked milestones record delivered outcomes, not a retroactive intermediate-review claim.
