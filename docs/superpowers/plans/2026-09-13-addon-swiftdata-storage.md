# SwiftData Observed Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Root owns integration, exact source snapshots and delivery. One implementation worker at a time; independent read/review work may run alongside it.

**Goal:** Implement the approved SwiftData storage policy with measured overbudget debt, blocked subsequent writes and preserved committed archive generations.

**Architecture:** The shared ResourceGovernor issues a protected measured-disk capability. A persistent internal owner-bound SwiftData archive actor inventories its private database root before and after framework operations, including failures, and uses that capability to retain actual charges. Strict application payload/memory admission remains separate. Per-owner roots conservatively attribute all database/sidecar overhead to that verified owner and avoid unverifiable shared-page apportionment.

**Tech Stack:** Swift 6, SwiftData/ModelActor, Foundation, existing ResourceGovernor and secure filesystem helpers; macOS 14 floor. No third-party package, custom SQLite VFS or provider launcher.

**Spec:** [Approved disk policy](2026-09-13-addon-swiftdata-disk-policy-decision.md), [selected archive direction](../specs/2026-09-13-addon-swiftdata-archive-design.md), existing storage/asset contracts.

## Constraints

- Preserve dirty checkout and existing untracked plugin work. Capture preimages, do not commit/reset/stage unrelated changes.
- User authorized framework disk overshoot observed after operations. No other resource ceiling or backend preadmission rule is weakened. Weekly consumption must remain below 60%.
- Existing owner ceilings remain 10 MiB data/20 MiB cache/30 MiB combined; disk is 100 MiB globally. Framework reservations use data class and include actual managed file lengths and conservative file/directory metadata.
- Never free retained disk accounting through generic release/releaseAll or close/suspend assumptions. Only measured shrink/removal may reduce observed charges.
- No silent archive deletion, sidecar truncation or fake rollback after a committed save. Overbudget data remains charged and subsequent writes fail until reconciliation shows available budget.
- Framework RSS and internal transient allocation remain observed/estimated; prepay bounded application-owned buffers before allocation/retention. No guarantee of physical disk or RSS ceilings.
- Actual API qualification was macOS 27 with macOS 14 deployment target; no macOS 14 runtime qualification is claimed. C0d stays closed.

## Task 1 — Protected observed disk accounting

Files: modify `CascadeKit/Sources/CascadeRuntime/Resources/ResourceGovernor.swift`; new `CascadeKit/Tests/CascadeRuntimeTests/ObservedDiskReservationTests.swift`.

Interfaces: internal opaque `ObservedDiskToken`, strict initial/growth admission, checked expected-size reconciliation that may record bytes beyond owner/global ceilings, status exposing overage/write admissibility, and explicit final release only after measured zero. Exact names are recorded in the implementer report before Task 2. Capabilities bind one governor/owner/lifetime; generic disk resize/release/releaseAll cannot bypass the protected ledger.

- [x] Write a compiling behavioral RED: strict reserve succeeds, reconcile actual files beyond 10 MiB, usage reports all bytes, new disk growth is denied; generic owner cleanup leaves the debt intact.
- [x] Implement checked arithmetic, canonical expected-size checks and protected lifecycle. Shrinking one debt does not clear another owner/global debt. Normal checkpoint/keyed/raster behavior remains unchanged.
- [x] Verify foreign/stale capabilities, overflow/negative observations, shared global pressure, unrelated reservations, strict growth vs observed reconciliation, and release only after zero inventory.
- [x] Run focused/adjacent governor tests, capture exact diff/report, obtain independent spec/quality review and fix concrete findings.

## Task 2 — Owner-bound SwiftData archive backend

Files: new focused `CascadeRuntime/Storage/SwiftDataArchive*.swift` files and `Tests/CascadeRuntimeTests/SwiftDataArchiveTests.swift`.

Interfaces: persistent private host object created with verified identity/root/common governor; unavailable until raw inventory admission and framework open/recovery reconciliation. Host save/load uses bounded immutable versioned generation values, never model/context references. Explicit save, autosave disabled, undo nil, CloudKit none; serial background worker. A status distinguishes ready/overbudget/suspended/faulted from a physically closed database, which SwiftData does not publicly guarantee.

Exact backend shape: `make(identity:root:governor:)`, `start`, scoped `withGeneration`, revision-checked `save`, `reconcile`, and logical `suspend`. The generation carries schema version, UInt64 revision, bounded verified digest and at most 8 MiB of ordinary Data. Each owner root keeps one SwiftData row with namespace and checksum. Use 16 KiB protected actor/root metadata, a 1 MiB estimated framework workspace plus full candidate payload and 4 KiB envelope disk prepayment before save; replace the estimate with actual observed files afterward.

Scoped reads retain protected temporary memory through the complete host callback; the internal callback must not retain the payload afterward. This is a caller contract, not a type-system guarantee. The private worker uses fresh local operation contexts so its executor context does not retain application row payloads between calls. Known caller-owned input remains the caller's responsibility before save. SwiftData's internal caches remain observational.

Startup must distinguish raw inventory from opening SwiftData: the complete host registry can establish every retained owner's ledger before any framework operation or normal write. The root is host-private; descriptor/path inode comparisons detect replacement but do not make SwiftData's URL opens descriptor-relative. Suspension retains the worker, lock and ledger. Dropping an object never refunds retained files.

