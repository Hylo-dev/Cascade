# Canonical Publication Restoration Implementation Plan

> **Status: INTERNAL RUNTIME SAVE/RESTORATION IMPLEMENTED AND INDEPENDENTLY APPROVED.** The approved SwiftData/observed-disk design is implemented through B1/B2, with102 covering tests including14 restoration cases. The [concrete storage plan](2026-09-13-addon-swiftdata-storage.md) records exact review evidence. Complete retained-registry composition is independently approved and delivered with 679 serial tests, signed build and verified restart; this document preserves the implemented eligibility and authority contract.

> **For agentic workers after approval:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. The coordinator assigns file ownership and controls verification; do not spawn workers, commit, build or restart independently.

**Goal:** Restore valid canonical publication state without renewing activity lifetimes, replaying notices or manufacturing asset authority.

**Architecture:** SwiftData selected; see the [qualification design](../specs/2026-09-13-addon-swiftdata-archive-design.md). Reuse the existing synchronous PublicationState, AssetState and common ResourceGovernor. The storage-neutral eligibility rules below are established requirements; the candidate and commit boundary must match the eventual durable transaction and identity model.

**Tech Stack:** Swift 6, macOS 14 floor, CascadeContracts, CascadeRuntime, Foundation and Swift Testing. The implemented archive uses the bounded Foundation codec from the linked B1/B2 plan; no new package dependency is introduced.

**Spec:** [C5 completion](2026-09-10-addon-runtime-completion.md), [execution Task 02.5](2026-09-09-addon-runtime-02-execution.md), [runtime design](../specs/2026-09-09-addon-runtime-design.md), [storage contract](../../addons/storage.md), [asset contract](../../addons/assets.md).

## Global constraints

- Production archive and restoration implementation are authorized through the linked storage plan. Native provider qualification remains outside this work; do not claim SDK transport or app bootstrap without implementing and verifying those boundaries.
- Preserve dirty work and capture preimages before any later implementation. No staging, commits, resets, native addon launches or C0d changes. Follow CODE_STYLE.md and compiling behavioral TDD.
- Keep one canonical state owner and the existing common governor. PublicationStore is an actor wrapper over PublicationState, not a separate resource authority; do not inject an independent governor there.
- Existing limits remain: snapshot 64 KiB, depth 8, 128 nodes, string 4 KiB; timeline 32 entries and 256 KiB; retained state 8 MiB; 16 active publications per addon; 16 activities globally and 4 per addon. Terminal history retains its existing 1,024-byte record charge.
- The 512 KiB transport envelope and 64 KiB checkpoint are unchanged. A future host restoration batch need not be a wire envelope; its explicit record, byte and temporary-work bounds must be specified with archive admission.
- No public SDK restore endpoint, executable operation container, replay of provider sequence/generation or serialized permission grant belongs in restoration metadata.

## Storage-neutral eligibility rules

1. **Canonical content:** Capture the complete stored Publication and all timeline entries, revision, kind and original host sessionDeadline. `snapshot(at:)` is a presentation projection and is not an export primitive. Use canonical record traversal; avoid an unbounded second array.
2. **Original lifetime:** Activity restoration preserves its original absolute civil sessionDeadline. Ordinary `accept` is unsuitable for fresh restored records because it calculates `now + 8h`. A later higher-revision update must still end at the original deadline.
3. **Terminal history:** Explicit end and elapsed expiry remain terminal. Dropping content must preserve the revision/kind/session deadline necessary to reject revival of that session. Do not silently overwrite current live or terminal authority with an archive record.
4. **No replay:** Notices are omitted from capture and may never become live restored content. Commands, completions, checkpoints and action effects are not restoration records. The eventual decoder must reject or explicitly discard prohibited record kinds before admission.
5. **Structural eligibility:** Validate supported semantic/schema version, finite dates, owner, publication ID/revision/kind consistency, normal content constraints and canonical expiry no later than the original session deadline. A plausible but forged timestamp is not detectable through structure alone; archive provenance/integrity remains necessary.
6. **Clock crossing:** RuntimeInstant deliberately is not Codable. Persist civil Date values only, then derive fresh operational monotonic deadlines in the new runtime. No old uptime/ContinuousClock value crosses restart. Existing civil expiry rules do not promise rollback-independent elapsed-time guarantees across reboot.
7. **Assets:** Every reference, including future timeline and public/sensitive variants, needs canonical live resolution for its publication/revision and host privacy scope. Serialized AssetHandle metadata or a partition UUID is never sufficient. Existing read-only pins can establish current in-memory eligibility; they do not define how cold assets or host-isolated partitions are reconstructed.
8. **Admission:** Decoded input retention, validation scratch, proposed records, active-family permits and native raster lifetime must be prepaid under the existing governor. Revalidate lifecycle and current authority after awaits; final validation and canonical publication/asset commit must not be separated by suspension. Do not release protection while a proposal or borrowed image still retains its allocation.

