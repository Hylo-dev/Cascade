# Asset transfer: design decision before compressed ingress

Status updated 2026-09-14: the user resolved the architectural choice in [Scegliere il trasferimento delle immagini tra addon e host](../../../.scratch/cascade-product/issues/21-asset-transfer.md). The host/SDK prerequisite is delivered. The text below is the original 2026-09-13 analysis of alternatives, preserved as decision evidence; its open-choice wording is historical. No asset-transfer code or C0d gate change is delivered by this document.

**Decision:** selecting the asset-transfer ownership mechanism is an architectural choice still open in the inspected sources. The high-level policy is already settled: keep images up to1MiB compressed/1,000,000 pixels and transfer assets separately from ordinary envelopes, whose total remains512KiB. The open choice is bounded multi-message assembly versus a separate native bulk-buffer capability. It changes the wire state machine, credit accounting and the lifetime of untrusted memory; it is not simply a choice of encoder or chunk size.

**Recommendation:** bounded chunk assembly using the existing Foundation codec stack. It reuses the established message/credit path and can be implemented/tested as a host primitive without selecting another native IPC resource type. It does not qualify a production native transport or solve C0d.

## What existing decisions actually establish

- `docs/superpowers/specs/2026-09-09-addon-runtime-design.md:318,329` and `plans/2026-09-09-addon-runtime-01-contracts.md:67` explicitly keep512KiB total envelopes and require a separate bounded asset transfer; the latter must not raise document/envelope limits.
- `CascadeAddonSDK/AddonAssetClient.swift` already exposes complete Data import plus share/release. `docs/addons/assets.md:67–94` fixes the PNG/JPEG profile and existing ImageIO/CoreGraphics decoder; compressed transport/assembly remains open (:208). The provider must never supply a path or privacy partition.
- `AddonRuntimeTransport.swift` is a bounded synchronous adapter boundary with no production conformer. Package.swift contains no adopted bulk-transfer package or CascadeTransport target. Foundation JSON/Data is already used by C6; ImageIO/CoreGraphics are the selected image libraries. SwiftData is the durable host archive, not an adopted ephemeral asset channel.
- `Prototypes/AddonPlatform/Shared/ProbeMessage.swift` and the platform probe use Foundation XPC for bounded request/reply experimentation. They do not implement an asset bulk-buffer contract or choose its ownership model. Owner-bootstrap evidence and the still-closed managed-death gate do not qualify new shared-memory/descriptor semantics.

No inspected adopted library or native boundary already selects the missing mechanism. Reusing Foundation for messages and ImageIO for images complies with the library-reuse direction; the addon-specific authority/credit state is application protocol logic, not a new image codec. Adding a networking/streaming library would not supply Cascade's canonical publication authority or quota lifetime.

## Two compatible options

### A. Bounded chunk assembly over the existing credited message path — recommended

Use a separate negotiated asset vocabulary with begin/chunk/finish/abort and bounded receipts. A concrete initial shape is64KiB raw chunks, at most16 data chunks for1MiB, contiguous offsets with no overlap/reorder/retransmit cache, plus begin/finish controls. Foundation encodes the chunk bytes; the ordinary total-envelope512KiB check still applies. The existing C6 worst-case base64/escaping arithmetic leaves room under192KiB for a64KiB raw chunk plus bounded metadata, but the exact new DTO/wrapper byte proof must be supplied in its implementation brief. This is not repeated base64 inside publication snapshots.

**Identity:** begin resolves the canonical RuntimeConnection and current host publication assignment, publisher/addon/digest and immutable privacy partition. The host mints the transfer token, binds it to that incarnation/connection/publication and declared total length, and rechecks all of it on each message and before import commit. No owner/path/partition from payload becomes authority. Exact ordered chunk progression is independent of publication/storage sequences; old tokens cannot resume after reconnect.

**Credits:** one pending asset transfer per active incarnation, subject to the existing active-provider/global quotas; no installed-owner preallocation or waiter queue. Each chunk uses the existing one shared ingress credit and an exact typed receipt credit. Receiving16 chunks does not authorize retaining16 raw frames: copy the current chunk into the admitted assembly, release that frame, then grant the next credit. No new provider job exemption or limit increase is implied. Abort, disconnect, expiry or revocation closes only the exact transfer. A finite nonrenewable host monotonic deadline must be specified in the implementation brief and serviced by existing deadline machinery, not a timer/task per chunk. Do not hold the runtime's global active operation while merely waiting for the next frame.

