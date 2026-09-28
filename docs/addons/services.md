# Host service broker (C3 continuation)

`CascadeRuntime.ServiceBroker` implements bounded host policy and orchestration decisions. It imports only
`CascadeContracts`. It does not launch addon workers, load addon code, implement transport SDK clients, or
prove execution/termination of a provider. C3 remains partial until qualified C1 and C2 composition and
real-provider tests exist.

## Authority and binding

The trusted host supplies `HostServicePermission` to `authorize`. That input includes a verified consumer,
resolver-selected `ServiceBinding`, service ID, explicit account/privacy partition and allowed operation.
The partition is host state, never a field that an addon may assert. Cross-publisher selection additionally
requires resolver consent; same-publisher callers still need the same explicit host permission.

A binding key includes verified consumer, requirement, feature and operation. A second authorization for
that key is rejected until the original permission is explicitly revoked. Provider identity, digest, exact
semantic version including build metadata, service, partition, feature and operation form source identity.
Different features are conservatively treated as incompatible scopes, even if their versions match.
The broker never reruns the resolver or silently changes a provider. Resolver acceptance and authenticity
of registration inputs are host responsibilities, not security properties established by this actor.

`registerSession` creates an opaque `ServiceSession` and a fresh connection generation from a verified
identity supplied by the transport authority. `acquire(session:requirementID:scope:now:lifetime:)` is the
host boundary for `OperationRequest.requestService`. It returns a canonical wire `Grant`, an interest ID,
a source ID and, for a new source, one start decision. The existing SDK interfaces remain unchanged.
The internal runtime maps the message controls to this host API; the public SDK client uses an injected channel. A production native transport adapter remains separate.

Every invocation receives the canonical grant **ID** and the authenticated session handle. A copied grant's
owner, generation, scope, expiry and cost fields are never consulted. Validation checks the canonical
session/generation, verified consumer, permission, immutable feature binding, source identity, operation,
contract and monotonic deadline. `beginInvocation` retains the exact canonical invocation and its selected
binding in a bounded logical-request history. `completeInvocation` rechecks canonical authority and the
response operation/contract, then synchronously records a terminal result before awaiting any capacity refund.
Refunding unused bytes never requires another resource admission and cannot change that accepted terminal outcome.
Revoked late results are rejected. Responses are a trusted host-adapter input, not an unauthenticated
provider entry point.

Logical request identity is `(verified consumer, ServiceInvocation.requestID)`, independently of sessions
and grant IDs. A second `beginInvocation` for any retained ID fails closed with `invalidPayload` and emits
no new work, whether the original is pending, completed, unknown or unsent. Changed payload, deadline,
feature, selected provider/version/digest, operation, requirement or partition also cannot replace it.
The returned immutable `ServiceWork` contains the exact admitted invocation for the trusted adapter.

`requestOutcome(session:grantID:requestID:now:)` is the recovery API. A fresh currently authorized grant must
match the original canonical requirement and source binding before any saved state/result is disclosed.
It returns `pending`, `dispatched`, `completed(response)`, `unknown` or `unsent`, or nil when no retained
history exists. Disconnect, revoke, disable and timeout turn dispatched work into `unknown` and queued
work into `unsent`; they never automatically retry either outcome. Terminal late responses cannot change
these outcomes. Completed results remain recoverable after reconnect only with matching fresh authority. Recovery that finalizes an
elapsed operation refunds its unused result capacity immediately. After the new governor await, `requestOutcome`
revalidates the canonical session/grant, full original requirement/source binding, history existence and original TTL
before returning any saved outcome. It never writes a captured record back after suspension.

History lasts ten monotonic minutes from initial admission and survives reconnect and disable. New work
requires a finite positive wire deadline interval no greater than 30 seconds; grant/interest lifetimes
retain their independent one-hour ceiling. Under ordinary clock progression, the original wire command
is already expired when its history can be removed. Existing command deadlines and history horizons remain
monotonic across civil-clock adjustments, while fresh request IDs can still be admitted after a rollback.
Deduplication is explicitly bounded to retained history: there is no indefinite logical-ID guarantee after
that horizon, nor across whole-host restart. C1 remains responsible for rejecting stale session envelopes.
No sticky civil-clock lower bound is imposed.

## Interests, sources and expiry

