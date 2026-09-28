# Multi-display Notch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, or superpowers:subagent-driven-development if the user selects delegation. Steps use checkbox (`- [ ]`) syntax for tracking. Implementation authorized by the user on 25 September 2026; execute the linked Wayfinder tickets with subagents.

**Goal:** keep the notch on every display, allow only one opening and distribute the Live Activities according to the user's preference.

**Architecture:** a global coordinator owns displays, focus, routing and the content lifecycle; each display has a stable presentation controller. The existing rendering and animations are reused. The activity copies share identity and source but have local views.

**Tech Stack:** Swift 6, macOS 14+, AppKit, Core Animation, SwiftUI, Swift Testing, Accessibility already used by the project.

**Spec:** [2026-09-24-multi-display-notch-design.md](../specs/2026-09-24-multi-display-notch-design.md). It contains the confirmed requirements and, separately, the choices proposed to complete the unspecified cases.

**Status:** plan prepared on the working tree of 24 September 2026; execution authorized on 25 September and tracked in the Wayfinder map. Confirmed focus: active window, pointer as a fallback. Recommended execution in sequence in the same context, since the tasks change the same contract between host and controller.

## Global Constraints

- macOS 14 minimum; Swift 6; AppKit/Core Animation for panels and morph, SwiftUI for content.
- No new dependency or private API for this feature.
- A single global mouse monitor; no polling of focus or displays.
- The display links stop at stable geometry. Focus updates do not recreate panels.
- Privacy and accessibility applied to every copy before the sensitive factories.
- Existing hardware calibrations preserved; old software calibrations must not prevent the new small bump.
- End of implementation: relevant tests, build with `scripts/build-development.sh`, update of the `/Applications/Cascade.app` link, relaunch and verification of the process.
- The working tree contains many pre-existing changes, including in the affected files. Before execution capture their diff; do not revert them, do not include them indiscriminately in commits and do not start from HEAD, losing the current state.

## Review Focus

1. The active window changes display without changing app, while the pointer stays still: the content follows the window. Test in task 2.
2. Fixed display disconnected/reconnected with a different numeric ID: no transfer to another monitor; restore through the UUID. Tests in task 1 and task 7.
3. Opening on A and a compact copy on B of the same activity: no double activation or premature suspension. Test in task 3.
4. Two opening requests during closing, a drag or a late callback: never two open panels, last valid destination. Test in task 4.
5. An 8 pt bump and an old 220 × 32 pt calibration on a display without hardware: readable content, 24 pt separation, visual geometry and hit test coinciding. Test in task 5.

## Verified current state

All the following paths are relative to the repository root.

| Existing code | Consequence for the change |
| --- | --- |
| `CascadeKit/Sources/CascadeKit/Core/Engine/NotchEngine.swift` | Creates a single panel, controller, resolver and monitor. Becomes the coordinator's facade. |
| `Core/Engine/NotchController.swift` under the same module | Owns `LiveActivityHost`, `WidgetHost`, resolver and monitor; `refreshActiveDisplay()` moves the panel. Separate global orchestration from local rendering. |
| `Core/Display/SafeAreaNotchDetector.swift` | Today it follows the pointer. It does not represent the required focus. |
| `Core/Activities/LiveActivityHost.swift` | `isExpanded` replaces the compact selection and clears the secondary; `isVisible` is global. Sharing this instance between controllers is not enough without changing the contract. |
| `Models/Configuration/NotchConfiguration.swift` | 220 × 32 pt fallback; a single measurement used for rest and separation. |
| `Core/Interaction/NotchSizePreferences.swift` | Already resolves the UUID identity; reuse this logic. |
| `Extensions/CGPath+NotchDroplet.swift` | Joins the side satellite to the silhouette; does not implement the new vertical droplet. Keep the existing path. |
| `Cascade/Features/Spotlight/SpotlightDropletLayout.swift` | Layout for the native Spotlight field; do not use it as the generic engine of the new Dynamic Island. |
| `Cascade/Integrations/Spotlight/SpotlightAccessibilityMonitor.swift` | Local model of AX worker, generations and notifications to follow. |
| `Cascade/Features/MediaLiveActivity.swift` and `Core/AddonPresentation/SnapshotActivity.swift` | They keep a single context/permission per activity; shared activations are needed, not one per copy. |

The MCP graph does not contain an index of Cascade; this survey uses the code of the working tree. The paths and interfaces proposed below must be checked again before applying the plan if the code has changed in the meantime.

