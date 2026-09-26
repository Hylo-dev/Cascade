//
//  NotchController.swift
//  CascadeKit
//

import AppKit
import Observation
import QuartzCore
import SwiftUI

/// NotchController renders and animates one panel anchored to one display.
///
/// Two layers of state live here on purpose:
///
/// - *Observed* state — `state` and `activeDisplay` — changes rarely (a side
///   opens, the active screen changes) and is what the widget/content layer
///   reacts to through Observation.
/// - *Per-frame* state — the springs, the views, the engines — is marked
///   `@ObservationIgnored` so morphing at 120 Hz does **not** invalidate any
///   SwiftUI view. The morph talks straight to the layer; SwiftUI only ever
///   hears about the discrete transitions.
@Observable
@MainActor
final class NotchController: NotchDisplayPresenting {

    private(set) var state        : NotchState = .closed
    private(set) var activeDisplay: ActiveDisplay?

    @ObservationIgnored
    var onExpandedFrameChanged: ((CGRect?) -> Void)?

    var onSettingsRequested: (() -> Void)? {
        get { hostView.onSettingsRequested }
        set { hostView.onSettingsRequested = newValue }
    }

    /// expandedFrame exposes the target silhouette in global AppKit coordinates,
    /// so an adjacent window never relies on the full-width overlay panel frame.
    var expandedFrame: CGRect? {
        guard isStarted, isPanelVisible, let display = activeDisplay else { return nil }
        return expandedRegion(for: display)
    }

    /// restingFrame exposes the actual compact silhouette in global AppKit
    /// coordinates. Auxiliary surfaces can share this anchor without deriving
    /// it from the full-width overlay window.
    var restingFrame: CGRect? {
        guard isStarted, isPanelVisible, let display = activeDisplay else { return nil }
        let size = restingSize(for: display)
        return CGRect(
            x     : display.frame.midX - size.width / 2,
            y     : display.frame.maxY - size.height,
            width : size.width,
            height: size.height
        )
    }

    @ObservationIgnored private let configuration: NotchConfiguration
    @ObservationIgnored private let morphEngine  : MorphEngineDriving
    @ObservationIgnored private let panel        : NotchPanel
    @ObservationIgnored private let hostView     : NotchHostView
    @ObservationIgnored private let windowPinner : WindowPinning
    @ObservationIgnored private let hoverFeedback: HoverFeedback
    @ObservationIgnored private let reducesMotion: () -> Bool
    @ObservationIgnored private let sizeCalibration: NotchSizeCalibration
    @ObservationIgnored private let softwareMetrics = SoftwareNotchMetrics()

    @ObservationIgnored private var leadingSpring : Spring
    @ObservationIgnored private var trailingSpring: Spring
    @ObservationIgnored private var compactSpring : Spring
    @ObservationIgnored private var heightSpring  : Spring
    @ObservationIgnored private var compactTrailingSpring: Spring
    @ObservationIgnored private var bubbleSpring: Spring
    @ObservationIgnored private var dragHeartbeatSpring: Spring
    @ObservationIgnored private var dragHeartbeatPhase = 0
    @ObservationIgnored private var isRecognizedFileDragActive = false
    @ObservationIgnored private var isAttachingSecondary = false
    @ObservationIgnored private var presentedActivityID: String?
    @ObservationIgnored private var presentedSecondaryActivityID: String?
    @ObservationIgnored private var isReplacingActivity = false
    @ObservationIgnored private var clickedOpen = false
    @ObservationIgnored private var hoverExitTask: Task<Void, Never>?
    @ObservationIgnored private var pendingExitPoint: CGPoint?

    /// Insets belong to the shared renderer rather than providers. Compact
    /// content remains readable inside a narrow wing, while expanded content
    /// clears the physical cutout and the rounded lower edge.
    @ObservationIgnored private let compactOuterInset     : CGFloat = 12
    @ObservationIgnored private let compactInnerInset     : CGFloat = 2
    @ObservationIgnored private let compactVerticalInset  : CGFloat = 6
    @ObservationIgnored private let expandedHorizontalInset: CGFloat = 20
    @ObservationIgnored private let expandedTopInset       : CGFloat = 4
    @ObservationIgnored private let expandedBottomInset    : CGFloat = 16
    @ObservationIgnored private let staleAccessoryWidth     : CGFloat = 18
    @ObservationIgnored private let openAccessoryWidth      : CGFloat = 76
    @ObservationIgnored private let hiddenExpandedHeight    : CGFloat = 40

    /// Slack (in points) added around the stay-open region. It absorbs pointer
    /// jitter at the edges and — crucially — extends the region past the very
    /// top of the screen: a half-open `CGRect` excludes its `maxY` edge, so
    /// without this the topmost pixel row would read as "outside" and snap the
    /// notch shut the moment the pointer reaches the screen edge.
    @ObservationIgnored private let hoverHysteresis: CGFloat = 8

    @ObservationIgnored private let widgetHost   : WidgetHost
    @ObservationIgnored private let activityHost : LiveActivityHost
    @ObservationIgnored private var fixedDisplay: ActiveDisplay
    @ObservationIgnored private var displayPresentation: DisplayPresentation?
    @ObservationIgnored private var presentationKey: LocalPresentationKey?
    @ObservationIgnored private var outgoingActivityRoots: [any NotchActivity] = []
    @ObservationIgnored private var retainsLiveActivityGeometry = false
    @ObservationIgnored private var pendingCollapseGeneration: UInt64?
    @ObservationIgnored private var localRequestGeneration: UInt64 = 0
    @ObservationIgnored private var pendingHoverGeneration: UInt64?
    @ObservationIgnored private var isApplyingCoordinatorPresentation = false

    @ObservationIgnored var onExpansionRequested: ((DisplayExpansionRequest) -> Void)?
    @ObservationIgnored var onExpansionCancelled: ((UInt64) -> Void)?
    @ObservationIgnored var onCollapseRequested: (() -> Void)?
    @ObservationIgnored var onCollapseFinished: ((UInt64) -> Void)?
    @ObservationIgnored var onInteractionHoldChanged: ((NotchInteractionKind, Bool) -> Void)?
    @ObservationIgnored var onDragOwnershipChanged: ((Bool) -> Void)?
    @ObservationIgnored var onRetainedActivityRootsChanged: (() -> Void)?
    @ObservationIgnored var onContextualPageRequested: (() -> Void)?
    @ObservationIgnored var onOrdinaryPageRequested: (() -> Void)?
    @ObservationIgnored var onFileDragHoverChanged: (([URL]?) -> Void)?
    @ObservationIgnored var onFileDrop: (([URL]) -> Bool)?
    @ObservationIgnored var onUnsupportedFileDrop: (() -> Void)?

    var retainedActivityRoots: [any NotchActivity] {
        let mounted = mountedActivityRoots
        let mountedIdentities = Set(mounted.map(ObjectIdentifier.init))
        return mounted + outgoingActivityRoots.filter {
            !mountedIdentities.contains(ObjectIdentifier($0))
        }
    }

    @ObservationIgnored private var isStarted           = false
    @ObservationIgnored private var isExternalSurfacePresented = false
    @ObservationIgnored private var isSettingsFocused = false
    @ObservationIgnored private var isPanelVisible      = false
    @ObservationIgnored private var isControlDragActive = false
    @ObservationIgnored private var dragReleaseTask     : Task<Void, Never>?
    @ObservationIgnored private var isSensitiveContentVisible = false
    @ObservationIgnored private var isReturningToBase = false
    @ObservationIgnored private var preferredCompactSideWidth: CGFloat = 0
    @ObservationIgnored private var baseBorderAppearance: NotchBorderAppearance = .neutral

    private struct LocalPresentationKey: Equatable {
        let primaryIdentity  : ObjectIdentifier?
        let primaryRevision  : UInt64?
        let secondaryIdentity: ObjectIdentifier?
        let secondaryRevision: UInt64?
        let noticeIdentity   : ObjectIdentifier?
        let noticeRevision   : UInt64?
        let expandedIdentity : ObjectIdentifier?
        let expandedRevision : UInt64?
        let expandedIsLiveActivity: Bool
        let showsWidgets     : Bool
        let contextualPageIdentity: ObjectIdentifier?
        let contextualPageID: String?
        let contextualPageRevision: UInt64?
        let contextualPageIsSelected: Bool
        let widgetContentRevision: UInt64
        let style            : ExternalNotchStyle
    }

    /// The previous pointer sample, so we can test the *segment* travelled since
    /// the last event — a fast flick can land samples on both sides of the small
    /// trigger band without ever sampling inside it.
    @ObservationIgnored private var lastPointer: CGPoint?

    /// Cached "is Mission Control showing" flag, updated on Space changes. It
    /// lets the hover path block opening with a cheap bool check instead of a
    /// window-list query on every open; it self-heals in `handlePointer`.
    @ObservationIgnored private var isMissionControlShowing = false

