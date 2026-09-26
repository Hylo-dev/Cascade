# Host-owned actions

`ActionAuthorizer` and `ActionDispatcher` are synchronous, Sendable value rules
for a future `AddonRuntime` actor. They do not authenticate a process, launch a
provider, execute callbacks, or prove native command dispatch. The runtime must
obtain installation identity/digest from its verified catalog, Resolution from its
current resolver, and publication/feature binding from its canonical admission
store. A raw `Publication` or `Resolution` received from a provider is not authority.

The actor supplies `ActionAuthorizer.Context` at admission and again at final
`consume`. `featureID` is assigned by the host to that PublicationID; it cannot be
inferred from an action name. Eligibility defaults to unavailable. The host must
explicitly attest current freshness, visibility and privacy availability. Sensitive
content is not inherently forbidden; redacted content cannot authorize an action.
An absent provider is compatible with available host content. An unexpected crash
can make the host context stale/unavailable until a refresh.

Authorization requires an enabled verified installation, accepted/unblocked addon,
enabled/unblocked manifest feature, declared action, exact publication identity
and revision, and exact immutable payload in the current presentation. For a
timeline, only its latest entry at the supplied civil time is current. All current
representations and nested nodes are scanned once; conflicting payloads for one
ID reject the action. Identical repeated payloads are valid. Missing node payload
means empty data. Publication expiry remains a civil-time check. The request's
operational deadline is anchored once by ActionJournal to a monotonic deadline,
with at most 30 seconds of waiting; final consume does not reinterpret it after a
civil-clock adjustment.

`submit` returns admission or the existing journal state for exact recovery. It
rejects request-ID reuse with changed request, publisher, digest or feature.
Recovery uses current installation/feature/eligibility and exact original binding;
it permits a newer current revision or a removed publication without replaying the
original effect. For retained-result recovery, explicit host eligibility authorizes
access to history; it does not assert that the original publication still exists.
New admission and final consume always require the actual current publication. It
does not extend the command or history deadline. History and binding survive a
terminal outcome for ten minutes from first admission, subject to the original
128-request-per-owner ceiling. A still-running old job conservatively occupies
its request ID after history expiry until its exact exit is observed; its expired
outcome is no longer disclosed. This prevents an old exit/result from affecting
fresh history with a reused request ID.

`takeReady` reserves the scheduler's real capacity and returns an opaque,
canonical ticket. It performs no send. `consume` checks that exact ticket once,
revalidates against fresh host state, and marks the journal sent before returning
`Delivery`. The runtime actor must serialize publication/permission changes with
this final consume and mark-sent/handoff; it must not suspend and later send a
stale decision. No caller-created UUID or reconstructed request grants a ticket.
Transport failure after consume is uncertain, even if delivery cannot be proven.
There are no retries or replacement request IDs.

The actual scheduler supplies at most four queued commands and one running job
per addon, with two running jobs globally. This also serializes requests for a
publication. A second intent at revision 1 is rejected before send if revision 2
becomes current while the first command completes. Reserved-but-unsent work can
be cancelled and release its slot because no external execution was started.
Acknowledgement records transport progress, not an outcome. Disconnect, timeout,
disable and stop preserve sent outcomes as unknown and request a stop once.
A stop request never releases real running capacity. Only a validated canonical
completion or exact observed exit does so. Late, malformed, foreign, wrong-
generation and duplicate results cannot replace outcomes or release another job.
Disable revokes tickets before cancelling; re-enable cannot revive old tickets.
`stop` permanently closes admission on that coordinator value.

Both owned components and all coordinator metadata share one host-tightenable
ceiling of 8 MiB. Admission reserves 69,632 bytes plus input in ActionJournal
(including the maximum 65,536-byte result), 8,192 bytes in AddonScheduler and
16,384 bytes for binding/history/decision overhead. The binding charge covers a
publisher limited here to 4 KiB, digest, feature/key, collection overhead and
bounded request/stop projections. No buffers are allocated per installed addon.
New admission fails before storing if the combined charge cannot fit. If enqueue
fails, a canonical single-request journal rollback restores history and charges;
no full-table transactional clones are made. Terminal outcomes reduce the journal
reserve, but the binding remains charged until original expiry. Running job and
binding charges remain after history expiry until actual exit. Returned values
are bounded; the caller must not retain an unbounded history of decisions.

`nextDeadline` combines journal and scheduler deadlines for the host's single
deadline queue. `expire` reports definite unsent expiry and required stops without
polling, sleep, private timers or per-frame sweeps. A stopping job disarms its
operational deadline while retained history still schedules its original expiry.
The value has no owner-wide ResourceGovernor release operation.

Global composition with ResourceGovernor, authoritative actor/session ownership,
publication/permission invalidation routing, transport acknowledgements, and the
qualified native launcher remain integration boundaries. Pure deterministic tests
prove the value transitions and resource accounting, not real process containment,
provider restart, OS compatibility, native delivery, or visible app behavior.
