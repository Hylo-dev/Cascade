# Task 88 — local shelf routing report

## Delivered behavior

- Added one public `NotchContextualPage` slot with stable ID, content revision, declared content height, accessibility label, and a context carrying the available render size.
- Added explicit engine registration and page-selection APIs. Occupied content is selected on the next ordinary opening; manual ordinary/contextual selection survives reconciliations, and an occupied-to-empty transition returns the active owner to its ordinary activity/widget page.
- Preserved explicit contextual selection through cross-display collapse handoff and reset selection/preview state on close, lock, stop, external suppression, and owner removal.
- Rendered contextual content through the existing notch geometry, clamped by `maximumActivityExpandedHeight`. The native two-segment chooser lives in the left header, keeps the settings gear, and labels the ordinary destination neutrally as `Activities`.
- Added a native `NSDraggingDestination` on `NotchHostView`. It admits an all-or-nothing batch of at most 32 regular local file URLs, requires copy support, excludes the physical cutout, rejects promise/mixed/directory offers with feedback, caches by drag sequence plus pasteboard change count, and revalidates a changed pasteboard at drop.
- Added gesture-bound native file-drag recognition to `MouseEventMonitor`. It inspects only fresh drag-pasteboard generations, emits one begin/end pair, recovers from a missing mouse-up, and performs no idle pasteboard polling.
- Routed recognized file drags only when the contextual page and drop handler are configured. The pointed display receives a finite double heartbeat and the existing `.drag` ownership hold; near-hover opens a temporary shelf preview, exit/failure restores the previous page, and a successful drop confirms the shelf.

## Public interface for task 89

```swift
public nonisolated struct NotchContextualPageContext: Sendable {
    public let availableSize: CGSize
    public init(availableSize: CGSize)
}

@MainActor
public protocol NotchContextualPage: AnyObject {
    var id: String { get }
    var contentRevision: UInt64 { get }
    var contentHeight: CGFloat { get }
    var accessibilityLabel: String { get }
    func makeContentView(in context: NotchContextualPageContext) -> AnyView
}

public extension NotchContextualPage {
    var accessibilityLabel: String { id }
}

@MainActor public final class NotchEngine {
    public func setContextualPage(
        _ page: (any NotchContextualPage)?,
        prefersDefault: Bool
    )
    public func showContextualPage(on displayID: CGDirectDisplayID? = nil)
    public func showOrdinaryPage(on displayID: CGDirectDisplayID? = nil)
    public func configureFileDrop(
        onHover: (@MainActor ([URL]?) -> Void)?,
        onDrop: (@MainActor ([URL]) -> Bool)?,
        onUnsupported: (@MainActor () -> Void)?
    )
}
```

`onHover` receives the currently admitted URL batch and receives `nil` on exit, rejection, or completion. `onDrop` is the final synchronous acceptance decision. Task 89 should keep the contextual page registered while empty and change only `prefersDefault` as shelf occupancy changes.

## Verification

All commands used the Xcode beta toolchain through `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

```text
swift test --filter 'MouseEventMonitorTests|NotchHostViewTests'
16 tests passed

swift test --filter NotchDisplayCoordinatorTests
52 tests passed

swift test --filter 'contextualPageUsesItsDeclaredHeightAndExistingMaximum|replacingAContextualPageInstanceWithTheSameIDAndRevisionRendersTheReplacement|recognizedFileDragRunsOneFiniteHeartbeatAndNearHoverRequestsDragExpansion'
3 tests passed
```

An additional combined four-suite run built successfully and passed 139 of 140 tests. The only failure was the existing one-second timeout in `controlDragKeepsExpandedContentAliveUntilMouseUp` while 140 main-actor tests were scheduled together; that exact test passed in the immediately preceding focused run. No app target was built or restarted because task 88 is limited to CascadeKit and the parent task explicitly reserved app integration for task 89.