    init(
        configuration: NotchConfiguration,
        display      : ActiveDisplay,
        morphEngine  : MorphEngineDriving,
        panel        : NotchPanel,
        hostView     : NotchHostView,
        windowPinner : WindowPinning,
        hoverFeedback: HoverFeedback,
        sizeCalibration: NotchSizeCalibration,
        activityHost : LiveActivityHost,
        widgetHost   : WidgetHost,
        reducesMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    ) {
        self.configuration  = configuration
        self.morphEngine    = morphEngine
        self.panel          = panel
        self.hostView       = hostView
        self.windowPinner   = windowPinner
        self.hoverFeedback  = hoverFeedback
        self.reducesMotion  = reducesMotion
        self.sizeCalibration = sizeCalibration
        self.activityHost   = activityHost
        self.widgetHost     = widgetHost
        self.fixedDisplay   = display
        self.leadingSpring  = Spring(parameters: configuration.spring)
        self.trailingSpring = Spring(parameters: configuration.spring)
        self.compactSpring  = Spring(parameters: configuration.spring)
        self.heightSpring   = Spring(parameters: configuration.spring)
        self.compactTrailingSpring = Spring(parameters: configuration.spring)
        self.bubbleSpring = Spring(parameters: configuration.spring)
        self.dragHeartbeatSpring = Spring(parameters: configuration.spring)
        sizeCalibration.onChange = { [weak self] in self?.applySizeCalibrationPreview() }
        sizeCalibration.onFinish = { [weak self] in
            self?.finishSizeCalibrationPresentation()
            self?.onInteractionHoldChanged?(.calibration, false)
        }
        hostView.onContextualPageRequested = { [weak self] in self?.onContextualPageRequested?() }
        hostView.onOrdinaryPageRequested = { [weak self] in self?.onOrdinaryPageRequested?() }
        hostView.onFileDragHoverChanged = { [weak self] in self?.onFileDragHoverChanged?($0) }
        hostView.onFileDrop = { [weak self] in self?.onFileDrop?($0) ?? false }
        hostView.onUnsupportedFileDrop = { [weak self] in self?.onUnsupportedFileDrop?() }
    }

    // MARK: - Lifecycle

    /// Resolve the active display, place the panel, and start listening.
    func start() {

        guard !isStarted else {
            return
        }

        isStarted = true
        lastPointer = nil
        dragReleaseTask?.cancel()
        dragReleaseTask = nil

        hostView.setChromeColor(configuration.chromeColor)
        hostView.auxiliaryInteraction.onDismiss = { [weak self] in
            Task { @MainActor [weak self] in
                // Dismissal can originate in a state change or view teardown.
                // Re-evaluate only after that transaction has finished.
                await Task.yield()
                guard let self, self.isStarted, self.isPanelVisible,
                      let point = self.lastPointer else { return }
                self.handlePointer(at: point)
            }
        }
        hostView.auxiliaryInteraction.onActiveChanged = { [weak self] isActive in
            self?.onInteractionHoldChanged?(.popover, isActive)
        }

        refreshActiveDisplay()
        isPanelVisible = true
        renderCurrentFrame()
        renderContent()
        startMorphIfNeeded()
        presentPanel()
    }