Compatible consumer interests share one source entry and one metadata charge. First acquisition returns
`startSource`; releasing the last interest returns `stopSource`. Normal `disconnect` invalidates grants and
outstanding work but retains bounded, unexpired host interests. `sourceChanged` returns at most one pending
`wakeConsumer` decision per absent verified consumer. Repeated changes coalesce until reconnection.
No event payload/cache is retained in the broker: the composed runtime owns the paid latest-state cache and delivery described below. Native C2 qualification remains separate.
Reconnect issues fresh grants/generations and can reuse the original interest until its original expiry.

Admission anchors the wire date once to `RuntimeInstant.monotonic`. Later civil-clock shifts do not alter
existing grant, interest or invocation deadlines. `nextDeadline()` supplies the minimum to the host's
shared deadline queue; the coordinator must call `expire(now:)` when due and process its stop decisions.
There are no per-addon tasks, polling loops or timers. Expired interests are not renewed in place;
after expiry drainage, a fresh authorized acquisition may create a new source.

`revoke(permissionID:)`, feature `disable`, `disableAddon` and `providerUnavailable` remove affected
active canonical authority synchronously before awaiting resource cleanup; request-history tombstones and
completed results retain their original horizon. Addon disable covers its consumer role,
its provider role and its connected session. Provider loss returns the exact affected features, allowing
system-event-driven resolver reevaluation while independent features remain usable. Installation and
restoration reevaluation use the resolver's dependency graph outside this broker; restoration requires a
new host-authorized binding. Existing permissions never revive automatically after disable/revocation.

## Executing decisions

Returned decisions are revocable snapshots, not enduring authority to execute. Immediately before
submitting work, a trusted coordinator calls `consumeSourceStart` or `consumeInvocation`. The calls check
canonical existence/deadlines and consume the decision once; a revoked/expired/replayed decision is denied.
Source consumption returns the verified descriptor needed by a host adapter. A fresh source always gets
a new UUID; `sourceChanged` for a removed source cannot wake consumers of a replacement source.

The coordinator must serialize decision consumption, actual transport submission and incoming lifecycle
revocation events. Consumption is not an atomic transaction with a native process launch: if it enqueues
a consumed decision elsewhere and delays execution, it must revalidate/cancel in that queue. C1/C2 must
authenticate provider sessions/generations, verify readiness, and reject stale source-event payloads before
calling the trusted broker boundary. The broker does not claim physical cancellation of an already
submitted invocation. Late responses still fail canonical validation after revoke, disconnect or expiry.

`shutdown()` represents whole-host shutdown: it returns source-stop decisions, discards in-memory request
history and releases broker-owned metadata. It does **not** release
outstanding process admissions, which remain charged until confirmed exit.

## Limits and resource accounting

All limits can be tightened by host tests, not raised above these ceilings:

| Retained collection/input | Hard ceiling |
| --- | --- |
| Sessions | 32 |
| Permissions and binding index | 256 each |
| Interests | 256 |
| Sources | 128 |
| Grants | 64 per addon owner, 1,024 globally |
| Outstanding invocations | 128 |
| Logical request history | 128 per addon owner, 1,024 globally, retained for ten monotonic minutes |
| Pending wake identities | At most one per interested identity, bounded by 256 interests |
| Path admissions | 16 records; at most 8 unique addon identities in an input path |
| Publisher / trusted partition | 256 UTF-8 bytes each |
| Digest | 512 UTF-8 bytes |
| Service, requirement, feature, operation | 128 ASCII identifier bytes each |
| Canonical semantic version | 128 UTF-8 bytes, parsed roundtrip required |
| Invocation / response payload | 65,536 bytes, enforced by Contracts |
| Grant/interest lifetime | Positive, at most 3,600 seconds |
| New command wire deadline interval | Finite, positive, at most 30 seconds |
| Runtime monotonic input | Nonnegative, at most ten 365-day years in one incarnation |

`ResourceGovernor` charges explicit `.state` reservations of 4,096 bytes per permission, 1,024 per session,
2,048 per shared source, 2,048 per interest, 1,024 per grant, and 8,192 plus canonical input bytes plus a
65,536-byte maximum-response reserve per logical request. Each reservation also incurs the governor's own
1,024-byte bookkeeping charge. Pending/dispatched requests keep that complete pre-dispatch reservation, including
when shared capacity is full. Once a terminal outcome is committed, the same reservation is reduced to canonical
input bytes +8,192 bytes of request/binding/response/queue metadata +actual retained result payload. Unknown/unsent
records retain zero result bytes; completed records keep their exact bounded response and original ten-minute TTL.
No history entry, request identity or saved result is evicted to reclaim space, and duplicate admission stays denied.

