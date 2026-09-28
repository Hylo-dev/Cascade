# Cascade addon protocol v1 — initial contracts

`CascadeContracts` is a Foundation-only, Sendable Swift 6 product targeting macOS 14.
CascadeKit keeps its existing product and language mode. These contracts apply equally
to bundled team addons and external addons; the manifest grants no privileges.

## Manifest

The public schema is [manifest.schema.json](manifest.schema.json). The `focus.json`
fixture copies the architecture example. `REQUIRES` at the root applies to the whole
addon; feature `REQUIRES` applies only to that feature. `sourceApp.required: false`
does not become a global application dependency. Libraries are inventory, not runtime
services. A bundle ID is a claim, never authentication.

Manifest/protocol major 1 is supported. The trusted host negotiates its compatible
minor and supported content schemas before admitting publication state. Defaults
remain 1.0; keyed-storage capability enables 1.1, and storage plus an asset-capable
adapter enable cumulative 1.2. A complete internal service invocation assembly enables cumulative 1.3 only with its adapter, handler, compatible environment and prepaid capacities. Cumulative 1.4 additionally requires the complete control/source/event handler and subscription adapter, with all earlier capabilities and prepaid maximum capacities. Asset frame schema 1 (`.v1`) is distinct from the
negotiated protocol minor; an untrusted offer cannot enable host capabilities. [Session negotiation and its native-integration boundary](sessions.md).
Package/service versions use SemVer, including explicitly written prereleases and
build metadata. Ranges are one to eight space-separated exact/comparison constraints
(`1.0.0`, `>=1.0.0 <2.0.0`); wildcards, caret, tilde and recursive boolean expressions
are rejected. The current OS condition grammar is `>=major.minor`.

Fallback shape: `{"kind":"anyOf","anyOf":[{"id":"namedAlternative","REQUIRES":[...]}]}`.
There are at most eight named alternatives, containing only leaf requirements. All
requirements arrays have at most 32 entries. Features, provided services and library
inventories have at most 64 entries and unique IDs/names. Feature `actions`, when
present, has at most 64 unique validated identifiers. Unknown security fields and
unknown discriminants are rejected conservatively. Root metadata is also closed in
this version. More permission/resource profiles require a versioned SDK extension;
the implemented permission is `storage.own` scoped to `addon`.

The event-driven profile requests 0...64 MiB and 0...1 concurrent work items, with
`scheduledDeadline` or `none`. The host can grant less; declarations are not grants.
The incompatible fixture changes only `id` and `REQUIRES` from Focus. The cycle
fixtures also change `PROVIDES`, so each publishes the service required by the other.
These fixtures are dependency-resolution inputs; manifest validation alone does not
establish successful resolution or runtime admission.

## Encoding and admission

Use `AddonManifest.decode`, `ProtocolOffer.decode` and `ProviderOutput.decode` at raw ingress. They check raw
bytes before JSONDecoder. All model `init(from:)` paths validate semantic bounds;
direct JSONDecoder calls cannot bypass the model checks but cannot measure whitespace
or parsing allocations. The transport must enforce its raw frame limit before creating
a decoder. Canonical JSONEncoder bytes define nested encoded-size accounting; Data is
base64 in JSON, with both decoded Data bounds and total encoded envelope bounds applied.
Dates use Foundation Codable's finite seconds since 2001-01-01 UTC. UUIDs use strings.

| Value | Maximum |
| --- | --- |
| Raw manifest | 65,536 bytes |
| Raw ProtocolOffer | 8,192 bytes |
| ContentDocument and complete PresentationSet | 65,536 encoded bytes each |
| Content tree | depth 8, 128 nodes, each text/label 4,096 UTF-8 bytes |
| Timeline | 32 entries, 262,144 encoded bytes for the entire array |
| Raw/encoded ProviderOutput | 524,288 bytes |
| Publications / operations | 16 each, independent of byte bounds |
| Action input | 4,096 decoded bytes |
| Action result / service payload / checkpoint | 65,536 decoded bytes each |

Content schema1 remains valid; schema2 adds up to eight bounded [glass lights](../architecture/glass-lighting.md).
Session admission checks every representation and every future timeline entry against
the negotiated schemas. A schema2 document still requires schema2 support when its
optional light array is absent or empty; a schema1 wire document must omit that key.

`ContentNode.kind` is one of text, symbol, image, row, column, progress, countdown,
clock, action. Each kind admits only its defined value fields. Images refer to declared
opaque asset IDs, never paths or embedded image bytes. Asset transfer stays separate from ProviderOutput. The internal host now admits
[publication-scoped assets](assets.md) and negotiates cumulative protocol 1.2 for an asset-capable adapter; the public SDK asset client/handle support explicit sharing and a concrete message client over an injected channel, while a production OS transport remains to be connected. Progress is finite in 0...1. Action IDs are unique within a
document. Tree decoding has an additional coding-path bound before recursive descent.
No SwiftUI builder, renderer, transport or broker is provided by this target.

