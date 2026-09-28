# Service control and subscription syntax

> **For agentic workers:** Use superpowers:subagent-driven-development and verification-before-completion. Execution mode is already authorized; do not ask again.

**Goal:** Implement independently testable, bounded service control/source/event syntax.

**Architecture:** A separate Foundation-only codec keeps invocation1.3 immutable. Schema1 closed DTOs describe acquisition phases and persistent source correlation without creating authority or enabling runtime1.4.

**Tech Stack:** Swift6, Foundation, Swift Testing, macOS14 package floor.

**Spec:** The subscription preflight linked below, with this plan's explicit phase and separate-codec decisions.

Status: implemented, independently reviewed, integrated and delivered; no runtime activation. The user's sustained Codex-only continuation authorizes this pure contract increment. It extracts the closed syntax from the [subscription preflight](../../../.scratch/codex-addon/20260918-continuation/service-subscription-preflight.md), including its correction for acquisition acknowledgment and persistent source identity. Host, full SDK client and activation remain a subsequent complete integration unit. This syntax can be implemented independently while the invocation host receives its concurrency correction.

## Ownership

Create exactly six files under CascadeKit: Sources/CascadeContracts/ServiceControlRequest.swift, ServiceControlReply.swift, ServiceSourceStartFrame.swift, ServiceSourceOutputFrame.swift, ServiceSubscriptionFrameCodec.swift and Tests/CascadeContractsTests/ServiceSubscriptionContractTests.swift. Root selects a separate codec rather than modifying the delivered invocation codec: explicit method/profile separation keeps invocation-only decoders unchanged. No existing source, Package, Runtime, SDK, example or native change. Work in an isolated Contracts-only harness copied from current source; root imports only the six frozen files after the invocation-host delivery. Harness results are not full-package results. Preserve immutable preimages and all existing work; no Git mutations.

## Closed shapes and semantics

Use Foundation-only Sendable/Equatable validated Codable values and existing nested contracts.

- Request: schemaVersion1, requestID, kind. acquire adds operation restricted to OperationRequest.requestService; subscribe adds requirementID and grantID; unsubscribe adds subscriptionID. No owner, permission, partition, lifetime or provider claims.
- Reply: schemaVersion1, requestID, kind, phase, result. Phase is admission or terminal. The sole admission result is accepted for acquire, with no extra fields or Grant. Terminal acquired adds Grant for acquire; subscribed adds subscriptionID for subscribe; acknowledged has no extra fields for unsubscribe; refused adds failureCode/failureReason for any kind; outcomeUnknown has no extra fields for any kind. No other phase/result/kind combinations. Refusal is pre-effect only; accepted acknowledges committed intent, not readiness. Code outcomeUnknown cannot appear inside refused; reasons are nonempty and <=4096 UTF-8 bytes without normalization/truncation. All result shapes reject extra/null case fields.
- Reply validate(matching:) checks exact requestID/kind, legal phase/result, and acquired Grant.scope against the acquire request's scope. RequirementID is a binding name, not necessarily Grant.serviceID: do not invent equality. Grant owner/generation/current authority are later canonical channel checks. A caller must track acknowledgment ordering separately; a single DTO does not prove lifecycle order.
- Source start: schemaVersion1, kind=sourceStart, sourceID, startNonce, providerID, publisher, digest, contractVersion, serviceID, partition, scope. Use existing AddonID, semantic version and ServiceScope values where appropriate; no Runtime imports. Publisher/digest/partition are nonempty bounded UTF-8 strings (256/512/256 respectively). These are host-issued descriptor claims, not consumer-selected authority.
- Source output: schemaVersion1, kind, sourceID, startNonce; startupCompleted carries no response, sourceUpdate adds ServiceResponse. validate(matching:) checks sourceID/startNonce and, for updates, serviceID/operation against the start descriptor. Readiness, verified provider incarnation and canonical source lifetime remain host checks, not UUID authentication.
- Dedicated codec has ServiceSubscriptionFrameProfile.v1_4 and explicit encode/decode operations for control requests/replies, source starts/outputs, and existing ServiceEvent. P1 ServiceProviderFrame/ServiceFrameCodec and generic AddonEvent remain unchanged and reject these source forms. Profile selection alone neither negotiates nor authenticates.

## Bounds and finite tests

Raw body <=196608 bytes checked before Foundation decode; decoded response payload <=65536, refusal reason <=4096. Validate original values and actual encoded output. Sorted-key JSON. Reuse existing strict nested validation. Nil profile fails. No double-base64 outer-envelope or allocator/RSS guarantee.

Use compiling behavioral RED then focused GREEN and adjacent Contracts tests in the isolated harness. Cover each legal shape, illegal phase/kind/result combinations, every correlation field, unknown/null/extra nested security fields, non-requestService acquire, malformed scalar/version/UUID/date values, nil profile, reason bounds including multibyte and control characters, raw cap+1, decoded cap+1, and service/source/event separation from P1/generic codecs. Exercise emitted and fully slash-escaped 65536-byte all-FF source updates and ServiceEvents with maximum metadata. Enumerate wrapper bounds (owner255 ASCII, identifiers128 ASCII, grant/date/resource fields; source publisher/digest/partition escaping <=6144 bytes) and prove the metadata wrapper stays below8192 and the complete frame below196608. Also test bounded malicious overexpanded Unicode/whitespace rejection. No fixed inflated test-count target.

Freeze exact diff, all baseline hashes, new-file hashes, actual logs/status and limitations. Independent review precedes root import/full-suite/signed-app delivery. No runtime profile1.4, public transport client, subscriptions, native peer/bootstrap, OS parity, process-death or complete C3 claims follow from syntax tests.

## Execution checkpoints

- [x] Capture byte-exact Contracts baseline and isolated harness identity.
- [x] Add the concrete closed-shape, correlation and maximum-frame tests described above; record compiling behavioral RED.
- [x] Implement only the six owned files; preserve every baseline input.
- [x] Run focused and adjacent Contracts tests; freeze bytes, logs, hashes and limitations.
- [x] Obtain independent specification and code-quality review; fix meaningful findings.
- [x] Root imports the six files after invocation-host delivery, verifies the complete package and performs signed app delivery.

No commit step: the shared dirty checkout must be preserved without Git mutation.

[Isolated implementation and independent PASS](../verification/2026-09-18-addon-service-subscription-frames.md); root integration/delivery remains pending. Original RED input-capture limitations and later mutation replay are distinguished in the evidence.

Root delivery completed:1048 tests/94 suites,439 exact build inputs, signed build/link and verified normal restart to PID20946. [Final evidence](../verification/2026-09-18-addon-service-subscription-frames.md). Earlier pending statements describe the isolated gate at that time.