`ResourceGovernor.reduceStateReservation(_:owner:toBytes:)` atomically reduces only an existing `.state` reservation.
The target excludes the original 1,024-byte governor metadata, which remains charged even for zero payload. The
canonical ID/owner stay unchanged. Validation and owner/global/entry charge updates occur in one actor turn with
no release/readmit interval, so reduction works at full capacity. Wrong-owner, missing/released, non-state, negative
or growing targets return false without mutation; repeated same-size reduction succeeds. Later release subtracts
only the remaining canonical charge. Jobs, assets, disks, process slots and process memory are unaffected.

Each retained request has one pending-refund flag within its existing metadata allowance. Existing completion,
recovery, invalidation and expiry events drain these bounded flags; no independent queue, task, timer or polling loop
is introduced. Terminal state is committed synchronously before governor awaits. An already removed/released record
cannot be resurrected by a late refund; a false reduction result is an explicit safe no-op that may leave conservative
capacity charged, not a failed command outcome. Expiry and shutdown release the remaining canonical reservation and
remove its pending metadata with the history record. Native process/path reservations remain until observed exit.

The shared 8-MiB budget may still deny history admission before request-count ceilings. `nextDeadline` includes
history expiry and `expire` releases those exact reservations. These are retained-data budgets, not native footprint
observations. Failed partial admissions roll back their exact reservations; revocation never calls `releaseAll(owner)`
across unrelated subsystems. Unexpected canonical-release failures are logged rather than silently discarded.
A bounded admission gate gives concurrent attempts `resourceDenied` instead of creating an unbounded queue.
Revision checks across governor awaits prevent source duplication and revoked-state resurrection.

`admitPath` accepts a complete, host-resolved provider path, reserves all provider charges before returning
any work authorization, or rolls the entire path back with `resourceDenied`. Each `.provider` reservation
charges a process slot and 64 MiB through the governor (currently three provider slots globally). No job
permit is held while waiting for downstream admission. `releasePathAfterExit` releases only that path's
canonical reservations, and must only be called when its workers have actually exited. Already running
processes and overlapping paths need coordinator composition; a duplicate provider budget is conservatively
denied here. A source metadata admission alone does not admit physical provider execution: the coordinator
must arrange the required process/path admission before submitting a source start or invocation.

## Evidence and remaining qualification

Focused Swift Testing suites cover canonical ownership/theft, wrong operation, previous generation,
monotonic expiry across wall changes, shared first/last release, partitions and per-feature versions,
wake coalescing, outstanding-result revocation, independent-feature preservation, provider disable,
resource rollback, 64-grant owner ceiling, concurrent source creation, whole-path rejection and canonical
decision consumption. Request-history regressions additionally cover identical/conflicting retransmission,
completion/reconnect/disable recovery, bounded pressure and cleanup, maximum result retention at a full
budget, atomic shrink at full capacity, small-result refunds without replay/TTL changes, all unknown/unsent terminal
paths, unrelated process/job/state preservation and concurrent completion/expiry/shutdown cleanup. These prove pure
host rules and bounded decisions. The exact suspension-point interleaving of recovery refund and revocation remains
a code-review obligation: the real governor exposes no deterministic blocking seam, and tests add no fake governor,
sleeps or production-only hooks. Revocation before/after recovery and general concurrent cleanup are exercised.

The `shared-services` qualification record is not satisfied by these tests alone. Qualified C1/C2 transport
composition, two real providers, observed one-source execution/stopping, account-separated latest caches,
and real-process dependency-chain behavior remain outstanding. No native transport/storage client was
invented as part of this continuation.

## SDK invocation lifecycle

The internal `ServiceInvocationLifecycle` keeps one pending invocation in a caller-owned serialization domain. It retains only bounded correlation metadata, not payload or response buffers. Tickets bind the local issuer and attempt to the service-domain generation, request ID and grant ID. This is neither peer authentication nor a replacement for the broker’s canonical authorization and bounded request history.

Before possible handoff, cancellation retires the local request as cancelled. Once exposure is possible, cancellation or close reports outcomeUnknown for every operation, including one named read. The SDK has no general promise that a service operation is pure or idempotent. A canonically completed response can arrive before the transport acceptance observation; after local cancellation, the exact late result is discarded without replacing that earlier uncertainty. The host may independently retain a known result.