## Task 1: Identity, inventory and routing preferences

**Files:** create `CascadeKit/Sources/CascadeKit/Models/Display/DisplayPresentationPreferences.swift`, `Core/Display/DisplayInventory.swift`, `Core/Display/ActivityDisplayRouting.swift` and `Tests/CascadeKitTests/ActivityDisplayRoutingTests.swift` under CascadeKit. Change `Core/Interaction/NotchSizePreferences.swift` only to share the UUID resolution with the inventory, without changing the keys of the existing calibrations.

**Interfaces:** public `DisplayIdentity`, `RawRepresentable`, `Hashable`, `Codable`, `Sendable`, with `rawValue: String` and `init(rawValue:)`. Public `DisplayPresentationPreferences` with `activityMode: LiveActivityDisplayMode` and `styles: [DisplayIdentity: ExternalNotchStyle]`. The models have explicit public initializers.

```swift
public nonisolated enum ExternalNotchStyle: String, Codable, Sendable {
    case notch, dynamicIsland
}
public nonisolated enum LiveActivityDisplayMode: Codable, Equatable, Sendable {
    case allDisplays
    case focusedDisplay
    case fixedDisplay(DisplayIdentity)
}
// Internal pure routing function; no AppKit calls or preferences reads.
static func destinations(
    mode: LiveActivityDisplayMode,
    connected: Set<DisplayIdentity>,
    focused: DisplayIdentity?
) -> Set<DisplayIdentity>
```

- [x] Write the test below, which initially fails because the types and the resolver do not exist.

```swift
@Test func fixedDisplayDoesNotFallBackWhenDisconnected() {
    let a = DisplayIdentity(rawValue: "A")
    let b = DisplayIdentity(rawValue: "B")
    #expect(ActivityDisplayRouting.destinations(
        mode: .fixedDisplay(a), connected: [b], focused: b
    ).isEmpty)
    #expect(ActivityDisplayRouting.destinations(
        mode: .fixedDisplay(a), connected: [a, b], focused: b
    ) == [a])
}
```