- [x] Test real private-directory save/reopen, explicit failed-candidate preservation, namespace/schema/digest integrity and bounded input before controlled copies. Use Foundation serialization and SwiftData transactions, not a second journal.
- [x] Reuse secure root traversal/flock and validate complete root URL before retention. Inventory all managed files safely; no symlink/hardlink/device following. Unknown files must be charged and block normal use, not silently ignored/deleted.
- [x] Prepay actor/operation metadata and candidate workspace. Retain the established disk token/object across retry and suspension. Successful or failed open/save/read reconciles all generated files before normal result/capability publication; cancellation does not skip accounting.
- [x] Gate new writes by canonical current owner/global debt. A save followed by an excess-size finding reports committed/overbudget distinctly. A synchronous failed save rolls back unsaved context changes but never claims that file growth vanished.
- [x] Test overshoot deterministically with an injected observer forwarding real filesystem inventory plus test-owned extra bytes/files, and with actual governor debt. Verify no second write, no charge loss, no data deletion, retry after measured shrink, cancellation and overlapping operation exclusion.
- [x] Verify real save/reopen and measurements, obtain independent review, update exact backend contract/limitations.

## Task 3 — Canonical publication and asset restoration integration

After Task 2's exact interfaces are frozen, implement the existing restoration draft against this backend: canonical full timelines/history/original deadlines, deduplicated RGBA blobs in owner/privacy scopes, host-verified assignments, fresh alias/partition reconstruction and coordinated publication/asset admission. No provider connection or serialized handle grants authority. Define concrete file-level substeps from current state before edits; this task must not claim app bootstrap or C0d launch qualification prematurely.

- [x] Capture current state through bounded canonical visitors and admitted pixel copying, excluding notices/commands.
- [x] Save/load coherent owner generations; validate whole generations before any live activation.
- [x] Recreate raster backings with the existing disposal coordinator, prepay metadata/family permits, then synchronously commit publication and asset proposals with original deadlines and fresh authority.
- [x] Test save → new host state → restore for timelines, expired/terminal state, shared images, privacy isolation, malformed/future data and quota/cancellation rollback.
- [x] Connect the host entry points needed by the current runtime and document remaining native/app adoption work.

## Delivery

- [ ] Full serial package suite from one normalized frozen copy using the existing single scratch; no duplicate caches under disk pressure.
- [ ] Signed build, strict signature verification, Applications link update, normal restart and observed new PID.
- [ ] Record exact tests, input hashes, measured limits and weekly allowance. Continue while authorized work remains and no new substantive design decision or allowance boundary is reached.

## Review ledger

- Task 1: complete. 26 focused/adjacent tests passed, including 8 observed-disk cases. Independent review approved the frozen two-file diff without findings. Exact report: `/private/tmp/cascade-observed-disk-task1-report.md`.
- Task 2: complete. Review fix 1 prevents unsafe-but-complete inventory from refunding prior bytes and counts larger known opened-file lengths. Both real-filesystem regressions and the scoped fix were independently approved. Final 44 tests/4 suites passed, including 18 backend tests. Exact report/current hashes: `/private/tmp/cascade-swiftdata-task2-report.md` and `/private/tmp/cascade-swiftdata-task2-hashes.json`.
- Task 3a: complete. Canonical capture, namespace-only preparation and restoration preserve original history/deadlines. Review fix 1 refreshes proposal authority after every state transition so divergent copied states cannot exchange prepared accounting. Scoped review approved the fix; 25 publication tests passed. Exact report: `/private/tmp/cascade-restoration-issuer-fix-report.md`.
- Task 3b B1: complete. Production review approved the bounded decoder and positional Foundation codec. A test-only evidence correction now distinguishes pre-decode aggregate rejection from later validation, with actual mutation RED and restored-source GREEN. Final 63 tests/7 suites passed; all seven hashes verified by root; scoped re-review approved without new findings. Exact report: `/private/tmp/cascade-runtime-archive-b1-report.md`.
- Task 3b B2a: complete. Canonical capture, direct-pin proposals, copied-state nonce and native raster-copy lifetimes passed independent review; 65 covering tests/7 suites passed and all three hashes were verified. Exact report: `/private/tmp/cascade-runtime-archive-b2a-report.md`.
- Task 3b B2b: complete. Independent review approved coherent save, resource lifetimes and committed outcomes with no findings;66 covering tests/6suites passed and both hashes verified. Report: `/private/tmp/cascade-runtime-archive-b2b-report.md`.
- Task 3b B2c: complete and independently approved without blockers. 102 covering tests/ten suites pass, including fourteen restoration tests; root verified all five hashes. Report: `/private/tmp/cascade-runtime-archive-b2c-report.md`. Internal runtime save/restore entry points are complete; production bootstrap remains separate.
- Retained-registry integration: C1 persistent discovery is complete and independently approved (36 covering tests); C2 complete-registry inventory and its late-entry correction are independently approved (55 covering tests) under [the reviewed plan](2026-09-13-addon-archive-registry-integration.md). C3 concrete forwarding is implemented and independently approved (87 covering tests).
- Delivery complete: 679 serial tests in 69 suites, 381 frozen inputs, signed build and verified normal restart to PID 97296. The [verification record](../verification/2026-09-13-addon-swiftdata-runtime.md) distinguishes reviewed focused results from delivery evidence.

Framework choice, shared-asset privacy scopes and observed-disk policy are already approved. No new user decision is required for the reviewed B1/B2 implementation or the preflighted C1/C2/C3 composition.