For response consumption, only an exact, validated service completion can retire pending work; proven prehandoff rejection can retire it without a response. Wrong generation, request, contract, operation or completion kind leaves current work occupied. A proven request-side prehandoff rejection is distinct from a generic exception or rejected reply. Closing the ledger is permanent logical revocation; it does not drain physical buffers, free their reservations, roll back host work or retry the invocation. The invocation executor supplies whole-operation ownership and atomic final delivery versus close. The cumulative1.4 client below adds controls and subscriptions under one connection arbiter, without changing this invocation ledger.

The integration tests use actual runtime resolution, service acquisition, broker dispatch and provider completion ingress. The relay of canonical saved results into the ledger is private test infrastructure, not a new consumer wire protocol. Those lifecycle-only fixtures retain distinct service and publication generations. The later canonically negotiated1.3 message path described below composes fresh sessions with a common generation; neither path rewrites issued grants. Input/response lifetimes stay in preadmitted scopes separately from host work and process accounting. Modeled process-exit input does not prove actual native termination.

The public `TransportServiceClient` implements all three `AddonServiceClient` methods together over an injected channel. Acquisition is internal context-assembly plumbing; production bootstrap remains separate. The historical invocation-only increment did not expose an incomplete public client.

[Reviewed delivery and finite evidence](../superpowers/verification/2026-09-18-addon-service-invocation-lifecycle.md): 978 tests / 89 suites, signed build and verified restart.

## Dedicated invocation frame contracts