    /// Hide the overlay and stop all observation and animation.
    func stop() {
        guard isStarted else {
            return
        }

        hostView.auxiliaryInteraction.onDismiss = nil
        hostView.auxiliaryInteraction.onActiveChanged = nil
        isStarted           = false
        isExternalSurfacePresented = false
        isSettingsFocused = false
        isPanelVisible      = false
        isControlDragActive = false
        dragReleaseTask?.cancel()
        dragReleaseTask = nil
        lastPointer = nil
        hoverFeedback.update(isHovering: false)
        morphEngine.stop()
        state = .closed
        isReturningToBase = false
        leadingSpring.snap(to: 0)
        trailingSpring.snap(to: 0)
        compactSpring.snap(to: 0)
        compactTrailingSpring.snap(to: 0)
        bubbleSpring.snap(to: 0)
        isAttachingSecondary = false
        presentedActivityID = nil
        presentedSecondaryActivityID = nil
        isReplacingActivity = false
        clickedOpen = false
        cancelHoverExit()
        hostView.auxiliaryInteraction.dismiss()
        heightSpring.snap(to: activeDisplay.map { Double(restingSize(for: $0).height) } ?? 0)
        outgoingActivityRoots.removeAll()
        retainsLiveActivityGeometry = false
        displayPresentation = nil
        presentationKey = nil
        pendingCollapseGeneration = nil
        pendingHoverGeneration = nil
        sizeCalibration.finish(save: false)
        hostView.setContent(AnyView(EmptyView()), frame: .zero, isVisible: false)
        hostView.clearActivityContent()
        hostView.setSettingsButton(frame: .zero, isVisible: false)
        hostView.setPageChooser(
            frame: .zero,
            isVisible: false,
            contextualLabel: "",
            ordinaryLabel: "",
            selectsContextual: false
        )
        onExpandedFrameChanged?(nil)
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    /// updateDisplay changes only this surface's fixed geometry. Focus changes
    /// never call it; inventory topology is the sole owner of panel placement.
    func updateDisplay(_ display: ActiveDisplay) {
        fixedDisplay = display
        guard isStarted else { return }
        let changed = activeDisplay != display
        activeDisplay = display
        guard changed else { return }
        sizeCalibration.finish(save: false)
        layoutPanel(for: display)
        heightSpring.snap(to: Double(morphTargets(for: display).height))
        renderContent()
        renderCurrentFrame()
        startMorphIfNeeded()
    }

    /// applyPresentation accepts a host-validated projection. The coordinator
    /// has already activated every provider before this method can call a view
    /// factory, including during same-ID replacement overlap.
    func applyPresentation(_ presentation: DisplayPresentation) {
        if shouldCloseBeforeApplyingStyle(presentation.style) {
            if pendingCollapseGeneration == nil {
                onCollapseRequested?()
            }
            return
        }
        let nextKey = localPresentationKey(for: presentation)
        let targetState: NotchState = presentation.isExpanded
            && pendingCollapseGeneration == nil ? .open : .closed
        if !targetState.isClosed {
            pendingHoverGeneration = nil
        }
        if presentationKey == nextKey,
           state == targetState {
            return
        }
        let previousRoots = mountedActivityRoots
        let incomingIdentities = Set(presentation.visibleActivityRoots.map(ObjectIdentifier.init))
        let outgoing = previousRoots.filter {
            !incomingIdentities.contains(ObjectIdentifier($0))
        }
        let outgoingWasLive = !outgoing.isEmpty
            && displayPresentation?.expandedIsLiveActivity == true

        displayPresentation = presentation
        presentationKey = nextKey
        if !outgoing.isEmpty, !reducesMotion() {
            outgoingActivityRoots = outgoing
            retainsLiveActivityGeometry = outgoingWasLive
            isReplacingActivity = true
            isReturningToBase = true
            onRetainedActivityRootsChanged?()
        } else if !outgoingActivityRoots.isEmpty {
            outgoingActivityRoots.removeAll()
            if !isReturningToBase {
                retainsLiveActivityGeometry = false
            }
            onRetainedActivityRootsChanged?()
        }

        let previousState = state
        isApplyingCoordinatorPresentation = true
        setState(targetState)
        isApplyingCoordinatorPresentation = false
        if state == previousState {
            renderContent()
        }
        renderCurrentFrame()
        startMorphIfNeeded()
    }

    private func shouldCloseBeforeApplyingStyle(
        _ style: ExternalNotchStyle
    ) -> Bool {
        guard let display = activeDisplay,
              !display.hasHardwareNotch,
              let currentStyle = displayPresentation?.style,
              currentStyle != style else { return false }
        return !state.isClosed
            || isReturningToBase
            || leadingSpring.value > 0
            || trailingSpring.value > 0
    }

    private func localPresentationKey(
        for presentation: DisplayPresentation
    ) -> LocalPresentationKey {
        LocalPresentationKey(
            primaryIdentity  : presentation.primary.map(ObjectIdentifier.init),
            primaryRevision  : presentation.primary?.contentRevision,
            secondaryIdentity: presentation.secondary.map(ObjectIdentifier.init),
            secondaryRevision: presentation.secondary?.contentRevision,
            noticeIdentity   : presentation.notice.map(ObjectIdentifier.init),
            noticeRevision   : presentation.notice?.contentRevision,
            expandedIdentity : presentation.expanded.map(ObjectIdentifier.init),
            expandedRevision : presentation.expanded?.contentRevision,
            expandedIsLiveActivity: presentation.expandedIsLiveActivity,
            showsWidgets     : presentation.showsWidgets,
            contextualPageIdentity: presentation.contextualPage.map(ObjectIdentifier.init),
            contextualPageID: presentation.contextualPage?.id,
            contextualPageRevision: presentation.contextualPage?.contentRevision,
            contextualPageIsSelected: presentation.contextualPageIsSelected,
            widgetContentRevision: presentation.widgetContentRevision,
            style            : presentation.style
        )
    }

    func discardRetainedActivityRoots(_ identities: Set<ObjectIdentifier>) {
        let remaining = outgoingActivityRoots.filter {
            !identities.contains(ObjectIdentifier($0))
        }
        guard remaining.count != outgoingActivityRoots.count else { return }
        outgoingActivityRoots = remaining
        hostView.clearActivityContent()
        presentationKey = nil
        onRetainedActivityRootsChanged?()
    }

    /// close starts local collapse and reports completion only from the morph's
    /// exact compact/base completion path, including reduced motion.
    func close(
        animated  : Bool,
        generation: UInt64
    ) {
        pendingCollapseGeneration = generation
        isApplyingCoordinatorPresentation = true
        setState(.closed)
        isApplyingCoordinatorPresentation = false
        startMorphIfNeeded()
    }

    func cancelClose() {
        guard pendingCollapseGeneration != nil else { return }
        pendingCollapseGeneration = nil
        isReturningToBase = false
        isReplacingActivity = false
        isApplyingCoordinatorPresentation = true
        setState(.open)
        isApplyingCoordinatorPresentation = false
        renderContent()
        startMorphIfNeeded()
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible {
            restoreAfterScreenUnlock()
        } else {
            hideForScreenLock()
        }
    }

    private var mountedActivityRoots: [any NotchActivity] {
        if let primary = displayedPrimaryActivity {
            if state.isClosed, let secondary = displayedSecondaryActivity {
                return [primary, secondary]
            }
            return [primary]
        }
        return []
    }

    /// Order the panel on screen and pin it into its SkyLight space. Pinning has
    /// to come after the panel is visible (it needs a valid `windowNumber`); we
    /// also call this on unlock, because hiding the window can drop its space
    /// membership and it must be re-pinned to stay anchored.
    private func presentPanel() {
        panel.orderFrontRegardless()
        windowPinner.pin(panel)
    }

    /// beginSizeCalibration freezes the bare compact silhouette while the user
    /// aligns it with the physical cutout. Live sessions retain their deadlines.
    func beginSizeCalibration() -> Bool {
        guard isStarted, isPanelVisible, let display = activeDisplay,
              display.hasHardwareNotch else { return false }
        sizeCalibration.begin(on: display, size: restingSize(for: display))
        return sizeCalibration.isActive
    }

    private func applySizeCalibrationPreview() {
        guard isStarted, isPanelVisible, let display = activeDisplay else { return }
        isReturningToBase = false
        state = .closed
        isControlDragActive = false
        dragReleaseTask?.cancel()
        dragReleaseTask = nil
        lastPointer = nil
        hoverFeedback.update(isHovering: false)
        morphEngine.stop()
        leadingSpring.snap(to: 0)
        trailingSpring.snap(to: 0)
        compactSpring.snap(to: 0)
        compactTrailingSpring.snap(to: 0)
        bubbleSpring.snap(to: 0)
        isAttachingSecondary = false
        presentedActivityID = nil
        presentedSecondaryActivityID = nil
        isReplacingActivity = false
        clickedOpen = false
        cancelHoverExit()
        hostView.auxiliaryInteraction.dismiss()
        heightSpring.snap(to: Double(restingSize(for: display).height))
        renderContent()
        renderCurrentFrame()
        panel.ignoresMouseEvents = true
    }

    private func finishSizeCalibrationPresentation() {
        guard isStarted, isPanelVisible, let display = activeDisplay else { return }
        lastPointer = nil
        heightSpring.snap(to: Double(restingSize(for: display).height))
        renderContent()
        renderCurrentFrame()
        startMorphIfNeeded()
    }

    /// displayedPrimaryActivity resolves only the root this local renderer is
    /// allowed to mount. Shared selection stays in the coordinator.
    private var displayedPrimaryActivity: (any NotchActivity)? {
        guard let displayPresentation else { return nil }
        if state.isClosed {
            return displayPresentation.notice ?? displayPresentation.primary
        }
        return displayPresentation.expanded
    }

    /// displayedSecondaryActivity is present only in the real compact layout.
    private var displayedSecondaryActivity: (any NotchLiveActivity)? {
        guard let displayPresentation else { return nil }
        guard state.isClosed, displayPresentation.notice == nil else { return nil }
        return displayPresentation.secondary
    }

    private var displayedContextualPage: (any NotchContextualPage)? {
        guard !state.isClosed,
              displayPresentation?.contextualPageIsSelected == true else { return nil }
        return displayPresentation?.contextualPage
    }

    /// Set whether accepted hover entries request AppKit haptic feedback.
    func setHapticsEnabled(_ isEnabled: Bool) {
        hoverFeedback.isEnabled = isEnabled
    }

    /// setBorderAppearance retains the latest status underneath a visible
    /// activity override. A network change never rebuilds content or starts a morph.
    func setBorderAppearance(_ appearance: NotchBorderAppearance) {
        guard baseBorderAppearance != appearance else { return }
        baseBorderAppearance = appearance
        updateBorderAppearance()
    }

    /// updateBorderAppearance resolves the visible provider on each discrete
    /// presentation change, so dismissal restores current rather than old state.
    private func updateBorderAppearance() {
        var appearance = baseBorderAppearance
        if isStarted, isPanelVisible, !isReturningToBase,
           let activity = displayedPrimaryActivity,
           activity.privacy != .sensitive || isSensitiveContentVisible {
            appearance = activity.borderAppearance ?? appearance
        }
        hostView.setBorderAppearance(appearance, animated: !reducesMotion() && isPanelVisible)
    }

    /// Reveal or redact sensitive provider content globally. Redaction rebuilds
    /// the shared surface without invoking any sensitive view factory.
    func setSensitiveContentVisible(_ isVisible: Bool) {
        guard isSensitiveContentVisible != isVisible else { return }
        isSensitiveContentVisible = isVisible
        // A retained satellite root may still be travelling into the expanded
        // surface. Redaction must revoke that old tree in the same transaction.
        if !isVisible { hostView.clearDetachedActivityContent() }
        renderContent()
        startMorphIfNeeded()
    }

    // MARK: - Active display

    /// Re-resolve which screen we follow; only re-place the panel when the
    /// screen actually changed — the coalescing the project insists on, so a
    /// mouse drifting within one screen never triggers window work.
    private func refreshActiveDisplay() {

        let display = fixedDisplay

        let didChange = display != activeDisplay

        if didChange { sizeCalibration.finish(save: false) }

        activeDisplay = display

        guard didChange else {
            return
        }

        layoutPanel(for: display)
        heightSpring.snap(to: Double(morphTargets(for: display).height))
        renderContent()
        // Moving to a narrower display must not leave the old absolute wing
        // width outside its new bounds, even while the display link was idle.
        let safeWidth = Double(compactExtension(for: display))
        if compactSpring.value > safeWidth { compactSpring.snap(to: safeWidth) }
        if compactTrailingSpring.value > safeWidth { compactTrailingSpring.snap(to: safeWidth) }
        renderCurrentFrame()
        startMorphIfNeeded()
    }

    /// Park the panel as a fixed band across the top of the active screen. The
    /// band is tall enough for a fully expanded notch, so it never resizes while
    /// morphing — only the layer path moves, which is cheap.
    private func layoutPanel(for display: ActiveDisplay) {

        let visualOutset = NotchBorderRenderer.visualOutset
        // Reserve overshoot in the fixed canvas, so even the tallest activity can bounce.
        let softwareDropletDepth = display.hasHardwareNotch
            ? 0
            : softwareMetrics.restingSize.height + softwareMetrics.bodyOffset
        let canvasHeight = ceil(
            max(
                normalizedMaximumExpandedHeight(),
                normalizedActivityMaximumHeight(),
                compactContentHeight(for: display),
                restingSize(for: display).height
            ) * 1.18 + softwareDropletDepth
        )
        let bandHeight = canvasHeight + visualOutset
        let frame      = CGRect(
            x     : display.frame.minX,
            y     : display.frame.maxY - bandHeight,
            width : display.frame.width,
            height: bandHeight
        )

        panel.setFrame(frame, display: true)
        hostView.frame = CGRect(
            x     : 0,
            y     : visualOutset,
            width : frame.width,
            height: canvasHeight
        )
    }

    /// setExternalSurfacePresented reserves the notch origin for a system-surface
    /// transition. Hover and clicks cannot expand a competing local surface.
    func setExternalSurfacePresented(_ isPresented: Bool) {
        guard isExternalSurfacePresented != isPresented else { return }
        isExternalSurfacePresented = isPresented
        lastPointer = nil
        if isPresented {
            isRecognizedFileDragActive = false
            dragHeartbeatPhase = 0
            dragHeartbeatSpring.snap(to: 0)
            cancelHoverExit()
            clickedOpen = false
            isControlDragActive = false
            hostView.auxiliaryInteraction.dismiss()
            hoverFeedback.update(isHovering: false)
            setState(.closed)
            panel.ignoresMouseEvents = true
        } else if isSettingsFocused, isStarted, isPanelVisible, !sizeCalibration.isActive {
            // A cancelled Spotlight handoff may never take keyboard focus away
            // from settings. Restore its expansion without waiting for re-focus.
            setState(.open, trigger: .settings)
        }
    }

    // MARK: - Interaction

    /// setSettingsFocused holds expansion for keyboard interaction, independent
    /// of hover. Releasing focus immediately re-evaluates the last pointer sample.
    func setSettingsFocused(_ isFocused: Bool) {
        guard isSettingsFocused != isFocused else { return }
        isSettingsFocused = isFocused
        cancelHoverExit()
        if isFocused {
            guard isStarted, isPanelVisible, !sizeCalibration.isActive,
                  !isExternalSurfacePresented else { return }
            setState(.open, trigger: .settings)
        } else {
            clickedOpen = false
            handlePointer(at: lastPointer ?? NSEvent.mouseLocation)
        }
    }

    /// Decide whether the pointer at `location` should open or close the notch.
    /// While closed we open when the pointer enters the resting trigger band;
    /// while open we close only when it leaves the *expanded* region, so sliding
    /// down into the open notch does not immediately snap it shut.
    func handlePointer(at location: CGPoint) {

        guard isStarted, isPanelVisible, !sizeCalibration.isActive, !isExternalSurfacePresented else {
            return
        }

        guard let display = activeDisplay else {
            lastPointer = location
            return
        }

        // Remember this sample for the next segment test, whatever we decide.
        defer {
            lastPointer = location
            updatePanelMouseInterception(at: location)
        }

        if isSettingsFocused {
            cancelHoverExit()
            return
        }

        hostView.auxiliaryInteraction.updatePointer(at: location)
        if hostView.auxiliaryInteraction.contains(location) {
            cancelHoverExit()
            return
        }

        // The control that received mouse-down must stay alive until AppKit has
        // delivered mouse-up. Drag samples still update the remembered pointer,
        // but they cannot collapse and replace its SwiftUI hosting root.
        guard !isControlDragActive else {
            return
        }

        if state.isClosed {
            if isRecognizedFileDragActive {
                let nearDropZone = restingTriggerZone(for: display)
                    .insetBy(dx: -18, dy: -12)
                if nearDropZone.intersects(segmentFrom: lastPointer ?? location, to: location) {
                    setState(.open, trigger: .drag)
                    return
                }
            }
            // Test the segment the pointer travelled since the last sample, not
            // just where it is now: a fast flick can skip clean over the small
            // trigger band between two events and never land inside it.
            // The detached circle is selected by click; crossing it must not
            // open the primary or consume the gap between the two silhouettes.
            if detachedBubbleFrame(for: display).contains(location), displayedSecondaryActivity != nil {
                return
            }
            let zone = restingTriggerZone(for: display)

            if let generation = pendingHoverGeneration {
                if !zone.contains(location) {
                    pendingHoverGeneration = nil
                    hoverFeedback.update(isHovering: false)
                    onExpansionCancelled?(generation)
                }
                return
            }

            if zone.intersects(segmentFrom: lastPointer ?? location, to: location) {

                // Don't let a hover re-open the notch while Mission Control is up
                // (that open/close fight with the space-change close is the
                // flicker). The cached flag keeps the common case a cheap bool;
                // only when it's set do we pay for a window-list re-check, which
                // also clears the flag once Mission Control has dismissed.
                if isMissionControlShowing {
                    isMissionControlShowing = isMissionControlActive()
                }

                if !isMissionControlShowing {
                    // Feedback belongs to the accepted entry and is synchronous.
                    // Keeping it before setState also keeps automatic activity
                    // updates completely outside the haptic path.
                    hoverFeedback.update(isHovering: true)
                    setState(.open)
                }
            }
        } else {
            // Inset negatively to grow the region, so the top screen edge and a
            // little slack around the island all count as "still hovering".
            let slack = clickedOpen ? CGFloat(20) : hoverHysteresis
            let stayOpen = expandedRegion(for: display)
                .insetBy(dx: -slack, dy: -slack)

            if stayOpen.contains(location) {
                cancelHoverExit()
            } else if clickedOpen {
                scheduleHoverExit(at: location)
            } else {
                hoverFeedback.update(isHovering: false)
                setState(.closed)
            }
        }
    }

    func setRecognizedFileDragActive(_ isActive: Bool, at point: CGPoint) {
        guard isStarted, isPanelVisible, !sizeCalibration.isActive,
              !isExternalSurfacePresented else { return }
        if isActive {
            guard !isRecognizedFileDragActive else {
                handlePointer(at: point)
                return
            }
            isRecognizedFileDragActive = true
            if state.isClosed, !reducesMotion() {
                dragHeartbeatPhase = 1
                dragHeartbeatSpring.snap(to: 0)
                startMorphIfNeeded()
            }
            handlePointer(at: point)
        } else {
            guard isRecognizedFileDragActive || dragHeartbeatPhase != 0 else { return }
            isRecognizedFileDragActive = false
            dragHeartbeatPhase = 0
            dragHeartbeatSpring.snap(to: 0)
            renderCurrentFrame()
        }
    }

    /// Keep interception alive through a control drag that began inside the
    /// animated path. Releasing the button immediately restores path-based
    /// routing at the current cursor position.
    func handlePointerButton(isPressed: Bool) {
        guard isStarted, isPanelVisible, !sizeCalibration.isActive, !isExternalSurfacePresented else {
            return
        }

        if isPressed {
            cancelHoverExit()
            if state.isClosed, !panel.ignoresMouseEvents, let display = activeDisplay,
               displayedSecondaryActivity != nil,
               detachedBubbleFrame(for: display).contains(lastPointer ?? NSEvent.mouseLocation) {
                expandSecondaryActivity()
            } else if !state.isClosed, !panel.ignoresMouseEvents {
                clickedOpen = true
            }
            dragReleaseTask?.cancel()
            dragReleaseTask = nil
            isControlDragActive = !panel.ignoresMouseEvents
            onDragOwnershipChanged?(isControlDragActive)
        } else {
            guard isControlDragActive else {
                updatePanelMouseInterception(at: lastPointer ?? NSEvent.mouseLocation)
                return
            }

            let releasePoint = lastPointer ?? NSEvent.mouseLocation
            dragReleaseTask?.cancel()
            dragReleaseTask = Task { [weak self] in
                // The local NSEvent monitor runs before the mouse-up reaches the
                // pressed SwiftUI control. Yielding keeps its root alive through
                // delivery, then applies the normal hover rule at release.
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.isControlDragActive = false
                self.onDragOwnershipChanged?(false)
                self.dragReleaseTask = nil
                self.handlePointer(at: releasePoint)
            }
        }
    }

    /// The top-center trigger band, in AppKit global coordinates. It exists
    /// whether or not a hardware notch is drawn there.
    private func restingTriggerZone(for display: ActiveDisplay) -> CGRect {

        let size = restingSize(for: display)
        let leading = max(0, CGFloat(compactSpring.value))
        let trailing = max(0, CGFloat(compactTrailingSpring.value))

        return CGRect(
            x     : display.frame.midX - size.width / 2 - leading,
            y     : display.frame.maxY - size.height,
            width : size.width + leading + trailing,
            height: size.height
        )
    }

    /// The fully expanded footprint, in AppKit global coordinates. Used as the
    /// "stay open" region so the notch only closes when the pointer truly
    /// leaves it.
    private func expandedRegion(for display: ActiveDisplay) -> CGRect {

        let halfWidth = effectiveExpandedHalfWidth(for: display)
        let dropletDepth = usesSoftwareDroplet(on: display)
            ? softwareMetrics.restingSize.height + softwareMetrics.bodyOffset
            : 0
        let height = expandedTargetHeight(for: display) + dropletDepth

        return CGRect(
            x     : display.frame.midX - halfWidth,
            y     : display.frame.maxY - height,
            width : halfWidth * 2,
            height: height
        )
    }

    /// Both pointer and accessibility activation use the same satellite selection.
    private func expandSecondaryActivity() {
        guard isStarted, isPanelVisible, state.isClosed, !sizeCalibration.isActive,
              !isExternalSurfacePresented, !isMissionControlShowing, let secondary = displayedSecondaryActivity else { return }
        cancelHoverExit()
        isAttachingSecondary = !reducesMotion()
        hoverFeedback.update(isHovering: true)
        setState(.open, activityID: secondary.id, trigger: .click)
        clickedOpen = true
    }

    /// The circle clears the physical notch by ten points, including its top corners.
    private func detachedBubbleFrame(for display: ActiveDisplay) -> CGRect {
        let centerGap = compactCenterGap(for: display)
        let height = compactContentHeight(for: display)
        let available = max(0, (display.frame.width - centerGap) / 2 - 10)
        let diameter = min(height, available)
        return CGRect(
            x     : display.frame.midX + centerGap / 2 + 10,
            y     : display.frame.maxY - height / 2 - diameter / 2,
            width : diameter,
            height: diameter
        )
    }

    private func cancelHoverExit() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        pendingExitPoint = nil
    }