`PresentationSet` is a closed object with keys `widget`, `compactLeading`,
`compactTrailing`, `minimal`, `expanded`. A widget needs `widget`; an activity needs
both compact representations, minimal and expanded; a notice needs both compact
representations and minimal and forbids expanded. Representations share one
PublicationID/revision. A publication contains exactly one of `content` or `timeline`.
Timeline dates increase strictly and precede `expiresAt`. `stalePolicy` is
`retainMarked` or `remove`. Canonical host admission enforces activity/notice session
lifetime caps separately from these wire values; revisions do not renew the session
deadline.

PublicationID contains `addonID`, `instanceID`, `sessionID`. It carries no authenticated
publisher claim: the host must map its verified publisher/peer to an assigned AddonID.
The host opens a canonical `PublicationStore` connection using verified identity and
host-assigned IDs, then admits output through `acceptPublicationState`. This boundary
derives revisions from the actual store and checks generation, sequence, assigned IDs,
negotiated schemas and expected completion before committing publication state.
`ProviderOutput.validateContext` remains a value-level check, not authentication.
Revisions are UInt64 and strictly increasing within a publication session; a reset
requires a new host-assigned session. The [session guide](sessions.md) explains retained
history, revocation and the native transport work still required.
`ConnectionGeneration` is a fresh UUID per handshake, independent of publication life.

## Messages

ProviderOutput has `schemaVersion: 1`, `publications`, `operations`, optional
`completion`, optional `checkpoint`. Missing completion means state only, including
when an invocation is pending. It never implies command success.

OperationRequest has a `kind` discriminator and case fields:

- `requestService`: `requirementID`, `scope` (`featureID`, `operation` only).
- `schedule`: finite `deadline`, validated `eventID`.
- `releaseLease`: UUID `leaseID`.
- `endPublication`: `publicationID`.

ActionRequest carries schemaVersion, requestID, publicationID, actionID, input,
deadline and observedRevision. The host attaches its connection generation when
sending; it is not selected by the action's author. The host [action coordinator](actions.md)
checks the current verified feature and published payload, then revalidates at one-use
delivery. A decoded ActionRequest alone grants no execution authority. ServiceInvocation carries
schemaVersion, requestID, contractID, operation, payload and deadline. ServiceResponse
carries schemaVersion, contractID, operation and payload.

InvocationCompletion uses Swift Codable's explicit associated-value object:
`{"action":{"requestID":"UUID","outcome":{"completed":{"payload":"BASE64"}}}}`
or `{"service":{"requestID":"UUID","response":{...}}}`. Exactly one result case is
allowed. ActionOutcome is `completed(payload)`, `rejected(reason: AddonFailure)` or
`outcomeUnknown`. Transport acceptance is not an outcome. Correlation checks reject
wrong request IDs, action/service swaps and wrong service contracts/operations.

Grant holds id, owner, serviceID, closed scope, expiresAt, generation and granted cost.
Lease holds id, grant and a positive monotonicDeadlineNanoseconds. These serializable
values are host-issued claims: the [service broker](services.md) validates its canonical
records, expiry, scope and generation; possessing decoded JSON does not authorize an
operation. Native peer authentication and actual dispatch remain to be connected.

## Error registry

AddonFailure is `{ "code": "…", "reason": "…" }`. Reasons are bounded to 4 KiB UTF-8;
Swift construction preserves whole graphemes up to 4,096 UTF-8 bytes. Empty input,
or an initial grapheme larger than that budget, uses a readable fallback. Decoding
rejects invalid wire reasons instead of normalizing them. Nested rejected outcomes
validate the same reason invariant. Consumers branch on code, not reason text.

| Code | Meaning / remedy |
| --- | --- |
| missingRequirement | Required installed capability is absent; enable a compatible provider. |
| versionConflict | No permitted version satisfies the constraints; change compatible versions. |
| permissionDenied | Consent or system permission is missing; review the relevant permission. |
| dependencyUnavailable | Previously usable dependency is unavailable; retry on a real availability event. |
| resolutionTooComplex | Graph/search budget exceeded; simplify dependencies. |
| resourceDenied | Admission budget is unavailable; reduce or defer work. |
| rateLimited | Request/update credit exhausted; wait for granted credit. |
| deadlineExceeded | Work did not complete before its deadline; no implicit retry. |
| sessionRevoked | Generation, grant or session is no longer valid; renegotiate. |
| invalidPayload | Malformed, oversized, uncorrelated, stale or unsupported input; fix the provider. |
| outcomeUnknown | Effect may have occurred without a final response; inspect state before retrying. |

StopReason is idle, disabled, permissionRevoked, resourceExceeded, hostStopping or
updated. These values do not implement process supervision or guarantee termination.