The [dedicated invocation messages](protocol.md#dedicated-service-invocation-messages) supply bounded request/reply/provider bodies. Entire-reply `validate(matching:)` is mandatory before result projection; codec success alone is not correlation or authorization.

## Internal invocation message exchange

The host now connects consumer request, provider invocation, original raw completion-only ProviderOutput and consumer reply. Both peers must canonically negotiate the complete cumulative service1.3 assembly for invocation; control/source/event paths additionally require the complete1.4 assembly. A copied grant or selected syntax profile cannot create authority. Dedicated raw bodies are limited to192KiB and decoded payloads to64KiB; generic AddonEvent retains its128KiB limit. Staging, codec workspace and retained/caller buffers require their own admitted overlapping lifetimes. Wire limits do not establish allocator or RSS bounds.

One paid route per incarnation reserves consumer reply and provider invocation capacity before retaining broker work. Self/dependency-slot cycles are refused before dispatch. Short host admission is released while awaiting provider completion. Routes retain scalar correlation metadata and use canonical broker history; they do not create another response cache or payload queue. Exact receipts dispose only their accepted payload, independently from command/job completion and process exit. Rejected reservations never synthesize accepted receipts.

Result disclosure checks current grant, connection, authority and deadline after suspended preparation and immediately before handoff. Completion, close and cleanup events are coalesced by the outer drain owner and revisited after its guards release. A retained failed asset refund is attempted once per cycle; a newly queued refund receives its first attempt. No polling or per-route task is added. Losing authority suppresses known history while physical ownership is settled; stopped process charges remain until separately observed exit.

A refused invocation means this exchange caused no new dispatch, not that an earlier retained logical request never executed. It is not trusted proof that request handoff never happened. A committed command with rejected reply can be known to the host and unknown to the caller. Uncertainty has its own result and causes no implicit retry.

The internal SDK executor owns one whole operation through validation, result arbitration and required physical drain. It checks the full ServiceInvocationReply against the request before projecting a completion into the unchanged lifecycle ledger. Cancellation before possible handoff sends nothing; after exposure it is unknown for every operation. A consumed result can win before late cancellation, while explicit close competes with final delivery in the same serialization domain. Required drain is shared and independent of caller cancellation.

The original invocation increment supplied internal invocation only; the cumulative1.4 composition adds real controls/subscriptions/events and the complete public client below. Native transport, peer authentication and process qualification remain separate. The route ceiling32 is statically guarded under the actual process cap3. Tests use canonical host/governor paths with modeled adapters and exit inputs, not real native addon death. [Finite tests, review findings and delivery status](../superpowers/verification/2026-09-18-addon-service-invocation-host.md).

## Service controls, sources and latest events

Cumulative1.4 connects the separate [control/source/event messages](protocol.md#service-control-and-source-messages) only when the complete handler, subscription adapter, cumulative storage/assets/invocation support, compatible environment and prepaid maximum capacities are present. Defaults remain1.0 and legacy1.0–1.3 behavior is preserved; a syntax profile or public offer cannot activate a handler.

Cold acquire commits canonical intent before launch exposure. Its admission `accepted` acknowledgment contains no Grant and does not mean readiness. Exact acknowledgment receipt, current source readiness and current authority across the entire provider path precede terminal `acquired` delivery. Launch/timeout uncertainty does not release accepted physical process/job charges or imply automatic replay. Explicit recovery and grant refresh preserve the original interest deadline; they do not renew the interest.

Subscribe binds an existing canonical Grant without launching or renewing a source. Repeat subscription confirms the same current connection alias and updates its delivery-grant association. Aliases deliver only the latest state, with no event history or payload queue. Unsubscribe withdraws the whole canonical interest and all its Grants, invalidates pending invocations and executes source-stop decisions when appropriate. Acknowledgment does not prove process exit. Normal disconnect retains bounded unexpired interests; reconnect uses fresh canonical generations, Grants and confirmed aliases, without adopting old alias IDs.

Source authority persists after the finite startup job retires. Source output must match the authenticated current provider incarnation/token, sourceID, startNonce, exact canonical source key, contract/operation and canonical publication sequence. A decoded frame or matching UUID cannot establish readiness or authority. Latest state is paid per exact source key, including trusted partition, selected provider/version/build/digest and feature/operation. Replacement overlap must be admitted before retention; denial preserves the old state. Current broker and connection authority is checked after suspension and immediately before disclosure.

Invocation and controls share one sequence/admission domain and physical delivery slot. Replies have priority; after terminal retirement, one owed event precedes the next operation's effects. Behind an accepted event, a request parks only its already-paid original raw ingress handle, with no broker work or second request buffer, and resumes on that event's exact receipt. Phase/kind/correlation-specific receipts retire only their accepted payload; startup completion, logical outcomes and process exit retire different ownership. Cleanup uses the existing coalesced outer drain and at most one failed-refund attempt per cycle, with no polling or per-route task/timer.

## Concrete SDK service client

`TransportServiceClient(channel:owner:handleEvent:)` implements `invoke`, `subscribe` and `unsubscribe` together through the injected `AddonServiceMessageChannel`. One immutable connection descriptor, sequence, whole-operation arbiter and shared physical drain cover invocation and controls. Full correlated replies are validated before projection; acquisition admission is consumed internally and cannot masquerade as a terminal response. The host remains permission, Grant, interest, deadline and source authority. Internal acquisition plumbing constructs a fresh `AddonContext` with actual storage/assets and canonical Grants; no public acquire method or new permission/partition/quota policy is introduced.

Event acceptance checks the full Grant, owner, generation and confirmed alias association. An early event may occupy one bounded pending subscribe candidate only with the exact Grant; its alias is installed solely by the independently correlated terminal reply. A same-grant repeat transfers the single already-paid latest value to the new local nonce; a changed Grant suppresses obsolete preparations. Unresolved unsubscribe transfers that alias's existing latest scope: known no-effect refusal or proven rejection before handoff restores/coalesces/pumps it, while acknowledgment, uncertainty or close suppresses it. Unknown unsubscribe quarantines the alias for the remainder of the physical connection and prevents readoption. Active plus quarantined aliases are bounded at64; overflow is refused and acknowledged removal permits capacity reuse.

The embedding prepays raw/codec/returned-value lifetimes, at most one latest event per alias and a running handler. Exact event receipt and physical staging disposal precede reception/callback; user handlers run outside client locks, host admission and synchronous handoff, so they can await invoke/unsubscribe or close. `close()` revokes local state and awaits the shared physical drain, but does not cancel or join already-running user code. Cancellation before possible handoff sends nothing; unresolved cancellation/close after exposure reports `outcomeUnknown` for every method, with no implicit replay. A consumed correlated terminal result can win before late cancellation.

The [host and whole-SDK verification record](../superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md) records the reviewed internal delivery and its limits. The earlier [syntax record](../superpowers/verification/2026-09-18-addon-service-subscription-frames.md) and invocation records remain historical evidence. This injected client and internal composition do not qualify a native adapter/bootstrap, C0d, macOS14/Intel execution or native C3.
