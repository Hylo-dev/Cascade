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
- One options lease across the presentation system, preserving the original underlying page.
- 128 nodes, depth 8, 64 KiB per document and existing aggregate/owner budgets.
- Native Back triangle at the position mirrored from settings; 180 ms finite layer transform/opacity transition; Reduce Motion uses opacity only.
- No per-frame SwiftUI state, periodic options timer, polling or main-thread I/O.
- Back/Escape/close/withdrawal/expiry/disable/display removal revoke resources; late replies and old controls cannot reopen detail.
- English code/comments/docs and CODE_STYLE.md conventions. The Debug fixture is host-owned test content, never a production addon fallback.

## Review Focus

1. A click starts provider work, then Back or a display switch happens before the response: obsolete origins cannot reopen or move detail.
2. A publication revision changes while detail is visible: old controls revoke immediately, while the selected detail remains until a valid refresh or revocation.
3. A competing detail replaces another over the file shelf: dismiss restores the original contextual selection rather than overwriting its slot.
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

- [ ] Write failing checks: false/absent flag preserves old encoding; true flag round trip; options unknown-field/size validation; missing capability/stale action/forged source/reused old lease rejection; Back/close/display removal restore ordinary and contextual pages; source revision revokes copied controls; interrupted transition clears outgoing content.
- [ ] Run those checks red with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcrun swift test --package-path CascadeKit --scratch-path /private/tmp/cascade-widget-fullscreen-swift --no-parallel --filter <focused suite>`; capture exact failures. Existing relevant suites supply the baseline.
- [ ] Implement the shortest shared contracts/runtime/presenter path, using canonical snapshots and finite native animations. Negotiate `notch.options.v1` only on a connected host and preserve older negotiation.
- [ ] Run focused suites green, then full serial package tests and boundary checks. Expected: no new failures and unchanged launcher hold. Record exact results and any pre-existing failures.
- [ ] Commit only this feature's code and tests; produce a report of files, red/green evidence, authority/resource/lifecycle decisions and any qualification limits.

### Task 2: App fixture, visual and performance qualification

**Files:** Debug host-owned scenario under `Cascade/Checks` and its opt-in app composition hook; usage docs and verification record under `docs`.

**Interfaces:** The Debug scenario publishes an ordinary snapshot widget through the generic bridge and opens detail using the same host container. It exposes a clickable title, a separate compact control, detail actions and native Back, plus deterministic withdrawal/refresh hooks. It never starts or bypasses an external addon process.

- [ ] Add a check demonstrating the fixture exercises the common origin/presentation/dismiss path, including stale source rejection. Run red then green.
- [ ] Capture the existing app's ordinary notch idle/open/close CPU and memory baseline. Build the feature through `scripts/build-development.sh` with scratch DerivedData under `/private/tmp`.
- [ ] Drive the opt-in real app fixture through opening, independent control, Back, Escape, rapid retarget and close/reopen; inspect the notch visually. Measure matching idle/open-close/visible/closed windows and compare CPU/memory/wakeups where available. Keep hardware-only multi-display evidence explicit.
- [ ] Document the public usage pattern and record verified versus pending scenarios. Expected: fixture route works, no periodic options timer, no accumulating hosts/leases, successful canonical build.
- [ ] Commit verification/docs. Request fresh independent review of the whole feature, address important findings with red/green checks, and run covering regression tests.
- [ ] Update `/Applications/Cascade.app`, quit/relaunch the normal updated app and verify executable/PID. Keep the managed worktree attached with its finished code; do not merge or push without a user instruction.

## Self-review and execution

The interfaces shared by both tasks are the options request/projection and the
generic host presenter; Task 2 uses them and does not introduce a second route.
Task 1 owns contracts, authority and UI as one coupled deliverable so no worker
edits a partially defined neighboring API. Task 2 owns qualification and Debug
composition. Both tasks include all five Review Focus scenarios in the affected
checks. Execute now under the user's explicit implementation instruction; keep
one implementer at a time and use an independent review before completion.