## Concrete implementation sequence

Execute after the reviewed SwiftData backend is frozen. One implementation worker owns each step; root controls independent review, the sole SwiftPM scratch and final integration. Runtime persistence means the latest successfully saved coherent generation. It does not promise an atomic transaction between every provider acknowledgment and durable storage.

### 3a — Canonical records and namespace-only restoration

Files: `Publications/PublicationState.swift`, `Admission/PublicationSessionRegistry.swift`, a focused immutable archive-record value, and new `PublicationRestorationTests.swift`.

- Add a bounded canonical visitor yielding the complete PublicationID, revision, family, original civil sessionDeadline and complete optional Publication. Exclude notices; do not project due timeline entries or reconstruct history already pruned.
- Extract namespace-only admission/binding from the session registry. Preparation only quotes and validates the verified publisher and existing namespace charge; it must not mutate publisher bindings. Bind during the same final synchronous commit as records/assignments/assets, without creating a connection, sequence or provider authority.
- Add `prepareRestoration`, final validation and synchronous nonthrowing commit. A prepared value binds the state owner and revision, quotes retained record/content growth and active-family permits, rejects collisions and malformed/unsupported data, and turns elapsed content into terminal history. Validate the entire generation before mutation.
- Preserve the current state/family ceilings. Record count is bounded by retained metadata and the archive envelope; it is not equivalent to the active-publication limit. Runtime assignment capacity remains separately applicable.
- Observe behavioral RED, then prove original eight-hour anchors survive restore and higher revision; pending timelines survive; expiry/end cannot revive; foreign/stale proposals, publisher mismatch, collisions and insufficient state leave canonical state unchanged.
- Freeze exact diff/report and obtain independent review before building the next step on these interfaces.

### 3b — Coherent assets and host runtime integration

Files: `Assets/AssetState.swift`, focused archive codec/raster-copy helpers, `AddonRuntime.swift`, and focused asset/runtime restoration tests. Reuse Foundation serialization, existing contract DTOs, ResourceGovernor and AssetDisposalCoordinator; do not add a transaction journal or image decoder.