**Memory/lifetime:** BEFORE granting begin acceptance, prepay the whole declared assembly length (<=1MiB), fixed transfer metadata and any controlled allocation overlap. The assembly needs protected lifetime across separate message invocations, revocation and final decode; a scope that ends after each chunk or a process quote refunded at observeExit is insufficient. Reuse the governor's protected-secret pattern with the correct temporary-memory dimensions; do not mischarge compressed bytes as a live raster merely to reuse its token. Quote bounded per-frame parse/copy workspace separately and release it after each frame. At finish, keep assembled input charged while the existing decoder's10,162,688-byte allowance and the eventual raster reservation coexist. Decoded pixels retain the current real-CGImage lifetime; dropping an assembly or receipt never refunds live pixels.

**Disk:** none for transfer staging. The existing later archive persistence remains independently quota-controlled. No temporary-file namespace, orphan-file scan or new disk exemption.

**Tradeoff:** up to16 acknowledged data transfers and an explicit bounded assembly state add latency/control logic. The host owns the assembled snapshot, can validate exact completeness, and uses the existing message boundary. No new shared-memory/file-descriptor API needs to be selected to test this pure path.

### B. Separately qualified native immutable bulk-buffer capability

Keep small begin/receipt/result control envelopes, but transport compressed bytes in a separately admitted native memory object/region identified by a host-issued transfer capability. The1MiB bulk object is not a1MiB JSON/Data envelope renamed to evade512KiB. This proposal does not select or claim a particular Apple API's macOS14 behavior, zero-copy operation, immutability or sandbox rights: those properties need a separate public-API qualification design before implementation.

**Identity/credits:** use the same canonical publication/privacy/incarnation binding as A. Limit to one bulk object per active incarnation with explicit host grant before creation/acceptance, one receipt and no arbitrary provider pathname or descriptor adoption. Closing a connection or receiving an ack is not proof that another process released its mappings or writable access.

**Memory/lifetime:** prepay the maximum permitted region and fixed mapping/capability metadata before granting it, including simultaneous provider/transport references and any host-owned snapshot copy. The host must obtain immutable bytes before calling the existing complete-Data decoder; provider cooperation or an advertised read-only handle alone is not sufficient. If immutable transfer cannot be established, take a separately prepaid bounded private snapshot and validate it; do not advertise zero-copy. A protected reservation follows the actual final mapping/reference/worker use, independently of provider exit and logical transfer cancellation. Existing decoder and raster charges remain separate and unchanged.

**Disk:** the proposed option is memory-backed, with no file staging. A fallback to files would introduce a new persistent temporary namespace, strict prepayment and crash/orphan reconciliation; that is an additional design, not an uncharged implementation detail of this option.

**Tradeoff:** may reduce chunk round trips/copies, but that benefit is unmeasured. It adds a native capability/immutability/cleanup boundary not present in the adopted host primitives. C0d remains closed; this option cannot be called production-ready or used to bypass its existing gate. It is appropriate only if a separately authorized qualification shows a concrete need/benefit over A.

## Decision boundary and next evidence

The existing user-approved limits, SDK signatures, privacy rules, image libraries and raster lifetimes do not need another decision. The architectural question is specifically whether to add native bulk-capability ownership or keep compressed assembly inside the already credited message model. Recommend A; exact DTO fields/chunk proof/deadline, protected assembly token and final admitted-import helper are subsequent finite implementation design, not new codec work.

After a selection, require real1MiB assembly/import and malformed/truncated/gapped/stale transfer tests, quota denial before allocation/credit, concurrent legacy traffic, exact cancellation/expiry/exit cleanup, and retained pixels/receipt behavior with the common governor. Native flooding/allocation and decoder-process qualification remain separately unproven. No action or user question is requested by this artifact.


Independent decision-artifact review approved the source basis and bounded recommendation without selecting the architecture for the user. Review: `/private/tmp/cascade-asset-transfer-design-review.md`. The choice has since been presented and resolved in the linked ticket. Implementation must follow the selected mechanism and the standing weekly limit; this historical proposal is not evidence that transfer code exists.
