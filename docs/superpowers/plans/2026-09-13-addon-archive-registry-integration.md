# Archive integration with the complete retained registry

Status: B2 runtime save/restore complete and independently approved. C1 implemented and independently approved; C2 complete-registry inventory and scoped fix independently approved; C3 concrete runtime operations independently approved and delivered. The user already approved SwiftData, observed disk debt and shared asset privacy scopes; the assessed composition requires no new policy choice.

## Reviewed direction

Extend the existing fixed-registry AddonStorageCoordinator; preserve StateRegistration's checkpoint schema meaning. Add a bounded archive root with per-owner names from KeyedStorageRecord.namespaceDigest/hex (verified publisher/addon, excluding executable digest). Reuse KeyedStorageDirectory secure descriptor traversal, entries, child checks and private directory validation. No new journal or generic storage abstraction is required.

Keep a private registry-aligned persistent archive object/slot for every registered retained identity, including disabled/uninstalled owners. Discover every existing archive and establish all known ledgers before any SwiftData container open or normal persistence. Open SwiftData lazily only when an accepted runtime save/restore needs that owner, avoiding hundreds of inactive framework containers. Preserve existing checkpoint/keyed startup order and global readiness semantics.

Missing owner directories require a persistent admitted archive ledger before creation. Refine SwiftDataArchive discovery to retain an absent-directory state or equivalent private provisioning ownership; strictly reserve directory bytes before mkdir and preserve the same object/token through failure and retry. Do not provision through a temporary generic reservation that cleanup can refund before ownership transfer. No file/sidecar deletion or physical-close claim is introduced. This lifecycle extension needs its own concrete file/API preflight and regression review before edits.

Inside a verified owner root, its existing observer counts all safe unknown file bytes and preserves charges under incomplete/unsafe scans. An unknown outer namespace has no verifiable registered owner: preserve established ledgers and known charges, mark inventory incomplete and deny all normal storage access. Do not invent attribution to the first addon or a synthetic host identity, and do not claim complete accounting. The host must supply the complete retained registry; permitting access despite unresolved ownership would be a separate policy decision and is not proposed.

## Narrow runtime composition

Prefer concrete coordinator methods saveArchive(owner: Owner, runtime: AddonRuntime) and restoreArchive(owner: Owner, runtime: AddonRuntime). Validate the fixed Owner epoch, derive the addon identity from its registry row, retain the active coordinator operation and privately borrow the archive into the B2 runtime method. Keep the runtime's same-governor, verified identity and current lifecycle checks. Return only scalar save/restoration outcomes, never a raw backend or arbitrary escaping callback.

Close revokes new calls immediately and reports draining while accepted runtime work finishes. Preserve known committed saves and completed restoration effects; no post-return stale-epoch check may describe them as rolled back. Logical suspension retains archive objects, locks and ledgers. Narrow the coordinator header accordingly: no raw backend/capability is returned to callers; concrete runtime composition borrows it only for the accepted operation.

## Required finite steps and evidence

1. Persistent absent-root discovery/provisioning lifecycle, with strict directory admission, failures/cancellation/retry and no double accounting. Keep existing direct-backend behavior compatible where practical.
2. Complete outer/owner registry inventory, lazy framework startup and preserved ledgers across coordinator retry/suspend. Unknown outer names, late-owner failures and cancellation after successful discovery must leave readiness closed and known charges intact.
3. Concrete runtime save/restore composition with foreign/stale Owner denial, same governor, close during accepted work, known commit preservation and real fresh-runtime restoration.

Root must turn each step into a bounded implementation brief and obtain preflight review before dispatch. One implementation worker and one SwiftPM scratch; independent read/review may run alongside. Full serial package verification, signed build, Applications link update and verified normal restart remain mandatory at delivery. Weekly use must remain below60%, including verification reserve. App bootstrap/dynamic registry adoption, authenticated SDK transport and C0d are not claimed by this fixed-registry increment.

## Assessment ledger

Independent read-only assessment approved the existing-coordinator extension, lazy framework opening, narrow concrete runtime borrowing, and fail-closed unowned outer namespace semantics. Missing-directory lifecycle is routine composition but still needs a concrete preflight; no implementation or test result is claimed here.

C1 read-only design refinement is recorded in `/private/tmp/cascade-runtime-archive-c1-brief.md`: a new discovery path retains an admitted token and duplicate of the held registry-parent descriptor before child inspection; absence remains distinct from unsafe/replaced ownership, and lazy creation grows the same protected token before mkdir. Existing make remains compatible. This brief still requires independent preflight before implementation; B2 completion remains first.