- Capture assignments, canonical records and exact-revision binding pins synchronously under admitted scratch. Join host partition/feature provenance from current assignments because pins survive provider imports. Deduplicate by backing identity plus host privacy partition. Copy tightly packed canonical RGBA with a bounded admitted CoreGraphics data-provider copy.
- Encode one bounded generation containing records, host feature/partition labels and unique raster blobs. The SwiftData save owns atomic persistence. Scope all captured/encoded buffers through save and all loaded/decoded buffers through the host restoration callback.
- Validate current installed publisher/addon/digest and enabled feature for every restored assignment; require no live process or conflicting current ID/instance. Retain an owner startup-restoration seal in the existing prepaid owner pool: the first successful assignment, accepted launch or restoration commit permanently seals that owner for this runtime lifetime. Failed/cancelled restoration before lifecycle activation may retry. Pruning, provider exit and suspension never reopen the seal; test end → prune → replay of an old live archive. Restore the complete archived PublicationID through a private host path, leaving ordinary `assignPublication` unchanged. Current authority is freshly issued; old provider connection/sequence state is never persisted.
- Map each persisted isolated-group label to one fresh host UUID per load, preserving grouping without merging with other loads, newly assigned scopes or addon-owned state. Labels in the file are provenance to validate, not provider grants.
- Allocate each unique backing once with the existing disposal coordinator. Create fresh per-publication aliases and rewrite declarations and recursive image nodes across every presentation variant and timeline entry. Prepare direct publication pins without synthetic provider connections or import handles.
- `saveArchive(owner:to:)` and `restoreArchive(owner:from:)` require an archive bound to the same verified owner and common governor. Prepay metadata, validation scratch, active families and native backing lifetimes. Revalidate runtime epochs/current authority after awaits. Finally validate assignments, namespace, publication and asset proposals, then commit synchronously with no intervening suspension.
- Every restored record, including a terminal record, receives a prepaid runtime assignment, matching the existing `requiredBytes` accounting traversal. Enforce the existing 16-assignment runtime capacity separately from the more general record/byte bound in PublicationState. Existing pruning removes both inactive history and its assignment; the startup seal prevents later same-runtime replay after that removal. Do not introduce unassigned retained records that a later pool shrink would refund.
- On failure, preserve live state and the previous committed archive; release only this attempt's allocations after proposals/borrowed pixels leave scope. A durable save followed by observed quota debt remains committed and is reported as such.
- Verify coherent save/new-runtime/restore, shared images, isolated groups, fresh aliases, full timelines, original deadlines, terminal state, catalog mismatch, malformed/future generations, cancellation and real-governor denial. Capture cannot recover previously pruned history, and runtime assignment limits still apply independently of the archive's byte bound.

### Integration limits

These internal host composition methods do not by themselves wire app bootstrap or authenticated SDK storage transport. A production startup must inventory the complete retained registry before any normal write, including disabled/uninstalled owners and every archive root. Keep that global admission barrier explicit when connecting the archive to the existing storage coordinator. C0d remains closed.

- [x] Complete and review 3a.
- [ ] Complete and review [3b B1/B2](2026-09-13-addon-runtime-archive-integration.md) against the exact backend interfaces.
- [ ] Resolve the complete-registry storage composition before claiming production archive startup.
- [ ] Run the full serial suite, frozen-input signed build, Applications link update and verified restart under root control.

## Required behavioral test matrix

| Case | Required evidence |
| --- | --- |
| Original activity anchor | Admit at `t0`, capture at `t0 + 2h`, restore at `t0 + 6h`, update revision at `t0 + 7h`; expiry remains `t0 + 8h`. |
| Civil/monotonic restart | Use a new runtime monotonic origin; eligibility follows the preserved civil deadline. Forward civil expiry cannot be undone by restoration; no persisted uptime is consulted. |
| Expiry and explicit end | Restore elapsed/terminal history; no content appears and a higher revision cannot revive the old session. |
| Corrupt/unsupported record | Nonfinite or inconsistent metadata, malformed content and future schema are never promoted into live canonical authority; verify the selected generation-recovery policy after approval. |
| Complete timeline | Capture after one entry is due; canonical restoration retains all future entries and presentation still selects the proper due entry. |
| No notice/command replay | Capture mixed activity/notice state; restoration creates no notice and executes no command/effect. |
| Asset authority | Missing, wrong-publication, wrong-revision, expired or privacy-mismatched references fail; future timeline references are checked. Decoding an AssetHandle alone cannot authorize a pixel. |
| Real resource denial | Fill shared quota before final admission; no partial publication/asset commit or leaked reservation. Existing backing bytes remain charged once. |
| Await invalidation | Gate a completed real reservation operation, invalidate lifecycle or advance expiry, then resume; stale candidates cannot commit. |