    /// A clicked surface tolerates a brief excursion, with one cancellable deadline.
    private func scheduleHoverExit(at point: CGPoint) {
        pendingExitPoint = point
        guard hoverExitTask == nil else { return }
        hoverExitTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(280)) }
            catch { return }
            guard !Task.isCancelled, let self, let point = self.pendingExitPoint else { return }
            self.hoverExitTask = nil
            self.pendingExitPoint = nil
            guard !self.isSettingsFocused, !self.isControlDragActive,
                  !self.hostView.auxiliaryInteraction.contains(point) else { return }
            self.hoverFeedback.update(isHovering: false)
            self.setState(.closed)
        }
    }

    // MARK: - Spaces / Mission Control

    /// `activeSpaceDidChange` fires for *both* a desktop swipe and Mission
    /// Control opening, so we disambiguate by what is on screen: Mission Control
    /// (and Exposé / show-desktop) puts up a full-screen Dock-owned window, a
    /// plain swipe does not.
    ///
    /// - Mission Control → collapse, animated (the mouse-leave that normally
    ///   closes the notch never arrives while the overview holds the events).
    /// - Plain swipe → do nothing: the notch stays open and anchored, because
    ///   the panel joins all Spaces and is stationary. (We deliberately do *not*
    ///   re-order the panel here — doing that on every fire is what made it
    ///   flicker.)
    func handleSpaceChange() {

        isMissionControlShowing = isMissionControlActive()

        guard isMissionControlShowing else {
            return
        }

        sizeCalibration.finish(save: false)
        setState(.closed)
        hoverFeedback.update(isHovering: false)
        lastPointer = nil
    }

    /// Whether Mission Control / Exposé / show-desktop is currently on screen.
    ///
    /// Those overviews are drawn by the Dock (or WindowManager) as a window
    /// roughly the size of the whole display; a normal desktop swipe puts up no
    /// such window. We match on owner + bounds — never window *names* — and
    /// exclude desktop elements (the wallpaper is also full-screen), so this
    /// needs no screen-recording permission and won't false-positive on the
    /// desktop.
    private func isMissionControlActive() -> Bool {

        guard let display = activeDisplay else {
            return false
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let minWidth  = display.frame.width  * 0.9
        let minHeight = display.frame.height * 0.9

        for window in windows {

            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == "Dock" || owner == "WindowManager" else {
                continue
            }

            guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            if bounds.width >= minWidth, bounds.height >= minHeight {
                return true
            }
        }

        return false
    }

    // MARK: - State & morph

    /// Apply a new discrete state and make sure the morph engine is running to
    /// animate toward it. Starting the engine is idempotent.
    private func setState(
        _ newState: NotchState,
        activityID: String? = nil,
        trigger   : DisplayExpansionTrigger = .hover
    ) {

        if !isApplyingCoordinatorPresentation {
            guard let displayID = activeDisplay?.displayID else { return }
            if newState.isClosed {
                if let generation = pendingHoverGeneration {
                    pendingHoverGeneration = nil
                    onExpansionCancelled?(generation)
                } else {
                    onExpansionCancelled?(localRequestGeneration)
                }
                onCollapseRequested?()
            } else {
                localRequestGeneration &+= 1
                pendingHoverGeneration = trigger == .hover ? localRequestGeneration : nil
                onExpansionRequested?(DisplayExpansionRequest(
                    displayID : displayID,
                    activityID: activityID,
                    trigger   : trigger,
                    generation: localRequestGeneration
                ))
            }
            return
        }

        guard newState != state else {
            return
        }

        cancelHoverExit()
        if newState.isClosed {
            clickedOpen = false
            hostView.auxiliaryInteraction.dismiss()
        }
        isReturningToBase = !reducesMotion() && (isReplacingActivity
            || (newState.isClosed && displayedPrimaryActivity is any NotchLiveActivity))
        state = newState
        renderContent()
        startMorphIfNeeded()
    }

    private func startMorphIfNeeded() {

        guard isStarted, isPanelVisible, !sizeCalibration.isActive else {
            morphEngine.stop()
            return
        }

        let targets = morphTargets()

        if reducesMotion() {
            finishReturnToBaseIfNeeded()
            let targets = morphTargets()
            leadingSpring.snap(to: targets.leading)
            trailingSpring.snap(to: targets.trailing)
            compactSpring.snap(to: targets.compact)
            compactTrailingSpring.snap(to: targets.compactTrailing)
            bubbleSpring.snap(to: targets.bubble)
            if targets.bubble == 0 {
                isAttachingSecondary = false
                hostView.clearDetachedActivityContent()
            }
            heightSpring.snap(to: Double(targets.height))
            dragHeartbeatPhase = 0
            dragHeartbeatSpring.snap(to: 0)
            morphEngine.stop()
            renderCurrentFrame()
            finishCoordinatorCollapseIfNeeded()
            return
        }

        guard !leadingSpring.isSettled(at: targets.leading)
           || !trailingSpring.isSettled(at: targets.trailing)
           || !compactSpring.isSettled(at: targets.compact)
           || !compactTrailingSpring.isSettled(at: targets.compactTrailing)
           || !bubbleSpring.isSettled(at: targets.bubble)
           || !heightSpring.isSettled(at: Double(targets.height))
           || dragHeartbeatPhase != 0
           || !dragHeartbeatSpring.isSettled(at: dragHeartbeatTarget) else {
            if isReturningToBase {
                finishReturnToBaseIfNeeded()
                startMorphIfNeeded()
            }
            return
        }

        guard !morphEngine.isRunning else {
            return
        }

        morphEngine.start { [weak self] dt in
            self?.advanceMorph(dt: dt)
        }
    }

    /// One morph frame: step both springs toward their targets, render, and —
    /// once everything has settled — stop the engine so the notch costs nothing
    /// while idle.
    private func advanceMorph(dt: CFTimeInterval) {

        guard isStarted, isPanelVisible else {
            morphEngine.stop()
            return
        }

        let targets = morphTargets()

        if reducesMotion() {
            finishReturnToBaseIfNeeded()
            let targets = morphTargets()
            leadingSpring.snap(to: targets.leading)
            trailingSpring.snap(to: targets.trailing)
            compactSpring.snap(to: targets.compact)
            compactTrailingSpring.snap(to: targets.compactTrailing)
            bubbleSpring.snap(to: targets.bubble)
            if targets.bubble == 0 {
                isAttachingSecondary = false
                hostView.clearDetachedActivityContent()
            }
            heightSpring.snap(to: Double(targets.height))
            dragHeartbeatPhase = 0
            dragHeartbeatSpring.snap(to: 0)
            renderCurrentFrame()
            morphEngine.stop()
            finishCoordinatorCollapseIfNeeded()
            return
        }

        // Only a closing axis meets the solid resting contour. Opening and
        // adaptive resizing retain their free spring and interruption velocity.
        leadingSpring.advance(
            toward    : targets.leading,
            dt        : dt,
            lowerBound: targets.leading == 0 ? 0 : nil
        )
        trailingSpring.advance(
            toward    : targets.trailing,
            dt        : dt,
            lowerBound: targets.trailing == 0 ? 0 : nil
        )
        compactSpring.advance(
            toward    : targets.compact,
            dt        : dt,
            lowerBound: targets.compact == 0 ? 0 : nil
        )
        compactTrailingSpring.advance(
            toward    : targets.compactTrailing,
            dt        : dt,
            lowerBound: targets.compactTrailing == 0 ? 0 : nil
        )
        bubbleSpring.advance(toward: targets.bubble, dt: dt)
        dragHeartbeatSpring.advance(toward: dragHeartbeatTarget, dt: dt)
        heightSpring.advance(
            toward    : Double(targets.height),
            dt        : dt,
            lowerBound: state.isClosed || isReturningToBase ? Double(targets.height) : nil
        )

        renderCurrentFrame()

        // Contact still carries outward velocity. Let that visible rebound
        // settle before revealing compact content or shutting the link down.
        // Point-valued axes can finish below a tenth of a point; waiting for a
        // thousandth would leave an invisible pause before compact content.
        let basePointThreshold: Double? = isReturningToBase ? 0.1 : nil
        let settled = leadingSpring.isSettled(at: targets.leading)
            && trailingSpring.isSettled(at: targets.trailing)
            && compactSpring.isSettled(at: targets.compact, threshold: basePointThreshold)
            && compactTrailingSpring.isSettled(at: targets.compactTrailing, threshold: basePointThreshold)
            && bubbleSpring.isSettled(at: targets.bubble)
            && heightSpring.isSettled(at: Double(targets.height), threshold: basePointThreshold)
            && dragHeartbeatSpring.isSettled(at: dragHeartbeatTarget)
        if settled {

            if advanceDragHeartbeatPhase() {
                renderCurrentFrame()
                return
            }

            leadingSpring.snap(to: targets.leading)
            trailingSpring.snap(to: targets.trailing)
            compactSpring.snap(to: targets.compact)
            compactTrailingSpring.snap(to: targets.compactTrailing)
            bubbleSpring.snap(to: targets.bubble)
            if targets.bubble == 0 {
                isAttachingSecondary = false
                hostView.clearDetachedActivityContent()
            }
            heightSpring.snap(to: Double(targets.height))

            renderCurrentFrame()
            if isReturningToBase {
                // This frame draws the exact bare notch with empty content.
                // The next display-link frame starts widening the compact wings.
                finishReturnToBaseIfNeeded()
            } else {
                morphEngine.stop()
                finishCoordinatorCollapseIfNeeded()
            }
        }
    }

    private var dragHeartbeatTarget: Double {
        dragHeartbeatPhase == 1 || dragHeartbeatPhase == 3 ? 1 : 0
    }

    private func advanceDragHeartbeatPhase() -> Bool {
        guard dragHeartbeatPhase != 0 else { return false }
        dragHeartbeatSpring.snap(to: dragHeartbeatTarget)
        if dragHeartbeatPhase == 4 {
            dragHeartbeatPhase = 0
            dragHeartbeatSpring.snap(to: 0)
            return false
        }
        dragHeartbeatPhase += 1
        return true
    }

    private func finishReturnToBaseIfNeeded() {
        guard isReturningToBase else { return }
        isReturningToBase = false
        isReplacingActivity = false
        if pendingCollapseGeneration == nil {
            releaseOutgoingActivityRoots()
            renderContent()
        } else {
            renderContent()
            finishCoordinatorCollapseIfNeeded()
        }
    }

    private func releaseOutgoingActivityRoots() {
        let releasedRoots = !outgoingActivityRoots.isEmpty
        outgoingActivityRoots.removeAll()
        retainsLiveActivityGeometry = false
        if releasedRoots {
            onRetainedActivityRootsChanged?()
        }
    }

    /// finishCoordinatorCollapseIfNeeded emits only after the controller has
    /// reached a non-expanded geometry and released every expanded root.
    private func finishCoordinatorCollapseIfNeeded() {
        guard state.isClosed,
              !isReturningToBase,
              let generation = pendingCollapseGeneration else {
            return
        }
        pendingCollapseGeneration = nil
        let releasedOutgoingRoots = !outgoingActivityRoots.isEmpty
        outgoingActivityRoots.removeAll()
        retainsLiveActivityGeometry = false
        onCollapseFinished?(generation)
        if releasedOutgoingRoots {
            onRetainedActivityRootsChanged?()
        }
    }

    /// morphTargets keeps side expansion, compact wings, satellite and height
    /// on one display link, preserving their velocities across interruptions.
    private func morphTargets() -> (leading: Double, trailing: Double, compact: Double, compactTrailing: Double, bubble: Double, height: CGFloat) {
        guard let display = activeDisplay else {
            return (0, 0, 0, 0, 0, 0)
        }
        return morphTargets(for: display)
    }

    private func morphTargets(
        for display: ActiveDisplay
    ) -> (leading: Double, trailing: Double, compact: Double, compactTrailing: Double, bubble: Double, height: CGFloat) {
        if isReturningToBase { return (0, 0, 0, 0, 0, restingSize(for: display).height) }
        return (
            leading : state.contains(.leading) ? 1 : 0,
            trailing: state.contains(.trailing) ? 1 : 0,
            compact : state.isClosed && !isReturningToBase && displayedPrimaryActivity != nil
                ? Double(compactExtension(for: display)) : 0,
            compactTrailing: state.isClosed && displayedPrimaryActivity != nil && displayedSecondaryActivity == nil
                ? Double(compactExtension(for: display)) : 0,
            bubble: state.isClosed && displayedSecondaryActivity != nil ? 1 : 0,
            height  : state.isClosed && displayedPrimaryActivity != nil
                ? compactContentHeight(for: display)
                : (state.isClosed ? restingSize(for: display).height : expandedTargetHeight(for: display))
        )
    }

    /// Resolve the current geometry from the springs and hand it to the host
    /// view. Cheap and allocation-light, safe to call every frame.
    private func renderCurrentFrame() {

        guard let display = activeDisplay else {
            return
        }

        let resting = restingSize(for: display)
        let maximumHeight = max(
            resting.height,
            compactContentHeight(for: display),
            normalizedMaximumExpandedHeight(),
            normalizedActivityMaximumHeight()
        )
        let renderedHeight = min(
            maximumHeight * 1.18,
            max(resting.height, CGFloat(heightSpring.value))
        )

        // Hardware and calibrated widths include the upper corner attachments.
        // The path adds those outside its straight sides, so reserve their span
        // inside the compact footprint instead of widening past the cutout.
        let restingAttachment = max(
            0,
            min(configuration.restingTopCornerRadius, resting.height / 2, resting.width / 2)
        )
        let compactWidth = Double(compactExtension(for: display))
        let compactProgress = compactWidth > 0
            ? min(1, max(0, max(compactSpring.value, compactTrailingSpring.value) / compactWidth))
            : 0

        let resolved = NotchGeometry.resolve(
            configuration           : configuration,
            restingHalfWidth        : resting.width / 2 - restingAttachment,
            restingHeight           : resting.height,
            compactLeadingExtension : max(0, CGFloat(compactSpring.value)),
            compactTrailingExtension: max(0, CGFloat(compactTrailingSpring.value)),
            compactCenterHalfWidth  : display.hasHardwareNotch
                ? resting.width / 2 - restingAttachment
                : compactCenterGap(for: display) / 2,
            compactProgress         : CGFloat(compactProgress),
            expandedHalfWidth       : effectiveExpandedHalfWidth(for: display),
            resolvedHeight          : renderedHeight,
            leadingProgress         : max(0, CGFloat(leadingSpring.value)),
            trailingProgress        : max(0, CGFloat(trailingSpring.value))
        )

        let safeExtent = max(0, display.frame.width / 2 - resolved.topCornerRadius)
        let heartbeat = max(0, CGFloat(dragHeartbeatSpring.value))
        let geometry = NotchGeometry(
            leftExtent        : min(safeExtent, resolved.leftExtent + heartbeat * 5),
            rightExtent       : min(safeExtent, resolved.rightExtent + heartbeat * 5),
            height            : resolved.height + heartbeat * 3,
            bottomCornerRadius: resolved.bottomCornerRadius,
            topCornerRadius   : resolved.topCornerRadius
        )
        sizeCalibration.update(geometry: geometry)

        // Compact content earns only a faint edge. Spring progress returns it
        // to zero with the wings, keeping the bare hardware notch unoutlined.
        let expandedBorderOpacity = min(1, max(0, leadingSpring.value, trailingSpring.value))
        let compactBorderOpacity = compactWidth > 0
            ? min(1, max(0, compactSpring.value / compactWidth)) * 0.12
            : 0

        // The notch hangs from the top of the host view; in the view's own
        // (non-flipped) coordinates that is `bounds.maxY`, centered.
        hostView.apply(
            geometry       : geometry,
            centerX        : hostView.bounds.midX,
            topY           : hostView.bounds.maxY,
            isChromeVisible: shouldDrawChrome(for: display),
            borderOpacity  : CGFloat(max(expandedBorderOpacity, compactBorderOpacity)),
            materialProgress: CGFloat(expandedBorderOpacity),
            detachedFrame  : detachedBubbleFrame(for: display).offsetBy(
                dx: -display.frame.minX,
                dy: hostView.bounds.maxY - display.frame.maxY
            ),
            detachedProgress: max(0, CGFloat(bubbleSpring.value)),
            isAttaching    : isAttachingSecondary,
            softwareDroplet: usesSoftwareDroplet(on: display),
            dropletProgress: max(
                0,
                min(1, CGFloat(max(leadingSpring.value, trailingSpring.value)))
            ),
            softwareMetrics: softwareMetrics
        )

        if let lastPointer {
            updatePanelMouseInterception(at: lastPointer)
        }
    }

    /// The resting size: the measured hardware notch where one exists, the
    /// configured fallback band where it does not.
    private func restingSize(for display: ActiveDisplay) -> CGSize {
        guard display.hasHardwareNotch else { return softwareMetrics.restingSize }
        return sizeCalibration.size(for: display) ?? display.notch.size
    }

    private func compactContentHeight(for display: ActiveDisplay) -> CGFloat {
        display.hasHardwareNotch ? restingSize(for: display).height : softwareMetrics.compactHeight
    }

    private func compactCenterGap(for display: ActiveDisplay) -> CGFloat {
        display.hasHardwareNotch ? restingSize(for: display).width : softwareMetrics.compactCenterGap
    }

    private func usesSoftwareDroplet(on display: ActiveDisplay) -> Bool {
        guard !display.hasHardwareNotch,
              displayPresentation?.style == .dynamicIsland,
              !displayPresentationIsShowingLiveActivity else { return false }
        return !state.isClosed || leadingSpring.value > 0 || trailingSpring.value > 0
    }

    private var displayPresentationIsShowingLiveActivity: Bool {
        guard let displayPresentation else { return false }
        if displayPresentation.expandedIsLiveActivity || retainsLiveActivityGeometry {
            return true
        }
        return state.isClosed && displayedPrimaryActivity != nil
    }

    /// Bound provider and configuration numbers before they reach geometry.
    /// A NaN or infinity from third-party content must never poison the shape.
    private func normalizedMaximumExpandedHeight() -> CGFloat {
        configuration.expandedHeight.isFinite
            ? max(0, configuration.expandedHeight)
            : 0
    }

    private func normalizedActivityMaximumHeight() -> CGFloat {
        configuration.maximumActivityExpandedHeight.isFinite
            ? max(0, configuration.maximumActivityExpandedHeight)
            : normalizedMaximumExpandedHeight()
    }

    private func declaredExpandedContentHeight(for activity: any NotchActivity) -> CGFloat {
        if activity.privacy == .sensitive, !isSensitiveContentVisible {
            return hiddenExpandedHeight
        }

        let declared = activity.expandedContentHeight
        return declared.isFinite ? max(0, declared) : 0
    }

    private func expandedTargetHeight(for display: ActiveDisplay) -> CGFloat {
        let resting = restingSize(for: display)
        if let page = displayedContextualPage {
            let declared = page.contentHeight
            let contentHeight = declared.isFinite ? max(0, declared) : 0
            let hardwareNotchHeight = display.hasHardwareNotch ? resting.height : 0
            let requested = hardwareNotchHeight
                + expandedTopInset + expandedBottomInset + contentHeight
            return max(resting.height, min(normalizedActivityMaximumHeight(), requested))
        }
        guard let activity = displayedPrimaryActivity else {
            return max(resting.height, normalizedMaximumExpandedHeight())
        }

        let hardwareNotchHeight = display.hasHardwareNotch ? resting.height : 0
        let requested = hardwareNotchHeight
            + expandedTopInset + expandedBottomInset
            + declaredExpandedContentHeight(for: activity)
        return max(resting.height, min(normalizedActivityMaximumHeight(), requested))
    }

    private func effectiveExpandedHalfWidth(for display: ActiveDisplay) -> CGFloat {
        let edgeSafeHalfWidth = max(0, display.frame.width / 2 - 12)
        let configured = configuration.expandedHalfWidth.isFinite
            ? max(0, configuration.expandedHalfWidth)
            : 0
        return min(configured, edgeSafeHalfWidth)
    }

    private func compactExtension(for display: ActiveDisplay) -> CGFloat {
        let available = max(0, (display.frame.width - compactCenterGap(for: display)) / 2)
        return min(preferredCompactSideWidth, available)
    }

    /// Cache provider sizing on discrete content changes; the animation reads
    /// only a number and never calls provider getters or allocates an array.
    private func updatePreferredCompactSideWidth() {
        let configured = configuration.compactActivityExtension.isFinite
            ? max(0, configuration.compactActivityExtension)
            : 0
        let activities = [displayedPrimaryActivity].compactMap { $0 }
        var preferred: CGFloat = 0
        for activity in activities {
            var width = configured
            if activity.privacy != .sensitive || isSensitiveContentVisible,
               let requested = activity.compactPreferredSideWidth,
               requested.isFinite, requested > 0 {
                width = min(160, requested)
            }
            preferred = max(preferred, width)
        }
        // The configured width is a fallback, not a minimum. The satellite
        // uses the resting height as its diameter and never widens the main wing.
        preferredCompactSideWidth = activities.isEmpty ? configured : preferred
    }

    /// Whether to draw the chrome on this display. Hardware notches always draw;
    /// the configuration decides whether external displays use the fallback
    /// compact notch (enabled by the default configuration).
    private func shouldDrawChrome(for display: ActiveDisplay) -> Bool {
        true
    }

    /// Show the widgets inside the open notch and hide them when it closes.
    ///
    /// The content lives in its own hosting view above the chrome, placed in the
    /// expanded interior and inset so it sits inside the rounded shape. It is a
    /// discrete swap on state change — not part of the per-frame morph loop — so
    /// it never touches the 120 Hz path.
    private func renderContent() {

        updateBorderAppearance()
        updatePreferredCompactSideWidth()
        onExpandedFrameChanged?(expandedFrame)
        hostView.setSettingsButton(frame: .zero, isVisible: false)
        hostView.setPageChooser(
            frame: .zero,
            isVisible: false,
            contextualLabel: "",
            ordinaryLabel: "",
            selectsContextual: false
        )

        guard isStarted, isPanelVisible, !isReturningToBase, !sizeCalibration.isActive,
              let display = activeDisplay else {
            hostView.setContent(AnyView(EmptyView()), frame: .zero, isVisible: false)
            hostView.clearActivityContent()
            return
        }

        presentedActivityID = displayedPrimaryActivity.map { $0.sourceID + ":" + $0.id }
        presentedSecondaryActivityID = displayedSecondaryActivity.map { $0.sourceID + ":" + $0.id }
        let resting = restingSize(for: display)
        let centerX = hostView.bounds.midX
        let topY    = hostView.bounds.maxY
        let dropletDepth = usesSoftwareDroplet(on: display)
            ? softwareMetrics.restingSize.height + softwareMetrics.bodyOffset
            : 0
        let contentTopY = topY - dropletDepth
        let hardwareNotchWidth = display.hasHardwareNotch ? resting.width : 0
        let hardwareNotchHeight = display.hasHardwareNotch ? resting.height : 0
        hostView.setFileDropExclusionFrame(display.hasHardwareNotch ? CGRect(
            x: centerX - resting.width / 2,
            y: topY - resting.height,
            width: resting.width,
            height: resting.height
        ) : .zero)

        if !state.isClosed {
            let buttonSize: CGFloat = 28
            let rightEdge = centerX + effectiveExpandedHalfWidth(for: display) - 12
            hostView.setSettingsButton(
                frame    : CGRect(
                    x     : rightEdge - buttonSize,
                    y     : contentTopY - max(hardwareNotchHeight, buttonSize),
                    width : buttonSize,
                    height: buttonSize
                ),
                isVisible: rightEdge - buttonSize >= centerX + hardwareNotchWidth / 2
            )
            if let page = displayPresentation?.contextualPage {
                let leftEdge = centerX - effectiveExpandedHalfWidth(for: display) + 12
                let rightLimit = centerX - hardwareNotchWidth / 2 - 8
                let chooserWidth = min(104, max(0, rightLimit - leftEdge))
                hostView.setPageChooser(
                    frame: CGRect(
                        x: leftEdge,
                        y: contentTopY - max(hardwareNotchHeight, buttonSize),
                        width: chooserWidth,
                        height: buttonSize
                    ),
                    isVisible: chooserWidth >= 72,
                    contextualLabel: page.accessibilityLabel,
                    ordinaryLabel: "Attività",
                    selectsContextual: displayPresentation?.contextualPageIsSelected == true
                )
            }
        }

        if state.isClosed {
            hostView.setContent(AnyView(EmptyView()), frame: .zero, isVisible: false)

            guard let activity = displayedPrimaryActivity else {
                hostView.clearActivityContent()
                return
            }

            let extensionWidth = compactExtension(for: display)
            let compactHeight = compactContentHeight(for: display)
            let centerGap = compactCenterGap(for: display)
            let leadingFrame = CGRect(
                x     : centerX - centerGap / 2 - extensionWidth,
                y     : topY - compactHeight,
                width : extensionWidth,
                height: compactHeight
            )
            let trailingFrame = CGRect(
                x     : centerX + centerGap / 2,
                y     : topY - compactHeight,
                width : extensionWidth,
                height: compactHeight
            )

            if let secondary = displayedSecondaryActivity {
                hostView.setCompactActivityContent(
                    leading      : activitySurface(
                        for         : activity,
                        presentation: .compactLeading,
                        outerSize   : leadingFrame.size
                    ),
                    leadingFrame : leadingFrame,
                    trailing     : nil,
                    trailingFrame: .zero
                )
                let bubbleFrame = detachedBubbleFrame(for: display).offsetBy(
                    dx: -display.frame.minX,
                    dy: topY - display.frame.maxY
                )
                hostView.setDetachedActivityContent(
                    activitySurface(
                        for         : secondary,
                        presentation: .compactLeading,
                        outerSize   : bubbleFrame.size,
                        isDetached  : true
                    ),
                    frame   : bubbleFrame,
                    onSelect: { [weak self] in self?.expandSecondaryActivity() }
                )
            } else {
                hostView.clearDetachedActivityContent()
                hostView.setCompactActivityContent(
                    leading      : activitySurface(
                        for         : activity,
                        presentation: .compactLeading,
                        outerSize   : leadingFrame.size
                    ),
                    leadingFrame : leadingFrame,
                    trailing     : activitySurface(
                        for         : activity,
                        presentation: .compactTrailing,
                        outerSize   : trailingFrame.size
                    ),
                    trailingFrame: trailingFrame
                )
            }
            return
        }

        if !isAttachingSecondary { hostView.clearDetachedActivityContent() }
        if let page = displayedContextualPage {
            hostView.clearActivityContent()
            let height = expandedTargetHeight(for: display)
            let halfWidth = effectiveExpandedHalfWidth(for: display)
            let pageFrame = CGRect(
                x: centerX - halfWidth + expandedHorizontalInset,
                y: contentTopY - height + expandedBottomInset,
                width: max(0, halfWidth * 2 - expandedHorizontalInset * 2),
                height: max(
                    0,
                    height - hardwareNotchHeight - expandedTopInset - expandedBottomInset
                )
            )
            hostView.setContent(
                page.makeContentView(in: NotchContextualPageContext(
                    availableSize: pageFrame.size
                )),
                frame: pageFrame,
                isVisible: true
            )
            return
        }
        if let activity = displayedPrimaryActivity {
            hostView.setContent(AnyView(EmptyView()), frame: .zero, isVisible: false)

            let expandedHeight = expandedTargetHeight(for: display)
            let expandedHalfWidth = effectiveExpandedHalfWidth(for: display)
            let expandedFrame = CGRect(
                x     : centerX - expandedHalfWidth,
                y     : contentTopY - expandedHeight,
                width : expandedHalfWidth * 2,
                height: max(0, expandedHeight - hardwareNotchHeight)
            )
            hostView.setExpandedActivityContent(
                activitySurface(
                    for         : activity,
                    presentation: .expanded,
                    outerSize   : expandedFrame.size
                ),
                frame: expandedFrame
            )
            return
        }

        hostView.clearActivityContent()

        let width  = effectiveExpandedHalfWidth(for: display) * 2
        let height = expandedTargetHeight(for: display)

        let interior = CGRect(
            x     : hostView.bounds.midX - width / 2,
            y     : contentTopY - height,
            width : width,
            height: height
        )
        .insetBy(dx: 20, dy: 16)

        let notchWidth    = hardwareNotchWidth
        let topBandHeight = display.hasHardwareNotch
            ? resting.height
            : softwareMetrics.compactHeight

        // The content host fills the whole band; the widgets are positioned
        // inside it from the resolved frames (which are in host, y-up coords).
        let content = widgetHost.makeContentView(
            interior     : interior,
            notchWidth   : notchWidth,
            topBandHeight: topBandHeight,
            hostHeight   : hostView.bounds.height
        )

        hostView.setContent(
            content,
            frame    : hostView.bounds,
            isVisible: true
        )
    }

    /// Build one shared activity surface. Sensitive metadata is checked before
    /// the factory, URL, accessibility label, or stale state is read, keeping
    /// redacted content out of both the visual and accessibility hierarchies.
    private func activitySurface(
        for activity                  : any NotchActivity,
        presentation                  : NotchActivityPresentation,
        outerSize                     : CGSize,
        isDetached                    : Bool = false
    ) -> AnyView {
        if activity.privacy == .sensitive, !isSensitiveContentVisible {
            return AnyView(
                SensitiveNotchActivityPlaceholder(presentation: presentation)
            )
        }

        let contentURL = isDetached ? nil : activity.contentURL
        let isStale    = !isDetached && activityHost.isStale(activity)
        let insets     = isDetached
            ? EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
            : activityInsets(for: presentation)
        var reservedWidth = isStale ? staleAccessoryWidth : 0
        if isExpanded(presentation), contentURL != nil {
            reservedWidth += openAccessoryWidth
        }
        let availableSize = CGSize(
            width : max(0, outerSize.width - insets.leading - insets.trailing - reservedWidth),
            height: max(0, outerSize.height - insets.top - insets.bottom)
        )
        let context = NotchActivityViewContext(
            presentation : presentation,
            availableSize: availableSize,
            isStale      : isStale,
            hardwareNotchWidth: isExpanded(presentation)
                ? activeDisplay.map { $0.hasHardwareNotch ? restingSize(for: $0).width : 0 } ?? 0
                : nil
        )
        let content: AnyView
        switch presentation {
        case .compactLeading:
            content = activity.makeCompactLeadingView(in: context)
        case .compactTrailing:
            content = activity.makeCompactTrailingView(in: context)
        case .minimal:
            content = activity.makeMinimalView(in: context)
        case .expanded:
            guard let liveActivity = activity as? any NotchLiveActivity else { return AnyView(EmptyView()) }
            content = liveActivity.makeExpandedView(in: context)
        }

        return AnyView(
            SharedNotchActivitySurface(
                content           : content,
                contentSize       : availableSize,
                contentURL        : contentURL,
                accessibilityLabel: activity.accessibilityLabel,
                presentation      : presentation,
                isStale           : isStale,
                insets            : insets
            )
        )
    }

    private func activityInsets(
        for presentation: NotchActivityPresentation
    ) -> EdgeInsets {
        switch presentation {
        case .compactLeading:
            EdgeInsets(
                top     : compactVerticalInset,
                leading : compactOuterInset,
                bottom  : compactVerticalInset,
                trailing: compactInnerInset
            )
        case .compactTrailing:
            EdgeInsets(
                top     : compactVerticalInset,
                leading : compactInnerInset,
                bottom  : compactVerticalInset,
                trailing: compactOuterInset
            )
        case .minimal:
            EdgeInsets(
                top     : compactVerticalInset,
                leading : compactOuterInset,
                bottom  : compactVerticalInset,
                trailing: compactOuterInset
            )
        case .expanded:
            EdgeInsets(
                top     : expandedTopInset,
                leading : expandedHorizontalInset,
                bottom  : expandedBottomInset,
                trailing: expandedHorizontalInset
            )
        }
    }

    private func isExpanded(_ presentation: NotchActivityPresentation) -> Bool {
        if case .expanded = presentation { return true }
        return false
    }

    /// hideForScreenLock stops all activity and widget presentation before the
    /// panel leaves the screen. Pointer callbacks remain installed for wake, but
    /// the visibility guard makes them inert while loginwindow owns the screen.
    private func hideForScreenLock() {
        guard isStarted, isPanelVisible else {
            return
        }

        isPanelVisible             = false
        isSettingsFocused          = false
        isExternalSurfacePresented = false
        isControlDragActive        = false
        dragReleaseTask?.cancel()
        dragReleaseTask = nil
        hoverFeedback.update(isHovering: false)
        lastPointer = nil
        morphEngine.stop()
        state = .closed
        isReturningToBase = false
        leadingSpring.snap(to: 0)
        trailingSpring.snap(to: 0)
        compactSpring.snap(to: 0)
        compactTrailingSpring.snap(to: 0)
        bubbleSpring.snap(to: 0)
        dragHeartbeatSpring.snap(to: 0)
        dragHeartbeatPhase = 0
        isRecognizedFileDragActive = false
        isAttachingSecondary = false
        presentedActivityID = nil
        presentedSecondaryActivityID = nil
        isReplacingActivity = false
        clickedOpen = false
        cancelHoverExit()
        hostView.auxiliaryInteraction.dismiss()
        heightSpring.snap(to: activeDisplay.map { Double(restingSize(for: $0).height) } ?? 0)
        sizeCalibration.finish(save: false)
        renderContent()
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    /// restoreAfterScreenUnlock takes a fresh display snapshot before showing
    /// content, so wake and resolution changes update geometry and views as one
    /// presentation rather than flashing the stale pre-lock layout.
    private func restoreAfterScreenUnlock() {
        guard isStarted, !isPanelVisible else {
            return
        }

        refreshActiveDisplay()
        isPanelVisible = true
        renderCurrentFrame()
        renderContent()
        startMorphIfNeeded()
        presentPanel()
    }

    /// updatePanelMouseInterception toggles the whole-band window using the
    /// exact animated path under the current cursor. This is the only reliable
    /// way for an NSPanel to let another process receive menu-bar clicks.
    private func updatePanelMouseInterception(at screenPoint: CGPoint) {
        guard isStarted, isPanelVisible, !sizeCalibration.isActive, !isExternalSurfacePresented else {
            panel.ignoresMouseEvents = true
            return
        }

        if isControlDragActive {
            panel.ignoresMouseEvents = false
            return
        }

        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let viewPoint   = hostView.convert(windowPoint, from: nil)
        panel.ignoresMouseEvents = !hostView.containsInteractivePoint(viewPoint)
    }
}

/// SharedNotchActivitySurface applies the host-owned appearance and behavior
/// around standard provider content. Providers keep control of their own view,
/// while Cascade supplies safe insets, stale status, accessibility, and links.
private struct SharedNotchActivitySurface: View {
    let content           : AnyView
    let contentSize       : CGSize
    let contentURL        : URL?
    let accessibilityLabel: String
    let presentation      : NotchActivityPresentation
    let isStale           : Bool
    let insets            : EdgeInsets

    var body: some View {
        ZStack {
            // The host owns expanded chrome, including glass and the opaque
            // accessibility fallback. A provider wrapper must not cover it.
            isExpandedPresentation ? Color.clear : Color.black
            linkedContent
                .padding(insets)
        }
        .environment(\.colorScheme, .dark)
        .font(isExpandedPresentation ? .body : .callout)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var linkedContent: some View {
        if !isExpandedPresentation, let contentURL {
            Link(destination: contentURL) {
                row(showsOpenControl: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            row(showsOpenControl: isExpandedPresentation && contentURL != nil)
        }
    }

    private func row(showsOpenControl: Bool) -> some View {
        HStack(spacing: 0) {
            content
                .frame(
                    width : contentSize.width,
                    height: contentSize.height
                )
                // Layout stays inside the content insets. Permit a bounded
                // glow/shadow around it; the native container still clips all
                // painting to the notch outline, including above the content.
                .padding(40)
                .clipped()
                .padding(-40)

            if isStale {
                Spacer().frame(width: 4)
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .frame(width: 14)
                    .accessibilityLabel("Aggiornamento in ritardo")
            }

            if showsOpenControl, let contentURL {
                Spacer().frame(width: 8)
                Link(destination: contentURL) {
                    Label("Apri", systemImage: "arrow.up.forward.app")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .frame(width: 68)
            }
        }
    }

    private var isExpandedPresentation: Bool {
        if case .expanded = presentation { return true }
        return false
    }
}

/// SensitiveNotchActivityPlaceholder is constructed without consulting the
/// provider, so private text, URLs, freshness, and accessibility labels cannot
/// enter the hidden SwiftUI tree.
private struct SensitiveNotchActivityPlaceholder: View {
    let presentation: NotchActivityPresentation

    var body: some View {
        ZStack {
            isExpandedPresentation ? Color.clear : Color.black
            if isExpandedPresentation {
                Label("Attività nascosta", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Attività sensibile nascosta")
    }

    private var isExpandedPresentation: Bool {
        if case .expanded = presentation { return true }
        return false
    }
}
