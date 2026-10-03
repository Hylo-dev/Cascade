# Addon Widget Fullscreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Supply a reusable SDK widget detail route and a native animated notch container with Back and correct restoration.

**Architecture:** A declared widget action obtains a host-captured origin. Runtime authorizes a bounded options document against that action and feature, retains one canonically owned lease, and projects accepted changes to the presentation bridge. The coordinator overlays this detail on the existing selection; native layers animate the transition and native chrome supplies Back.

**Tech Stack:** Swift 6.2, CascadeContracts/AddonSDK/Runtime/Presentation/Kit, AppKit, Core Animation; macOS 15; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-03-addon-widget-fullscreen-design.md` (approved in chat; user explicitly requested implementation).

## Global Constraints

- `supportsFullscreen` defaults to false, and false is omitted from encoded manifests.
- No external provider code runs in the host; current native launcher hold remains intact.
- Options use the canonical feature/publication/action, revision, generation and resource checks; source display is host-owned.
- One options lease and one pending visible widget origin across the presentation system. The latest pending click revokes the preceding origin; no origin queue or detail stack.
- Opening requires the visible ordinary widget grid. Back restores that ordinary selection on the original display and preserves the unselected contextual slot. Selected shelf/activity pages have no visible widget entry surface.
- 128 nodes, depth 8, 64 KiB per document and existing aggregate/owner budgets.
- Replay history holds 256 bindings across all live connection generations, charged at 128 bytes each (32 KiB total). Exact owner/generation invalidation refunds its bindings; capacity denies new leases without history eviction.
- Prepare and validate every publication, imported asset, options proposal and correlated completion before presenter mutation; then commit synchronously without throwing.
- Native Back triangle at the position mirrored from settings; 180 ms finite layer transform/opacity transition; Reduce Motion uses opacity only.
- No per-frame SwiftUI state, periodic options timer, polling or main-thread I/O.
- Back/Escape/close/withdrawal/expiry/disable/display removal revoke resources; late replies and old controls cannot reopen detail.
- English code/comments/docs and CODE_STYLE.md conventions. The Debug fixture is host-owned test content, never a production addon fallback.

## Review Focus

1. A click starts provider work, then Back or a display switch happens before the response: obsolete origins cannot reopen or move detail.
2. A publication revision changes while detail is visible: old controls revoke immediately, while the selected detail remains until a valid refresh or revocation.
3. Visible grid clicks A then B occur before either reply: B revokes A, delayed A cannot open, B opens, and Back prevents either reply reopening. Restore the original ordinary selection and preserve the unselected file shelf slot; selected contextual/activity pages cannot authorize hidden widgets.
4. Rapid open/Back/open interrupts a transition: at most current incoming/outgoing hosts survive and completion of an old animation cannot hide the new page.
5. A provider forges or reuses another lease/source/request: canonical owner/feature/generation and current budgets reject before projection.

---

### Task 1: Shared options route from SDK to native host

**Files:**
- Modify `CascadeKit/Sources/CascadeContracts/Models/Addon/AddonFeature.swift`, `Models/Session/OperationRequest.swift`, protocol negotiation and output validation.
- Create options request/projection value types in `CascadeContracts/Models/Options`, SDK request convenience in `CascadeAddonSDK/Core/Options`, and bounded options authority in `CascadeRuntime/Core/Options`.
- Integrate with `CascadeRuntime/Core/Runtime/AddonRuntime.swift`, accepted actions, generation/owner invalidation, publication accounting and a synchronous options adapter/projection seam.
- Modify `CascadeKit/Core/AddonPresentation/AddonPresentationBridge.swift`, its sink and SnapshotWidget action origin path.
- Add a dedicated widget detail overlay in `NotchDisplayCoordinator`/`NotchController`, generic engine methods and native Back/finite transitions in `NotchHostView`.
- Test contracts, runtime options/action/negotiation/accounting, bridge, coordinator restoration and interrupted transitions in their existing test targets.

**Interfaces:** `AddonOptionsRequest(publicationID:observedRevision:actionRequestID:leaseID:document:)` is an immutable Codable bounded request. `OperationRequest.presentOptions(AddonOptionsRequest)`/`.dismissOptions(UUID)` carry only values. A host-only opaque origin token binds the accepted action to the display and prior selection. Runtime supplies accepted presentation changes to `AddonPresentationBridge`; do not let a wire display ID mint an origin. The host presenter returns acceptance and an idempotent dismiss callback, keeping the contextual page slot intact. Retained options actions enter the existing action authorization/delivery path with the leased document as the authorized representation.

- [x] Write failing checks: false/absent flag preserves old encoding; true flag round trip; options unknown-field/size validation; missing capability/stale action/forged source/reused old lease rejection; invalid imported assets reject a mixed options batch before projection while preserving valid detail/budget; latest pending A/B click wins and Back rejects both late replies; Back/close/display removal preserve ordinary navigation and the unselected contextual slot; selected shelf/activity rejects hidden widget origins; source revision revokes copied controls; interrupted transition clears outgoing content.
- [x] Run those checks red with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcrun swift test --package-path CascadeKit --scratch-path /private/tmp/cascade-widget-fullscreen-swift --no-parallel --filter <focused suite>`; capture exact failures. Existing relevant suites supply the baseline.
- [x] Implement the shortest shared contracts/runtime/presenter path, using canonical snapshots and finite native animations. Negotiate `notch.options.v1` only on a connected host and preserve older negotiation.
- [x] Run focused suites green, then full serial package tests and boundary checks. Expected: no new failures and unchanged launcher hold. Record exact results and any pre-existing failures.
- [x] Commit only this feature's code and tests; produce a report of files, red/green evidence, authority/resource/lifecycle decisions and any qualification limits.