Restoration validates a whole generation before activation. A corrupt or unsupported member fails that generation unchanged; no partially restored publication/asset authority is exposed. The backend preserves the committed data and reports its availability separately from any observed disk debt.

## Decision history

The approved documents prescribe versioned, quota-admitted atomic persistence but no publication archive backend or transaction format spanning records and assets. Checkpoints and keyed values are individually bounded to 64 KiB; a complete timeline can be 256 KiB. Splitting records without a commit protocol permits torn generations. The storage coordinator explicitly gates access rather than providing an atomic transaction across roots.

The user selected SwiftData after the earlier GRDB and Foundation-file alternatives. The linked decision records that history. The completed probe and explicitly approved observed-disk policy establish the backend boundary; the concrete sequence above preserves whole-generation consistency, fresh runtime authority and privacy grouping. Retained-owner registry completeness remains a required integration boundary. Implementation status is tracked by the linked storage plan.

## Source evidence

- `docs/superpowers/plans/2026-09-10-addon-runtime-completion.md:277–291`: C5 requires valid restoration without notice/command replay or renewed eight-hour activity duration.
- `docs/superpowers/plans/2026-09-09-addon-runtime-02-execution.md:102–112`: persistence limits and valid/expired/corrupt/future restoration tests.
- `CascadeKit/Sources/CascadeRuntime/Publications/PublicationState.swift:53`: canonical Record retains sessionDeadline separately from Publication; ordinary accept at lines 570–574 creates a fresh deadline. Snapshot near line 698 projects content; canonical lookup near line 715 preserves the timeline.
- `CascadeKit/Sources/CascadeRuntime/Scheduling/RuntimeInstant.swift:8`: runtime clock domains intentionally are not Codable.
- `docs/addons/storage.md:44–98`: checkpoint format and 64 KiB bound; keyed commit/recovery and global coordinator sections describe per-record atomic replacement and the nontransactional cross-root access gate.
- `docs/addons/assets.md`: descriptive AssetHandle metadata, sharing and reviewed internal archive integration.
- Discovery used targeted source/doc reads after the graph reported Cascade was not indexed. This planning task changed no production code and ran no builds.

## Preflight review ledger

Independent preflight identified and resolved three phase-order gaps before implementation: a retained startup seal prevents replay after terminal history pruning; every runtime-restored record keeps a prepaid assignment under the existing 16-assignment capacity; namespace preparation stays nonmutating until the combined final commit. These preserve restart-only restoration and current runtime accounting rather than introducing manual rollback or unbounded history.

## Codec resource preflight

Use a shallow binary-plist envelope of bounded scalar metadata and Data leaves.
Store complete Publication values as individually bounded JSON Data (256 KiB timeline
plus a bounded 4 KiB wrapper), and canonical RGBA as ordinary Data. Do not embed
recursive Publication/ContentNode graphs directly in binary plist: object references
can expand during typed decoding, so raw payload size alone is not a decoded-memory
bound. Foundation remains the parser/serializer.

Check each application collection count before reserve/decode, and check cumulative
accepted blob bytes before retaining the next value. Existing limits include 32 timeline
entries, 64 asset IDs through ContractValidation.unique, the glass-light maximum,
and 128 nodes/depth8 per content document. ContentNode's current decoder materializes
children before its final node check; move the existing limits before recursive
materialization using a shared node/depth budget, preserving current valid inputs.
Publication revision0 remains valid. A fixed32 MiB aggregate DTO reservation has not
been justified; the 3b read-only design must supply checked structural charges and
separate bounded scalar/parser scratch before implementation. No new codec library,
transaction journal or user policy change is needed for these domain checks.

3a review complete: the divergent-value-state mutation nonce fix was independently approved;25 publication tests passed. Exactfix/evidence `/private/tmp/cascade-restoration-issuer-fix.diff` and `/private/tmp/cascade-restoration-issuer-fix-report.md`. The linked B1/B2 plan now supplies aggregate structural charges and a single-publication inspection slot for the codec preflight above.