The public `MessageAddonStorageClient` uses the existing storage schema 1 and negotiated `.v1_1` storage profile on protocol 1.1 or cumulative 1.2. Its injected channel supplies physical connection/receipt guarantees that are not encoded in the response bytes. See the [client contract](storage.md#concrete-sdk-message-client); native bootstrap remains separate.

## Dedicated service invocation messages

`ServiceInvocationRequest`, `ServiceInvocationReply` and `ServiceProviderFrame` use schema1 through `ServiceFrameCodec` and the descriptive `.v1_3` profile. They carry bounded consumer invocation, completed/refused/outcomeUnknown result and provider invocation shapes. Requests reference a grant ID; they do not assert owner, partition, provider selection or session authority. The internal runtime can now select cumulative 1.3 for the complete canonical assembly and still defaults to 1.0. Incomplete assemblies retain their earlier selection. A codec/profile does not enable host service support.

Raw bodies are capped at196608bytes before Foundation decode, decoded payloads at65536bytes and nonempty refusal reasons at4096 UTF-8 bytes without truncation. Full slash-escaped base64 payloads fit the dedicated bound; generic AddonEvent remains capped at131072bytes. Larger Unicode/whitespace spellings are refused. This is a byte-format bound, not allocator/RSS or outer double-base64 qualification.

After decoding, the consumer **must call `reply.validate(matching: request)` before exposing or projecting a result**. This checks every outer correlation field and the nested completed response. Constructor/codec validation alone does not reject an individually valid but contradictory outer/nested identity. The SDK lifecycle sees only the projected InvocationCompletion and cannot restore discarded outer fields. Peer authority, exact receipt disposal and physical generation checks remain separate. Refused(outcomeUnknown) is invalid; uncertainty has its own result. Refusal does not establish SDK request-side non-exposure or erase an earlier retained logical request.

[Reviewed syntax delivery](../superpowers/verification/2026-09-18-addon-service-invocation-frames.md) records its original 990-test/90-suite boundary. The later [internal host and SDK exchange](../superpowers/verification/2026-09-18-addon-service-invocation-host.md) adds the four message legs, exact receipts and common generation composition. The cumulative1.4 composition adds the complete public client and subscription controls/events; native transport remains separate. The [host and whole-SDK record](../superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md) records the reviewed internal delivery and its limits.

<a id="dormant-service-control-and-source-syntax"></a>

## Service control and source messages

`ServiceControlRequest`, `ServiceControlReply`, `ServiceSourceStartFrame` and `ServiceSourceOutputFrame` use schema1 through the separate `ServiceSubscriptionFrameCodec` and descriptive `.v1_4` profile. Cumulative runtime1.4 is selected only for the complete canonical handler/adapter/environment/prepaid-capacity assembly, including storage, assets and invocation. The `.v1_4` syntax profile alone enables no runtime authority; defaults and legacy1.0–1.3 remain preserved.

Control requests are acquire, subscribe or unsubscribe with exact case fields. Acquire carries only OperationRequest.requestService. Replies explicitly distinguish admission and terminal phases: only acquire/accepted is an admission acknowledgment, without a grant; terminal acquired/subscribed/acknowledged is kind-specific. Refused/outcomeUnknown are separate terminal results; refused(outcomeUnknown) is invalid. Full request matching checks correlation and acquired scope, without treating a requirement binding name as the service ID or authenticating copied grants. The composed host commits cold acquisition intent before launch exposure; exact admission receipt and current readiness/authority precede terminal Grant handoff. Admission acceptance is not readiness. Grant refresh retains the original interest deadline. Full lifecycle ordering and current authority remain host responsibilities.

Source starts carry the host-issued descriptor, sourceID and startNonce. Source output is startupCompleted or sourceUpdate; matching checks exact source/nonce and update contract/operation. The composed host checks persistent current-provider incarnation/token/startNonce, exact canonical source binding and publication sequence, including after startup-job retirement. A source UUID and successful decode do not prove provider incarnation, readiness or current source authority. Dedicated ServiceEvent decoding also checks the strict nested generation shape; the baseline generic event codec is unchanged.

Bodies remain bounded at196608 bytes before Foundation decode, response payloads at65536 bytes and refusal reasons at4096 original UTF-8 bytes. Publisher/digest/partition bounds are256/512/256 original UTF-8 bytes. The full escaped64KiB source/event fixtures fit this dedicated bound; generic AddonEvent retains its128KiB limit. These are wire-format bounds, not allocator, envelope or native guarantees. [Historical syntax evidence](../superpowers/verification/2026-09-18-addon-service-subscription-frames.md). See the [host and whole-SDK delivery reference](../superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md) and [service lifetimes and exact receipts](services.md#service-controls-sources-and-latest-events). The injected client does not qualify native adapter/bootstrap, C0d or macOS14/Intel execution.