- [x] Run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path CascadeKit --filter ActivityDisplayRoutingTests`; observe the initial failure.
- [x] Implement `ActivityDisplayRouting.destinations`: all → `connected`; focus → singleton if present in `connected`, otherwise the empty set; fixed → singleton of the requested identity only if connected. The choice of the focus fallback belongs to task 2.
- [x] Implement an injected inventory behind `DisplayInventoryProviding`: property `displays: [DisplayInventoryEntry]`, callback `onChange`, methods `start()` and `stop()`. `DisplayInventoryEntry` contains `snapshot: ActiveDisplay`, `identity: DisplayIdentity?`, `name: String`. Publish only topology/geometry/scale changes; one surface per logical display.
- [x] Use a single Codable payload `displayPresentationPreferencesV1` in UserDefaults; unknown/corrupted setting → `.focusedDisplay`, missing style → `.notch`. A valid record with an offline UUID stays saved. Treat screens without a UUID with a session ID in the coordinator for the all/focus modes, without making them selectable as a persistent destination.
- [x] Add proofs for Codable round-trip, all/focus, no display, unknown selection and a stable UUID with a new numeric ID; rerun the filter. The tests must check the public results, not duplicate the internal switch.
- [x] Record the diff of this tranche only; any commit must include only the feature's hunks.

## Task 2: Focus of the active window and fallback

**Files:** create `CascadeKit/Sources/CascadeKit/Core/Display/FocusedDisplayResolver.swift`, `FocusedWindowMonitor.swift`, `Tests/CascadeKitTests/FocusedDisplayResolverTests.swift`. Change `Core/Display/SafeAreaNotchDetector.swift`, `Core/Display/ActiveDisplayResolving.swift` and `Core/Events/MouseEventMonitor.swift`, removing the overlap between focus, inventory and pointer.

**Interfaces:** `FocusedWindowMonitoring` exposes `onChange: ((CGRect?) -> Void)?`, `start()` and `stop()`. The published frame is already in global AppKit coordinates. The concrete monitor observes the frontmost external app and its window; the pure resolver receives only values.

```swift
nonisolated enum FocusedDisplayResolver {
    static func resolve(
        window: CGRect?, pointer: CGPoint,
        frames: [CGDirectDisplayID: CGRect],
        previous: CGDirectDisplayID?, main: CGDirectDisplayID?
    ) -> CGDirectDisplayID?
}
```

- [x] Add the window/pointer conflict test.

```swift
@Test func focusedWindowWinsOverPointer() {
    let frames: [CGDirectDisplayID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 1000, height: 800),
        2: CGRect(x: -1000, y: 0, width: 1000, height: 800)
    ]
    #expect(FocusedDisplayResolver.resolve(
        window: CGRect(x: -900, y: 100, width: 600, height: 500),
        pointer: CGPoint(x: 500, y: 400), frames: frames,
        previous: 1, main: 1
    ) == 2)
    #expect(FocusedDisplayResolver.resolve(
        window: nil, pointer: CGPoint(x: 500, y: 400),
        frames: frames, previous: 2, main: 1
    ) == 1)
}
```

- [x] Run the `FocusedDisplayResolverTests` filter and verify the initial failure.
- [x] Implement maximum intersection, stable tie-break, fallback pointer → main → first sorted ID. Discard null, infinite or empty frames and frames without a positive intersection.
- [x] Observe app change, focused window change, move/resize, minimization and destruction of the window; remove the previous subscriptions. Coalesce the events, perform AX reads on the worker and discard responses from superseded generations. When Accessibility is revoked/absent, publish `nil` and use the fallback without opening repeated dialogs.
- [x] Reuse the existing permission-change path to reactivate the monitor when consent changes. The pointer is always observed for hover, but it updates the active display only if a valid focused frame is missing.
- [x] Test separately coordinate conversion with a monitor above/below/to the left, tied area, window change within the same app, move without the mouse, late callback and revoked permission. Inject the AX transport into the monitor for these proofs, without querying other apps in unit tests.
- [x] Run the tests again; verify on a real window that dragging it between monitors changes the result with the pointer then still. No periodic timer.

## Contract update after the 25 September audit

Visibility in task 3 uses `setVisibleActivities(_ activities: [any NotchActivity])`, with instance identity, instead of the plain set of IDs reported in the draft below. The expanded choice explicitly distinguishes no activity, fallback and selected activity. In task 4 the requests carry a cancellable token and the closing a generation: the real end of the morph is what counts. The satellite must stay on the compact copies of the other displays; the layout of the already expanded display stays the existing one. These amendments prevail over the initial fragments.

## Task 3: Shared selection and activity lifecycle

**Files:** change `CascadeKit/Sources/CascadeKit/Core/Activities/LiveActivityHost.swift`, `Tests/CascadeKitTests/LiveActivityHostTests.swift` and `Tests/CascadeKitTests/AddonPresentationTests.swift`. Temporarily update the single controller to the new interface to keep the tranche compilable.

**Interfaces:** the new internal `ActivitySelection` contains `primary`, `secondary`, `expanded` of type `(any NotchLiveActivity)?` and `notice: (any NotchTransientNotice)?`. `LiveActivityHost.selection` exposes it read-only; `setExpanded(_:activityID:)` keeps choosing the open activity. The new `setVisibleActivityIDs(_ ids: Set<String>)` governs the actual activation within the visible session; `setVisible(false)` stays reserved for global suspension/lock and not for removing a copy. `setVisible(true)` enables the session but activates only the identities of the union handed over by the coordinator.

- [x] In the same file as the existing `LiveFixture` fixtures, add the following test.

```swift
@Test @MainActor func copiesShareActivationUntilLastPresentationLeaves() {
    let host = LiveActivityHost()
    let music = LiveFixture("music")
    host.setVisible(true)
    host.present(music)
    host.setVisibleActivityIDs([music.id])
    host.setVisibleActivityIDs([music.id])
    #expect(music.activations == 1)
    host.setExpanded(true, activityID: music.id)
    #expect(host.selection.primary?.id == music.id)
    #expect(host.selection.expanded?.id == music.id)
    host.setVisibleActivityIDs([music.id])
    #expect(music.suspensions == 0)
    host.setVisibleActivityIDs([])
    #expect(music.suspensions == 1)
    host.stop()
}
```

- [x] Run `swift test --package-path CascadeKit --filter LiveActivityHostTests` with the `DEVELOPER_DIR` from task 1 and record the initial failure.
- [x] Separate the computation of `ActivitySelection` from the reconciliation of activations. The compact selection does not depend on `isExpanded`; notices do not clear the underlying live selection. Expansion keeps removing and suppressing notices according to the existing contract.
- [x] Compare the union of the actually visible identities with the current activations; for equal IDs also compare the instance to suspend the replaced one. `setVisibleActivityIDs` must not recursively emit `onChange` on every application of the same projection.
- [x] Keep a single expiry scheduler. Keep priority, two distinct sources, expanded fallback, invalidation by revision and revocation of the old contexts. An activity excluded from all presentations keeps metadata/expiry but no view resources.
- [x] Add proofs for compact primary/secondary while one is expanded, a single update observed by two copies, expiry while expanded, removal of one copy without suspension, instance replacement with the same ID and suspension on lock. With `SnapshotActivity`, the action stays valid while there is a presentation and is revoked after the last one; do not create a provider per display.
- [x] Rerun `LiveActivityHostTests` and `AddonPresentationTests`; adjust the old expectations only where the new contract requires the persistent compact selection.

## Task 4: Permanent panels and exclusive opening

**Files:** create `CascadeKit/Sources/CascadeKit/Core/Engine/NotchDisplayCoordinator.swift` and `Tests/CascadeKitTests/NotchDisplayCoordinatorTests.swift`. Change `Core/Engine/NotchEngine.swift`, `Core/Engine/NotchController.swift`, `Core/Events/EventMonitoring.swift` and `Tests/CascadeKitTests/NotchControllerTests.swift`.

**Interfaces:** `NotchDisplayCoordinator` has `start()`, `stop()`, `updatePreferences(_:)`, `requestExpansion(on: CGDirectDisplayID, activityID: String?)`, `requestCollapse(on:)`, `didFinishCollapse(on:)` and `expandedDisplayID: CGDirectDisplayID?`. The local controller receives `updateDisplay(_ display: ActiveDisplay)` and `applyPresentation(_:)`; it emits opening/closing requests and animation end. `DisplayPresentation` contains the references to the local content `primary`, `secondary`, `notice`, `expanded`, `showsWidgets: Bool` and the resolved style. The activities use the types from task 3.

- [x] Build coordinator fixtures with a fake inventory, fake focus and recording surfaces conforming to `NotchDisplayPresenting`. This protocol exposes the local methods above, `close(animated:)`, `stop()` and a closing-finished callback. Record created panels, frames, visible content and the sequence of transitions.
- [x] Write the sequential proof: connect A/B → two surfaces; open A → owner A; request B → A closing and B still compact; notify `didFinishCollapse(on: A)` → owner B; both surfaces still exist. The proof must check every transition, not only the final result.
- [x] Run the `NotchDisplayCoordinatorTests` filter, verifying the failure before the implementation.
- [x] Move inventory, focus, monitor, activity host and widget host to the coordinator. Each controller stays anchored to its own display; focus no longer calls `layoutPanel` on the existing panels. The display geometry update can call it. The product configuration always keeps the software chrome visible: the old `drawsChromeWithoutHardwareNotch` flag cannot turn off the silhouettes required by the new mode.
- [x] Implement the ownership handover according to this sequence; the animation's completion is a controller event, not a numeric delay.

```text
requestExpansion(B):
  if an interaction holds A: keep B while the trigger stays valid
  else if A exists and differs from B:
    pending = B; invalidate A's open controls; ask A to collapse
  else: assign B and present the content the routing allows