### Task 2: App fixture, visual and performance qualification

**Files:** Debug host-owned scenario under `Cascade/Checks` and its opt-in app composition hook; usage docs and verification record under `docs`.

**Interfaces:** The Debug scenario publishes an ordinary snapshot widget through the generic bridge and opens detail using the same host container. It exposes a clickable title, a separate compact control, detail actions and native Back, plus deterministic withdrawal/refresh hooks. It never starts or bypasses an external addon process.

- [x] Add the finite compiled-app check covering the common origin/presentation/dismiss path, including stale source rejection; compile the real missing hook RED then GREEN, and pass covering shared behavioral checks. Native execution of that check remains in the next pending qualification item.
- [x] Capture normal closed and requested-expanded CPU/physical-footprint baseline and updated idle samples; build the feature through `scripts/build-development.sh` with scratch DerivedData under `/private/tmp`. Actual interactive open/close baseline was unavailable through the empty computer-use surface; visible source matching, private-memory/wakeup/timing and interaction measurements remain pending.
- [ ] Drive the opt-in real app fixture through opening, independent control, Back, Escape, rapid retarget and close/reopen; inspect the notch visually. Measure matching idle/open-close/visible/closed windows and compare CPU/memory/wakeups where available. Keep hardware-only multi-display evidence explicit.
- [x] Document public usage and verified versus pending scenarios, including shared route/host checks and the successful canonical build. The fixture's native scenario still needs execution; no periodic options timer was introduced.
- [x] Commit verification/docs. Request fresh independent review of the whole feature, address findings with red/green checks, and run covering regression tests. Whole-feature review and the single scoped lifetime-fix review approved; 1,875 full tests passed. Newly executed native fixture qualification is recorded separately.
- [x] Update `/Applications/Cascade.app`, quit/relaunch the normal updated app and verify executable/PID (51182, final source 0fa653b, exact feature-derived executable). Keep the managed worktree attached with its finished code; do not merge or push without a user instruction.

Execution evidence: `docs/superpowers/verification/2026-10-03-addon-widget-fullscreen.md`.
Computer use initially reported a locked session and failed automatic unlock.
The shell later became readable, but input actions returned
AXError.actionUnsupported and the screenshot remained an empty white panel.
The signed native fixture check was executed and failed to find its first
compact button: the mounted SwiftUI hosting group had no AX children. A Debug
activation experiment was falsified and removed. Native interaction/visual
clearance, interaction measurements and physical multi-display coverage remain
unqualified. No hidden-source or lock bypass was introduced. Normal idle CPU
and physical-footprint samples are recorded, without claiming visual matching.
Task reviews, whole-feature review and the single scoped lifetime fix review
are approved; qualification evidence preserves the outstanding app-check failure.

## Self-review and execution

The interfaces shared by both tasks are the options request/projection and the
generic host presenter; Task 2 uses them and does not introduce a second route.
Task 1 owns contracts, authority and UI as one coupled deliverable so no worker
edits a partially defined neighboring API. Task 2 owns qualification and Debug
composition. Both tasks include all five Review Focus scenarios in the affected
checks. Execute now under the user's explicit implementation instruction; keep
one implementer at a time and use an independent review before completion.
