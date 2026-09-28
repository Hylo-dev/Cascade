# Concrete SDK client for keyed-storage messages

The approved storage/SDK work and the user’s sustained Codex-only continuation authorize this bounded increment. The 35% reserve is waived. [Accepted design investigation](../../../.scratch/codex-addon/20260918-continuation/storage-client-design.md) contains the complete ordering requirements and finite acceptance matrix.

## Scope

Add exactly four files: SDK Storage/AddonStorageMessageChannel.swift and MessageAddonStorageClient.swift; PresentationTests/MessageAddonStorageClientTests.swift; RuntimeTests/MessageAddonStorageIntegrationTests.swift. Reuse StorageRequestLifecycle, Contracts, Runtime handlers and existing package targets unchanged. No native adapter, public Runtime exposure, protocol bump, launcher or C0d change. Root owns documentation, review and delivery.

The concrete client implements existing read/write/remove and adds close on its concrete type. Its injected Sendable byte channel exposes immutable generation/profile, an exchange result of response(Data) or proven request-side rejectedBeforeHandoff, and idempotent asynchronous physical close/drain. The channel is trusted, connection-bound infrastructure; it must match the physical generation/sequence and consume the exact host response receipt before returning bounded bytes. The SDK cannot independently authenticate proof absent from those bytes.

Request-side rejection means no exposure to host request processing/backend execution and disposed staging. Never infer it from cancellation, an exception, response handoff rejection or suppressed output. A backend acknowledgment with refused reply remains a committed mutation with undeliverable reply; unresolved SDK mutations are unknown, not proven refused.

## Serialization and lifetime

One lock protects the unchanged scalar lifecycle, a separate whole-operation busy slot, local terminal completion and permanent authority closure. Admission precedes request construction/encoding; no queue retains waiting keys or values. The slot remains occupied after lifecycle.consume clears pending, through response interpretation, final authority decision and any physical drain. No lock is held across await or reentrant channel work.

Cancellation records the lifecycle’s first local outcome without abandoning exchange. Before handoff it prevents sending; after possible mutation handoff it remains unknown even if a discarded response later arrives. Response consumption before cancellation preserves the known response. Explicit close and final result delivery share one lock ordering: close winning after validation returns sessionRevoked after drain, rather than delivering bytes/acknowledgment with revoked authority. Finalization winning first preserves that completed result. All callers share one cancellation-independent close task; no early return before required drain, no close/exchange dependency cycle and no second physical close.

Malformed/mismatched replies, profile/generation drift and generic exchange failure poison the client. Valid exact host failure responses preserve their bounded code/reason and leave the healthy channel usable. Missing read versus present empty Data remains distinct. No retries, normalization, batch API, new storage classes, archive or checkpoint behavior.

## Bounds and versions

Use existing schema1 and storage profile v1_1 under negotiated protocol1.1 or cumulative1.2. Default1.0 remains unsupported before encoding/exchange. Keep all existing caps: keys1–256 UTF-8 bytes without NUL, values<=64KiB, frames<=192KiB, failure reasons<=4096bytes, existing envelope and backend quotas.

Logical client admission is not a memory reservation. The embedding must admit input, encoding/decoding and returned-value lifetimes before constructing/encoding requests; argument Data can retain larger backing than its visible count. In real-runtime tests establish a protected outer SDK memory scope before inputs/client/operations, separate from the runtime and backend’s existing scopes. The conservative8MiB test allowance is not a measured Foundation heap formula. Keep result Data inside its paid scope; return only scalar observations. A channel drain cannot release caller-owned Data. Production native allocation/RSS qualification remains open.

## Verification

Capture exact new-file absence; preserve dirty checkout without Git mutation/worktrees. Meaningful compiling RED then focused GREEN with retained logs/hashes; use deterministic gates rather than sleeps. Test all read/write/remove cancellation and close orderings, healthy host refusals versus poisoned transport, exact request rejection, max/control/Unicode keys and values, wrong correlation, raw frame bounds, shared drain and post-validation close.

The integration bridge must drive actual canonical Runtime storage ingress, real coordinator/keyed backend and exact response receipts, with a strongly owned coordinator. Cover successful durable operations, missing/empty, full values, shared-slot overlap, wrong/duplicate/foreign receipts, actual backend commit followed by reply rejection, cancellation/close and protected-scope retention. Modeled observeExit is a labeled test input, never proof of physical exit. Do not race existing unsynchronized adapter dictionaries; serialize access or use a private bounded synchronized adapter in the new file.

Run new SDK/integration suites and necessary adjacent lifecycle/frame/negotiation/backend/asset checks serially. Root then performs independent review, full package verification, refreshed independent source-example builds against the augmented public SDK, signed app build/link and normal restart. Existing source examples remain verified against their pinned62-input SDK baseline until that refresh; their workers do not own this SDK delta.

The increment does not finish broad C5, Clock adoption, native IPC, authenticated bootstrap, app composition, hostile parser/RSS qualification, macOS14/Intel qualification or native SDK parity. C0d remains exit78.

## Delivery

Implemented and independently reviewed: [955 tests / 87 suites, refreshed examples and signed delivery](../verification/2026-09-18-addon-storage-message-client.md). Optional P3 matrix gaps remain explicitly recorded; no claim of exhaustive combinations or native qualification.