didFinishCollapse(A):
  release A and its expanded views
  if pending is still connected and the trigger is valid: open pending
  otherwise: all compact
```

- [x] Compute one `DisplayPresentation` per surface: activity only on the destinations; notice only on the active display; expanded content only on the owner. Remove the outgoing views/interactions, tell the host the union of the IDs of the new presentation and of the views still animating, then build the new views. `activate` must precede the factories: `SnapshotActivity` captures the action permission while building the view. At the end of the animation reduce the union again. A focus change between two copies of the same activity must not produce an intermediate empty set.
- [x] Closing controllers can remove their views, but they do not call the global `activityHost.stop()`, `setVisible(false)` or `setPresentationSuppressed`. Suppression during a morph is local. `WidgetHost` has a single expanded owner; empty/revoke the old view before mounting it on the new display.
- [x] Route pointer movement to the display under the pointer and to the previous/current owner to generate the exit; do not hit test every screen on every event. The released button always reaches the controller that owns the drag.
- [x] Test all/focus/fixed without recreating windows, fast A→B→C, the pointer leaving B before A closes, removal of A/B during the transition, popover/drag/settings, lock/unlock, stop and Reduce Motion. `stop()` removes all windows and stops the shared services only once.
- [x] Rerun the coordinator and controller tests. Do not change the spring algorithms or the provider priorities in this task.

## Task 5: Software notch and droplet Dynamic Island

**Files:** create `CascadeKit/Sources/CascadeKit/Models/Geometry/SoftwareNotchMetrics.swift`, `Extensions/CGPath+SoftwareNotchDroplet.swift`, `Tests/CascadeKitTests/SoftwareNotchGeometryTests.swift`. Change `Models/Geometry/NotchGeometry.swift`, `Models/Configuration/NotchConfiguration.swift`, `Core/Engine/NotchController.swift`, `Components/NotchHostView.swift`, `Models/Configuration/NotchActivityViewContext.swift` and `Cascade/Features/MediaLiveActivity.swift`.

**Interfaces:** `SoftwareNotchMetrics` exposes `restingSize`, `compactHeight`, `compactCenterGap`, `neckWidth`, `bodyOffset`. New vertical droplet geometry separate from `CGPath.notchDroplet`, which stays the activities' satellite.

```swift
nonisolated struct SoftwareNotchMetrics {
    let restingSize = CGSize(width: 96, height: 8)
    let compactHeight: CGFloat = 32
    let compactCenterGap: CGFloat = 24
    let neckWidth: CGFloat = 12
    let bodyOffset: CGFloat = 8
}
```

- [x] Write proofs on the three independent measurements and on the central width. For fake 200 pt hardware the reserve stays 200; for software it is 24 with identical side content dimensions. Verify both styles at rest with a 96 × 8 bounding box that includes the fillets, without accidentally adding the outer radii.
- [x] Run `SoftwareNotchGeometryTests` before the new implementation and observe the failure.
- [x] Replace the undifferentiated uses of `restingSize` in the controller: the resting trigger uses the bump; the compact layout uses the height and separation for activities; the expanded content uses the real hardware reserve or zero. Also update satellite, settings button, insets and the canvas computation.
- [x] Pass `hardwareNotchWidth: 0` on software, preserving the calibrated hardware value where it exists. Fix the `?? 200` fallback in `MediaLiveActivity` if necessary so that an explicit absence of hardware does not produce the old central gap. Do not shrink icons/fonts to obtain a smaller central space.
- [x] For Dynamic Island without an activity, interpolate the bump toward the vertical body and neck; Notch uses the shape connected to the edge. During a Live Activity use the same layout and path as the activities for both styles. An `expandedFallback` without a live session uses the droplet.
- [x] Make fill, glass, borders, mask, accessibility and hit testing consume the same path. Keep the satellite renderer and the Spotlight path. The top bump stays present even when the droplet body descends.
- [x] Apply the old calibrations only to hardware for this new software mode; keep the saved data. No destructive migrations. The size control must not impose the old 16 pt minimum on the new bump.
- [x] Test a finite path and content within the canvas at progress 0/0.5/1, initial/final frame, morph interruption, style change while open, activity arrival/end during the droplet, 1×/2× scales and a narrow display. No frame with content outside the mask, diverging path/hit test or a missing bump.
- [x] Run `SoftwareNotchGeometryTests`, `NotchGeometryTests`, `ContinuousNotchPathTests`, `NotchHostViewTests`, `NotchSizeCalibrationTests` and `NotchControllerTests`. Visually compare the initial values of the specification; any adjustments also update the specification.

## Task 6: Settings and auxiliary surfaces

**Files:** change `Cascade/CascadeServices.swift`, `Cascade/Features/Settings/CascadeSettingsView.swift`, `Cascade/Features/Settings/CascadeSettingsWindowController.swift`, `Cascade/Integrations/Spotlight/SpotlightCoordinator.swift`, `CascadeKit/Sources/CascadeKit/Core/Engine/NotchEngine.swift`, `CascadeTests/SettingsTests.swift`.

**Interfaces:** the engine exposes `setDisplayPreferences(_ preferences: DisplayPresentationPreferences)`, a descriptive list of the displays and a callback for its changes. `CascadeServices` persists the preferences from task 1 and provides bindings to the UI; no second authoritative cache. `expandedFrame` and `onExpandedFrameChanged` describe the opening owner, not the display that has just received focus.

- [x] Add the `.displayStyle` and `.activityDisplays` search cases and their tests before the UI: the terms "screen", "display", "notch", "Dynamic Island" and "activity" find the real controls.
- [x] Implement a Screens section in the Appearance page: rows with the display name and the Notch/Dynamic Island choice only when the hardware cut-out is missing. For hardware show the physical behavior without an inapplicable selector.
- [x] Add "Show Live Activities" with three options: "All screens", "Follow focus", "Specific screen". The monitor selector appears only for the third; an offline monitor stays listed as disconnected. Help text explains focus and fallback and that the silhouette stays on all screens.
- [x] Apply the preferences immediately, without relaunch, with normalization on load. The style change closes the affected surface before changing geometry; it does not interrupt the activities on the other surfaces.
- [x] Anchor settings, calibration and Spotlight to the invoking/opening display. Replace the pointer's autonomous selection in `SpotlightCoordinator` with an anchor provided by the services: the open display if present, otherwise the active display resolved by task 2. Its own focus, if any, must not transfer the anchor.
- [x] Keep the single arbitration for Spotlight too: the other silhouettes stay, a second expansion waits for the outer surface to close. If the display disappears, cancel the join and use the native restore already provided, without moving windows indiscriminately.
- [x] Verify persistence and search with `SettingsTests`; add a proof for settings open on B while the external focus moves to A, an offline fixed choice and same-name displays with different UUIDs. Use accessible labels that distinguish same-name rows.

## Task 7: Integrated verification, documentation and build

**Files:** update `docs/architecture/live-activity-contracts.md`; create `docs/superpowers/verification/2026-09-24-multi-display-notch.md` at execution time, recording the actual environment and proofs. Do not declare the verifications listed here as already performed.

- [x] Run all the CascadeKit tests once the tasks are finished: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path CascadeKit`.
- [x] Run the app tests with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/CascadeDevelopment" test -only-testing:CascadeTests/SettingsTests`.
- [x] Verify the following matrix on real monitors when available, recording every unavailable combination as not verified. The fakes demonstrate routing/state, not native panel stacking.

