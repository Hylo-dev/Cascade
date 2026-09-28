# Task 88 preparation — local shelf routing

Scope is limited to `CascadeKit/Sources/CascadeKit` and focused `CascadeKitTests`. Task 87 owns persistence/copying; task 89 owns the app adapter, shelf composition, and outgoing drag. The contextual-pages proposal remains unapproved, so this increment adds one dedicated contextual slot and two-choice navigation, without a general pager, a third bubble, a fake Live Activity, or a Music fallback.

## Recommended contract

Add `Core/Pages/NotchContextualPage.swift`:

```swift
import CoreGraphics
import SwiftUI

public struct NotchContextualPageContext: Sendable {
    public let availableSize: CGSize
}

@MainActor
public protocol NotchContextualPage: AnyObject {
    var id: String { get }
    var contentRevision: UInt64 { get }
    var contentHeight: CGFloat { get }
    var accessibilityLabel: String { get }
    func makeContentView(in context: NotchContextualPageContext) -> AnyView
}
```

`availableSize` lets task 89 lay out the deck without another geometry API. `accessibilityLabel` supplies the native chooser title (`Ripiano`) and can default to `id`; it does not create a page model. `contentHeight` is finite-clamped through the existing `maximumActivityExpandedHeight` ceiling (240 points by default), using the current cutout and inset calculation rather than the widget height. Width remains the current `expandedHalfWidth` (220 per side).

Coordinator API:

```swift
func setContextualPage(_ page: (any NotchContextualPage)?, prefersDefault: Bool)
func showContextualPage(on displayID: CGDirectDisplayID? = nil)
func showDefaultPage(on displayID: CGDirectDisplayID? = nil)
```

The page remains registered while empty. `prefersDefault` is the occupied-state input: ordinary opening selects it only when true, while explicit selection and an accepted incoming drag can reveal it when false. Updating the same page/revision must reconcile content without changing the user's current page.

Keep one internal open-session selection (`automatic` or `contextual(id:)`). Initialize it when ownership is granted; preserve it through all reconciliations and page revisions; clear it only after real collapse completion, stop/lock, or owner removal. The existing `reconcilePresentations()` block that rewrites `activityHost.expansionSelection` must run only for `automatic`. This prevents a primary activity update from replacing a manually chosen shelf. A later opening re-evaluates `prefersDefault`, as required.

Extend `DisplayPresentation` with the selected contextual page and its revision. `isExpanded` includes that page; `visibleActivityRoots` remains unchanged. `NotchController` renders the contextual page before the activity/widget branches and includes page identity/revision in `LocalPresentationKey`. `WidgetHost` is open only when widgets are actually selected.

Add a small native page chooser in `NotchHostView`, placed in the existing top chrome to the left of the hardware cutout. It offers `Ripiano` and the current ordinary destination (`Musica` when an expanded activity exists, otherwise `Widget`), has a clear accessibility label/hint, and calls the explicit coordinator selection APIs. It must coexist with the settings button, not replace it, and must not add a footer or widen `hitPath` beyond the live notch silhouette.

## Incoming drag boundary

`NotchHostView` should register only `.fileURL` and implement `NSDraggingDestination`. Admission reads the current dragging pasteboard, accepts only regular local file URLs, rejects directories/text/file promises, and reports `.copy`. Generic callbacks are sufficient:

```swift
var acceptsFileDrop: (([URL]) -> Bool)?
var onFileDropEntered: (([URL]) -> Void)?
var onFileDropExited: (() -> Void)?
var performFileDrop: (([URL]) -> Bool)?
```

Entered/updated state must visibly distinguish accepted and rejected drops; exit, end, cancellation, lock, owner change, and external-surface presentation clear it. Task 89 wires these callbacks to the host and renderer.

The pre-entry heartbeat belongs to `MouseEventMonitor`, because `NSDraggingDestination` starts only after the cursor reaches the window. Recognize once per real left-button drag gesture from the current drag pasteboard, only when it contains file URLs; reset on mouse-up. Do not poll an idle pasteboard and do not treat text/window drags as files. Add a defaulted protocol hook (a setter method with a no-op `EventMonitoring` extension is the least disruptive option) so existing test monitors need not all grow storage.

The coordinator routes recognized drag state and subsequent pointer samples to the surface under the pointer while preserving the existing single-owner and `.drag` hold rules. `NotchController` gives a closed notch one finite double pulse, then uses the existing morph driver to settle; no `Timer` or perpetual animation. When the recognized drag reaches the narrow resting/near-hover zone, it requests expansion with `.drag`, explicitly selects the contextual page, and exposes the destination. Screen lock, an external overlay, calibration, cancellation, and owner transfer cancel the pulse/drop state. `hitTest` continues to use the animated `hitPath`, so adjacent sidebar space remains pass-through.

## Proposed files

- Add `CascadeKit/Sources/CascadeKit/Core/Pages/NotchContextualPage.swift`.
- Update `Core/Engine/NotchDisplayCoordinator.swift` for registration, open-session selection, explicit selection, projection, ownership/reset rules, and native-drag routing.
- Update `Core/Engine/NotchController.swift` for contextual sizing/rendering, chooser callbacks, finite heartbeat, and near-hover drag opening.
- Update `Components/NotchHostView.swift` for the native chooser and `NSDraggingDestination` callbacks/admission.
- Update `Core/Events/EventMonitoring.swift` and `MouseEventMonitor.swift` for gesture-bound file-drag recognition.
- Update `NotchDisplayCoordinatorTests.swift`, `NotchControllerTests.swift`, and `NotchHostViewTests.swift`; add a small `MouseEventMonitorTests.swift` only if the recognizer cannot be covered cleanly through an existing fixture.

## Focused checks

- Empty registered shelf leaves ordinary hover/click on Music or widgets; occupied shelf is default on the next opening.
- Manual switch to Music/widgets survives shelf revision/occupancy updates until close; the following opening re-evaluates the shelf default.
- Explicit shelf selection works while empty and does not mutate compact Live Activity selection.
- Contextual height clamps finite, oversized, NaN, and reduced-motion cases using the existing maximum.
- Chooser is keyboard/VoiceOver reachable, settings remains reachable, and both remain inside the live hit path.
- Only a fresh real file drag pulses; text, directory-only, promise-only, cancelled, and stale pasteboard cases do not.
- Pulse runs once per gesture and settles with the morph engine stopped; reduced motion applies the status without residual animation.
- Near-hover drag opens the shelf/drop target on the pointed display, respects single ownership across displays, and clears on exit, mouse-up, lock, external overlay, and collapse.

The known risky seam is `reconcilePresentations()`: its current owner-without-activity branch automatically selects the primary/fallback on every reconcile. Contextual/manual selection must guard that branch before any rendering work, otherwise shelf updates will appear correct briefly and then be replaced by Music or widgets.