C1 independent preflight approved the concrete absent-directory/token lifecycle without findings. The derived child URL must satisfy the full URL bound, the caller retains its parent descriptor through duplication, and the duplicate is revalidated before child inspection. These checks are explicit in the brief. Implementation remains sequenced after B2 runtime review.

C2/C3 concrete preflight: use a dedicated observed token, initially zero, for the known outer root's4KiB allowance attributed to the first fixed registration, matching existing keyed-root metadata accounting. Retain it across close/retry; reconcile only after safely holding the parent and before cancellation/epoch checks. Child roots remain solely in C1 ledgers; unknown outer contents remain unattributed and keep the global gate closed. The C1-facing raw inventory snapshot distinguishes complete safe inventory from model corruption, so a corrupt row cannot masquerade as an unaccounted directory. Exact next brief: `/private/tmp/cascade-runtime-archive-c2c3-brief.md`; implementation remains after reviewed B2/C1.

Outer-root restart clarification: retain and reuse the same held parent open-file description across logical close/retry; independently reopening it would contend with the retained C1 duplicates. The root observed token remains protected and is not refunded by generic cleanup.


C1 dispatch follows the detailed readiness sequence in `/private/tmp/cascade-runtime-archive-c1-readiness.md` and approved `/private/tmp/cascade-runtime-archive-c1-brief.md`. One implementation worker owns the single SwiftPM scratch. C2/C3 remain separate reviewed slices. Weekly allowance39%; retain final test/build/restart headroom under60%.


C1 implementation frozen for independent review: root verified five hashes. Final36 tests/three suites pass (ten discovery tests with19 parameter cases,18 backend and8 observed-governor tests). A real parent-replacement regression proved that an already completed observation must participate in the conservative retained-byte maximum; its RED and correction are recorded in `/private/tmp/cascade-runtime-archive-c1-report.md`. Exact diff/hashes use the same c1 prefix. C2 remains undispatched pending review.


C1 independently approved without introduced blockers; all five frozen hashes match. Persistent ledgers, shared parent descriptor ownership, strict4KiB provisioning, conservative failure accounting, replacement rejection and independent raw status satisfy the approved contract. C2 is now dispatched as a separate coordinator/inventory slice under `/private/tmp/cascade-runtime-archive-c2c3-readiness.md`; C3 runtime facade remains gated on its review.


C2 frozen for independent review: three exact hashes verified by root;55 tests/five suites pass. Existing coordinator assertions explicitly include the new archive baselines while retaining their original checkpoint/keyed deltas. A separate compiling RED showed an unknown outer entry arriving during keyed startup; parent/outer validation now follows those startup awaits before readiness. Exact report/diff/hashes use `/private/tmp/cascade-runtime-archive-c2-*`. Scratch released; C3 still unimplemented.


C2 independent review found one P2 at the final outer scan: membership-only validation allowed a registered child replaced by a symlink/file/nonprivate directory during keyed admission to reach readiness. Root verified the source and dispatched a bounded no-follow directory/owner/mode check plus a deterministic extension of the existing late-admission regression. No recursive rescan, new C1 snapshot API or atomic-filesystem guarantee is introduced. Other C2 lifecycle/accounting checks passed; C3 remains gated on the scoped correction review.


C2 fix1 independently approved: the P2 is resolved and no new fix-scope finding remains. Root verified the canonical three hashes and fix-specific two hashes. Actual RED covered six readiness errors across symlink/file/mode; final55 tests/five suites pass with all four late-admission cases. `/private/tmp/cascade-runtime-archive-c2-fix1-report.md` records exact evidence. C3 concrete save/restore facade is dispatched with the same scratch and existing B2 committed-result semantics.


Next independent host-only increment, after this plan's delivery verification: [significant-event dirty tracking and one-attempt flushing](2026-09-13-addon-archive-event-flushing.md). Existing specifications already require meaningful-event persistence and bounded stop checkpoint work, so an arbitrary debounce interval is not a new user decision. The next plan has independent preflight with a terminal-history marking correction incorporated, but no source dispatch. It excludes application wake scheduling and separately scoped shutdown quiescing; C0d remains closed.


C3 independently approved without findings; root verified all three frozen hashes. Full combined delivery passed 679 serial tests in 69 suites, 381 identical build/test inputs and 30 reviewed source/test hashes. Signed build, strict signature check, Applications link update and normal restart PID 78065 → 97296 succeeded. Weekly use 43%. Exact evidence is in [the delivery record](../verification/2026-09-13-addon-swiftdata-runtime.md). C4 is now dispatched under its corrected, independently approved preflight; this completed delivery remains its baseline.