| Proof | Required result |
| --- | --- |
| Hardware + external, no activity | Two permanent silhouettes; external selectable in both styles |
| Two screens without hardware | Independent styles, same activity semantics |
| All, two activities, opening on A | Compact copies on B; a single open surface |
| Window focus on A, mouse on B | Compact activity on A; hover on B can open the widgets |
| Window move/window change within the same app | Activity follows the new display; panels do not move |
| Specific B; disconnection/reconnection of B | No copy on A; return to B with the same valid revision |
| A open, request B, then C | A closes before the new opening; last valid request |
| Live Activity arrival/expiry during a morph | Silhouette always present, consistent content, no resurrected activity |
| Lock/unlock, stop/start, lid closed | No orphaned window, services released, inventory updated |
| Fullscreen, Spaces, Mission Control, mirroring | Compact presence on the relevant desktop; no duplication of logical panels |
| Reduce Motion/Transparency, VoiceOver | Correct final geometry, same exclusivity, sensitive content protected |
| Settings, popover, Spotlight | Stable anchor and a single open interaction |

- [ ] Native qualification of the resources at rest: count of display links and TimelineView through profiling not performed. **Automatic part completed:** three copies share a single activation/expiry, focus does not reallocate panels and the morph/lock/Reduce Motion tests pass. The profiling limit is declared in the report and accepted as the boundary of the local delivery, without claiming a native measurement that does not exist.
- [x] Update the architecture contracts: permanent silhouettes, compact selection independent of expansion, shared lifecycle, meaning of notices and software measurements.
- [x] Run `scripts/build-development.sh`. Only after success verify the target of `/Applications/Cascade.app`, terminate the previous instance, reopen that path and verify the process/executable of the new instance.
- [x] In the final report distinguish automated tests, real proofs, unavailable combinations and relaunch results. Do not consider the build alone a multi-monitor verification.

**Delivery outcome, 26 September 2026:** implementation and reviews completed; signed build and relaunch verified. Settings suite 17/17; final full package run, exit 1 with the timeouts compared with the baseline in the [report](../verification/2026-09-24-multi-display-notch.md). The unavailable physical proofs and the profiling not performed stay explicitly unqualified.

## Completion criterion

Every requirement of the specification has a task: presence and opening → task 4; style/droplet/geometry → task 5; modes and persistence → tasks 1 and 6; confirmed focus → task 2; copy without provider duplication → task 3; qualification and relaunch → task 7. The work is complete only after verification of the transitions and of the replication, not after merely adding the selectors.
