//
//  NotchDisplayCoordinator.swift
//  CascadeKit
//

import AppKit
import OSLog

private let fileDropLog = Logger(subsystem: "hylo.Cascade", category: "FileDrop")

/// DisplayExpansionTrigger describes why a local surface wants ownership.
/// Hover requests are cancellable while explicit invocations remain valid until
/// the surface withdraws them or its display leaves the inventory.
enum DisplayExpansionTrigger: Equatable {
    case hover
    case click
    case accessibility
    case settings
    case spotlight
    case calibration
    case popover
    case drag
}

/// DisplayExpansionRequest carries the local generation that makes delayed
/// arbitration safe. A later generation from the same surface supersedes it.
struct DisplayExpansionRequest: Equatable {
    let displayID : CGDirectDisplayID
    let activityID: String?
    let trigger   : DisplayExpansionTrigger
    let generation: UInt64
}

/// NotchInteractionKind names interactions that pin an owner and its invocation
/// anchor while still allowing focused-window routing to update compact copies.
enum NotchInteractionKind: Hashable {
    case settings
    case spotlight
    case calibration
    case popover
    case drag
}

/// DisplayPresentation is the complete content projection for one fixed panel.
/// Provider references are shared, while each surface creates its own local view.
struct DisplayPresentation {
    let primary    : (any NotchLiveActivity)?
    let secondary  : (any NotchLiveActivity)?
    let notice     : (any NotchTransientNotice)?
    let expanded   : (any NotchLiveActivity)?
    /// expandedIsLiveActivity distinguishes a routed session from the explicit
    /// no-session fallback, even when both use the same provider protocol.
    let expandedIsLiveActivity: Bool
    let showsWidgets: Bool
    let contextualPage: (any NotchContextualPage)?
    let contextualPageIsSelected: Bool
    let widgetContentRevision: UInt64
    let style      : ExternalNotchStyle

    init(
        primary: (any NotchLiveActivity)?,
        secondary: (any NotchLiveActivity)?,
        notice: (any NotchTransientNotice)?,
        expanded: (any NotchLiveActivity)?,
        expandedIsLiveActivity: Bool,
        showsWidgets: Bool,
        contextualPage: (any NotchContextualPage)? = nil,
        contextualPageIsSelected: Bool = false,
        widgetContentRevision: UInt64,
        style: ExternalNotchStyle
    ) {
        self.primary = primary
        self.secondary = secondary
        self.notice = notice
        self.expanded = expanded
        self.expandedIsLiveActivity = expandedIsLiveActivity
        self.showsWidgets = showsWidgets
        self.contextualPage = contextualPage
        self.contextualPageIsSelected = contextualPageIsSelected
        self.widgetContentRevision = widgetContentRevision
        self.style = style
    }

    var isExpanded: Bool {
        expanded != nil || showsWidgets || contextualPageIsSelected
    }

    /// visibleActivityRoots mirrors the renderer's real mounted roots. An owner
    /// presents only its expanded root, a notice replaces compact roots locally,
    /// and a compact surface may mount primary plus its detached secondary.
    var visibleActivityRoots: [any NotchActivity] {
        if let expanded {
            return [expanded]
        }
        if showsWidgets || contextualPageIsSelected {
            return []
        }
        if let notice {
            return [notice]
        }
        return [primary, secondary].compactMap { $0 }
    }

    func removingInvalidRoots(
        accepted: Set<ObjectIdentifier>,
        host    : LiveActivityHost
    ) -> DisplayPresentation {
        func validLive(_ activity: (any NotchLiveActivity)?) -> (any NotchLiveActivity)? {
            guard let activity,
                  accepted.contains(ObjectIdentifier(activity)),
                  host.isPresentationValid(activity) else {
                return nil
            }
            return activity
        }

        func validNotice(_ activity: (any NotchTransientNotice)?) -> (any NotchTransientNotice)? {
            guard let activity,
                  accepted.contains(ObjectIdentifier(activity)),
                  host.isPresentationValid(activity) else {
                return nil
            }
            return activity
        }

        return DisplayPresentation(
            primary     : validLive(primary),
            secondary   : validLive(secondary),
            notice      : validNotice(notice),
            expanded    : validLive(expanded),
            expandedIsLiveActivity: expandedIsLiveActivity,
            showsWidgets: showsWidgets,
            contextualPage: contextualPage,
            contextualPageIsSelected: contextualPageIsSelected,
            widgetContentRevision: widgetContentRevision,
            style       : style
        )
    }
}

/// NotchDisplayPresenting is the fixed-display boundary between global
/// arbitration and one panel's geometry, springs, views and local interaction.
@MainActor
protocol NotchDisplayPresenting: AnyObject {
    var onSettingsRequested: (() -> Void)? { get set }
    var onExpandedFrameChanged: ((CGRect?) -> Void)? { get set }
    var expandedFrame: CGRect? { get }
    var restingFrame: CGRect? { get }
    var onExpansionRequested    : ((DisplayExpansionRequest) -> Void)? { get set }
    var onExpansionCancelled    : ((UInt64) -> Void)? { get set }
    var onCollapseRequested     : (() -> Void)? { get set }
    var onCollapseFinished      : ((UInt64) -> Void)? { get set }
    var onInteractionHoldChanged: ((NotchInteractionKind, Bool) -> Void)? { get set }
    var onDragOwnershipChanged  : ((Bool) -> Void)? { get set }
    var onRetainedActivityRootsChanged: (() -> Void)? { get set }
    var onFileDragHoverChanged: (([URL]?) -> Void)? { get set }
    var onFileDrop: (([URL]) -> Bool)? { get set }
    var onUnsupportedFileDrop: (() -> Void)? { get set }
    /// Exact provider instances still owned by the renderer, including its
    /// current mounted projection and roots leaving through a transition.
    var retainedActivityRoots: [any NotchActivity] { get }

    func start()
    func updateDisplay(_ display: ActiveDisplay)
    func applyPresentation(_ presentation: DisplayPresentation)
    func discardRetainedActivityRoots(_ identities: Set<ObjectIdentifier>)
    func close(animated: Bool, generation: UInt64)
    func cancelClose()
    func setVisible(_ isVisible: Bool)
    func handlePointer(at point: CGPoint)
    func handlePointerButton(isPressed: Bool)
    func handleSpaceChange()
    @discardableResult
    func beginSizeCalibration() -> Bool
    func setSettingsFocused(_ isFocused: Bool)
    func setExternalSurfacePresented(_ isPresented: Bool)
    func setHapticsEnabled(_ isEnabled: Bool)
    func setBorderAppearance(_ appearance: NotchBorderAppearance)
    func setSensitiveContentVisible(_ isVisible: Bool)
    func setFileDropEnabled(_ isEnabled: Bool)
    func endRecognizedFileDragGesture()
    func setRecognizedFileDragActive(_ isActive: Bool, at point: CGPoint)
    func stop()
}

/// NotchDisplayCoordinator owns all process-global observation and content
/// hosts. It keeps one fixed local surface per logical display and serializes
/// expanded ownership through real collapse-completion callbacks.
@MainActor
final class NotchDisplayCoordinator {
    private enum ContextualSelectionReason: Equatable {
        case defaultOccupied
        case manual
        case preview
    }

    private enum ExpandedPageSelection: Equatable {
        case automatic
        case ordinary(ActivityExpansionSelection)
        case contextual(String, ContextualSelectionReason)
    }

    private struct FileDropPreview {
        let displayID: CGDirectDisplayID
        let previousSelection: ExpandedPageSelection
        let openedForPreview: Bool
    }
    private struct SurfaceRecord {
        let surface: any NotchDisplayPresenting
        var entry  : DisplayInventoryEntry
    }

    private let inventory   : any DisplayInventoryProviding
    private let focusMonitor: any FocusedWindowMonitoring
    private let monitor     : any EventMonitoring
    private let activityHost: LiveActivityHost
    private let widgetHost  : WidgetHost
    private let mainDisplay : () -> CGDirectDisplayID?
    private let pointer     : () -> CGPoint
    private let makeSurface : (ActiveDisplay) -> any NotchDisplayPresenting

    private var preferences: DisplayPresentationPreferences
    private var pendingPreferences: DisplayPresentationPreferences?
    private var transientStyles: [CGDirectDisplayID: ExternalNotchStyle] = [:]
    private var pendingTransientStyles: [CGDirectDisplayID: ExternalNotchStyle] = [:]
    private var surfaces   : [CGDirectDisplayID: SurfaceRecord] = [:]
    private var latestRequests: [CGDirectDisplayID: DisplayExpansionRequest] = [:]
    private var pendingRequests: [CGDirectDisplayID: DisplayExpansionRequest] = [:]
    private var pendingRequestOrder: [CGDirectDisplayID: UInt64] = [:]
    private var nextRequestOrder: UInt64 = 0
    private var interactionHolds: [CGDirectDisplayID: Set<NotchInteractionKind>] = [:]
    private var interactionOwnerDisplayID: CGDirectDisplayID?
    private var closingDisplayID: CGDirectDisplayID?
    private var closingGeneration: UInt64?
    private var nextClosingGeneration: UInt64 = 0
    private var focusedWindow: CGRect?
    private var focusedDisplayID: CGDirectDisplayID?
    private var pointerLocation: CGPoint
    private var previousPointerDisplayID: CGDirectDisplayID?
    private var dragDisplayID: CGDirectDisplayID?
    private var settingsDisplayID: CGDirectDisplayID?
    private var externalDisplayID: CGDirectDisplayID?
    private var externalReady: (() -> Void)?
    private var isExternalSurfaceActive = false
    private var isStarted = false
    private var isVisible = true
    private var widgetContentRevision: UInt64 = 0
    private var isHapticsEnabled = true
    private var borderAppearance: NotchBorderAppearance = .neutral
    private var isSensitiveContentVisible = false
    private var contextualPage: (any NotchContextualPage)?
    private var contextualPagePrefersDefault = false
    private var expandedPageSelection: ExpandedPageSelection = .automatic
    private var pendingExplicitPageSelection: (
        displayID: CGDirectDisplayID,
        selection: ExpandedPageSelection
    )?
    private var fileDropPreview: FileDropPreview?
    private var recognizedFileDragDisplayID: CGDirectDisplayID?
    private var nativeFileDragHoverDisplayID: CGDirectDisplayID?
    private var isRecognizedFileDragGestureActive = false
    private var fileDragGestureGeneration: UInt64 = 0
    private var fileDragReleaseTask: Task<Void, Never>?
    private var fileDropOnHover: (@MainActor ([URL]?) -> Void)?
    private var fileDropOnDrop: (@MainActor ([URL]) -> Bool)?
    private var fileDropOnUnsupported: (@MainActor () -> Void)?
    private var isReconciling = false
    private var needsReconciliation = false

    private(set) var expandedDisplayID: CGDirectDisplayID?
    var onSettingsRequested: (() -> Void)?
    var onExpandedFrameChanged: ((CGRect?) -> Void)?
    var onDisplaysChanged: (([NotchDisplayDescriptor]) -> Void)?
    var onScreenLocked: (() -> Void)?

    var displayDescriptors: [NotchDisplayDescriptor] {
        surfaces.values.map { record in
            NotchDisplayDescriptor(
                runtimeID       : record.entry.snapshot.displayID,
                identity        : record.entry.identity,
                name            : record.entry.name,
                hasHardwareNotch: record.entry.snapshot.hasHardwareNotch,
                style           : describedStyle(for: record.entry.snapshot.displayID)
            )
        }.sorted { $0.runtimeID < $1.runtimeID }
    }

    var auxiliaryDisplayID: CGDirectDisplayID? {
        interactionOwnerDisplayID ?? expandedDisplayID ?? focusedDisplayID
    }

    var settingsAnchorDisplayID: CGDirectDisplayID? { settingsDisplayID }

    var expandedFrame: CGRect? {
        guard let expandedDisplayID else { return nil }
        return surfaces[expandedDisplayID]?.surface.expandedFrame
    }

    /// restingFrame follows the interaction anchor, then the expanded owner,
    /// then focus. The surface remains the sole resolver of its real silhouette.
    var restingFrame: CGRect? {
        guard let displayID = auxiliaryDisplayID else {
            return nil
        }
        return surfaces[displayID]?.surface.restingFrame
    }

    func restingFrame(on displayID: CGDirectDisplayID) -> CGRect? {
        surfaces[displayID]?.surface.restingFrame
    }

    init(
        inventory   : any DisplayInventoryProviding,
        focusMonitor: any FocusedWindowMonitoring,
        monitor     : any EventMonitoring,
        activityHost: LiveActivityHost,
        widgetHost  : WidgetHost,
        preferences : DisplayPresentationPreferences,
        mainDisplay : @escaping () -> CGDirectDisplayID? = { CGMainDisplayID() },
        pointer     : @escaping () -> CGPoint = { NSEvent.mouseLocation },
        makeSurface : @escaping (ActiveDisplay) -> any NotchDisplayPresenting
    ) {
        self.inventory       = inventory
        self.focusMonitor    = focusMonitor
        self.monitor         = monitor
        self.activityHost    = activityHost
        self.widgetHost      = widgetHost
        self.preferences     = preferences
        self.mainDisplay     = mainDisplay
        self.pointer         = pointer
        self.makeSurface     = makeSurface
        self.pointerLocation = pointer()
    }

    /// start installs each global callback once, then creates persistent local
    /// surfaces from the inventory's first atomic topology snapshot.
    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        isVisible = true
        pointerLocation = pointer()
        inventory.onChange = { [weak self] in self?.reconcileInventory() }
        focusMonitor.onChange = { [weak self] frame in
            self?.focusedWindow = frame
            self?.resolveFocusAndReconcile()
        }
        activityHost.onChange = { [weak self] in self?.reconcilePresentations() }
        activityHost.onValidityChange = { [weak self] in self?.reconcilePresentations() }
        widgetHost.onContentChanged = { [weak self] in
            guard let self else { return }
            self.widgetContentRevision &+= 1
            self.reconcilePresentations()
        }
        monitor.onPointerMoved = { [weak self] point in self?.handlePointer(at: point) }
        monitor.onPointerButtonChanged = { [weak self] pressed in
            self?.handlePointerButton(isPressed: pressed)
        }
        monitor.onActiveDisplayMayHaveChanged = { [weak self] in
            self?.focusMonitor.refresh()
        }
        monitor.onSpaceChanged = { [weak self] in self?.handleSpaceChange() }
        monitor.onScreenLocked = { [weak self] in
            guard let self else { return }
            self.setVisible(false)
            self.onScreenLocked?()
        }
        monitor.onScreenUnlocked = { [weak self] in self?.setVisible(true) }
        monitor.setFileDragRecognitionHandler { [weak self] active, point in
            self?.handleRecognizedFileDrag(active: active, at: point)
        }

        // The host must grant capability before the first local factory runs.
        // Setting the global gate before inventory reconciliation makes that
        // ordering true even for the initial batch of surfaces.
        activityHost.setVisible(true)
        inventory.start()
        reconcileInventory()
        focusMonitor.start()
        monitor.start()
    }

    /// stop tears down every panel before stopping the shared services once.
    func stop() {
        guard isStarted else {
            return
        }

        isStarted = false
        inventory.onChange = nil
        focusMonitor.onChange = nil
        monitor.onPointerMoved = nil
        monitor.onPointerButtonChanged = nil
        monitor.onActiveDisplayMayHaveChanged = nil
        monitor.onSpaceChanged = nil
        monitor.onScreenLocked = nil
        monitor.onScreenUnlocked = nil
        monitor.setFileDragRecognitionHandler(nil)
        activityHost.onChange = nil
        activityHost.onValidityChange = nil
        widgetHost.onContentChanged = nil
        for record in surfaces.values {
            clearCallbacks(on: record.surface)
            record.surface.stop()
        }
        surfaces.removeAll()
        latestRequests.removeAll()
        pendingRequests.removeAll()
        pendingRequestOrder.removeAll()
        interactionHolds.removeAll()
        transientStyles.removeAll()
        pendingTransientStyles.removeAll()
        pendingPreferences = nil
        interactionOwnerDisplayID = nil
        closingDisplayID = nil
        closingGeneration = nil
        expandedDisplayID = nil
        dragDisplayID = nil
        settingsDisplayID = nil
        externalDisplayID = nil
        externalReady = nil
        isExternalSurfaceActive = false
        expandedPageSelection = .automatic
        pendingExplicitPageSelection = nil
        fileDropPreview = nil
        recognizedFileDragDisplayID = nil
        nativeFileDragHoverDisplayID = nil
        isRecognizedFileDragGestureActive = false
        fileDragReleaseTask?.cancel()
        fileDragReleaseTask = nil
        widgetHost.update(state: .closed)
        activityHost.stop()
        monitor.stop()
        focusMonitor.stop()
        inventory.stop()
    }

    func updatePreferences(_ preferences: DisplayPresentationPreferences) {
        guard self.preferences != preferences || pendingPreferences != nil else { return }
        if let owner = expandedDisplayID,
           style(for: owner, preferences: self.preferences) != style(for: owner, preferences: preferences) {
            pendingPreferences = preferences
            beginCollapse(of: owner)
            onDisplaysChanged?(displayDescriptors)
            return
        }
        pendingPreferences = nil
        self.preferences = preferences
        if let owner = expandedDisplayID, !routedDisplayIDs().contains(owner) {
            latestRequests.removeValue(forKey: owner)
            beginCollapse(of: owner)
        }
        reconcilePresentations()
        onDisplaysChanged?(displayDescriptors)
    }

    func setTransientDisplayStyle(
        _ style       : ExternalNotchStyle,
        for displayID : CGDirectDisplayID
    ) {
        guard surfaces[displayID]?.entry.identity == nil,
              transientStyles[displayID] != style else { return }
        if expandedDisplayID == displayID {
            pendingTransientStyles[displayID] = style
            beginCollapse(of: displayID)
            onDisplaysChanged?(displayDescriptors)
            return
        }
        transientStyles[displayID] = style
        reconcilePresentations()
        onDisplaysChanged?(displayDescriptors)
    }

    func register(_ widget: NotchWidget) {
        widgetHost.register(widget)
        widgetContentRevision &+= 1
        reconcilePresentations()
    }

    func unregisterWidget(id: WidgetIdentifier) {
        widgetHost.unregister(id: id)
        reconcilePresentations()
    }

    func setContextualPage(
        _ page          : (any NotchContextualPage)?,
        prefersDefault  : Bool
    ) {
        let wasPreferred = contextualPagePrefersDefault
        contextualPage = page
        contextualPagePrefersDefault = page != nil && prefersDefault
        if page == nil {
            if case .contextual = expandedPageSelection {
                selectOrdinaryPage()
            }
            pendingExplicitPageSelection = nil
            endFileDropPreview(keepContextual: false)
            clearRecognizedFileDrag()
        } else if wasPreferred && !contextualPagePrefersDefault,
                  case .contextual = expandedPageSelection {
            selectOrdinaryPage()
        }
        updateFileDropReadiness()
        reconcilePresentations()
    }

    func showContextualPage(on requestedDisplayID: CGDirectDisplayID? = nil) {
        guard let contextualPage else { return }
        let displayID = requestedDisplayID ?? expandedDisplayID ?? auxiliaryDisplayID
        guard let displayID, surfaces[displayID] != nil else { return }
        let selection = ExpandedPageSelection.contextual(contextualPage.id, .manual)
        if expandedDisplayID == displayID {
            pendingExplicitPageSelection = nil
            expandedPageSelection = selection
            reconcilePresentations()
        } else {
            pendingExplicitPageSelection = (displayID, selection)
            requestExpansion(on: displayID, activityID: nil, trigger: .click)
        }
    }

    func showOrdinaryPage(on requestedDisplayID: CGDirectDisplayID? = nil) {
        guard let displayID = requestedDisplayID ?? expandedDisplayID,
              surfaces[displayID] != nil else { return }
        if expandedDisplayID == displayID {
            pendingExplicitPageSelection = nil
            selectOrdinaryPage()
            reconcilePresentations()
        } else {
            let selection = ExpandedPageSelection.ordinary(
                resolvedOrdinarySelection(on: displayID)
            )
            pendingExplicitPageSelection = (displayID, selection)
            requestExpansion(on: displayID, activityID: nil, trigger: .click)
        }
    }

    func configureFileDrop(
        onHover      : (@MainActor ([URL]?) -> Void)?,
        onDrop       : (@MainActor ([URL]) -> Bool)?,
        onUnsupported: (@MainActor () -> Void)?
    ) {
        fileDropOnHover = onHover
        fileDropOnDrop = onDrop
        fileDropOnUnsupported = onUnsupported
        updateFileDropReadiness()
        if onDrop == nil {
            endFileDropPreview(keepContextual: false)
            clearRecognizedFileDrag()
        }
    }

    func present(_ activity: any NotchLiveActivity) { activityHost.present(activity) }
    func setExpandedFallback(_ activity: (any NotchLiveActivity)?) {
        activityHost.setExpandedFallback(activity)
    }
    func showNotice(_ notice: any NotchTransientNotice) {
        guard isVisible, heldDisplay(for: .spotlight) == nil else { return }
        activityHost.showNotice(notice)
    }
    func updateNotice(_ notice: any NotchTransientNotice) {
        guard isVisible, heldDisplay(for: .spotlight) == nil else { return }
        activityHost.updateNotice(notice)
    }
    func endActivity(id: String) { activityHost.end(id: id) }
    func dismissActivity(id: String) { activityHost.dismiss(id: id) }
    func dismissActivities(from sourceID: String) { activityHost.dismissActivities(from: sourceID) }

    func beginSizeCalibration(on requestedDisplayID: CGDirectDisplayID? = nil) {
        guard let displayID = requestedDisplayID ?? auxiliaryDisplayID,
              let surface = surfaces[displayID]?.surface else { return }
        guard surface.beginSizeCalibration() else { return }
        setInteractionHold(.calibration, on: displayID, active: true)
    }

    func setSettingsFocused(_ isFocused: Bool) {
        let heldDisplayID = heldDisplay(for: .settings)
        guard let displayID = heldDisplayID ?? settingsDisplayID ?? expandedDisplayID ?? focusedDisplayID,
              let surface = surfaces[displayID]?.surface else { return }
        setInteractionHold(.settings, on: displayID, active: isFocused)
        surface.setSettingsFocused(isFocused)
    }

    func setSettingsPresented(
        _ isPresented         : Bool,
        reanchorToCurrentOwner: Bool = false
    ) {
        if isPresented {
            let currentOwner = interactionOwnerDisplayID ?? expandedDisplayID ?? focusedDisplayID
            guard let displayID = reanchorToCurrentOwner
                    ? currentOwner
                    : settingsDisplayID ?? currentOwner,
                  surfaces[displayID] != nil else { return }
            settingsDisplayID = displayID
            if expandedDisplayID == nil {
                requestExpansion(on: displayID, activityID: nil, trigger: .settings)
            }
        } else {
            settingsDisplayID = nil
        }
    }

    func setExternalSurfacePresented(_ isPresented: Bool) {
        if isPresented {
            guard let displayID = auxiliaryDisplayID else { return }
            reserveExternalSurface(on: displayID) {}
        } else {
            releaseExternalSurface()
        }
    }

    /// reserveExternalSurface keeps the requested origin exclusive and waits
    /// for another expanded owner to report real compact geometry before the
    /// external presenter starts.
    func reserveExternalSurface(
        on displayID: CGDirectDisplayID,
        ready       : @escaping () -> Void
    ) {
        guard isStarted, isVisible, surfaces[displayID] != nil else { return }
        if externalDisplayID == displayID, isExternalSurfaceActive {
            ready()
            return
        }
        if externalDisplayID != displayID {
            releaseExternalSurface()
        }
        externalDisplayID = displayID
        externalReady = ready
        setInteractionHold(.spotlight, on: displayID, active: true)
        advanceExternalSurfaceReservation()
    }

    /// releaseExternalSurface always clears the display that acquired the
    /// reservation, even if focus or Settings anchoring changed meanwhile.
    func releaseExternalSurface() {
        guard let displayID = externalDisplayID else { return }
        externalReady = nil
        if isExternalSurfaceActive {
            surfaces[displayID]?.surface.setExternalSurfacePresented(false)
        }
        isExternalSurfaceActive = false
        externalDisplayID = nil
        setInteractionHold(.spotlight, on: displayID, active: false)
    }

    func setHapticsEnabled(_ isEnabled: Bool) {
        isHapticsEnabled = isEnabled
        for record in surfaces.values { record.surface.setHapticsEnabled(isEnabled) }
    }

    func setBorderAppearance(_ appearance: NotchBorderAppearance) {
        borderAppearance = appearance
        for record in surfaces.values { record.surface.setBorderAppearance(appearance) }
    }

    func setSensitiveContentVisible(_ isVisible: Bool) {
        isSensitiveContentVisible = isVisible
        for record in surfaces.values { record.surface.setSensitiveContentVisible(isVisible) }
    }

    /// requestExpansion arbitrates a generation-tagged local intent. Ownership
    /// never moves until the current surface reports actual compact completion.
    func requestExpansion(
        on displayID : CGDirectDisplayID,
        activityID   : String?,
        trigger      : DisplayExpansionTrigger = .click,
        generation   : UInt64? = nil
    ) {
        let generation = generation ?? ((latestRequests[displayID]?.generation ?? 0) &+ 1)
        acceptExpansion(DisplayExpansionRequest(
            displayID : displayID,
            activityID: activityID,
            trigger   : trigger,
            generation: generation
        ))
    }

    func requestCollapse(on displayID: CGDirectDisplayID) {
        latestRequests.removeValue(forKey: displayID)
        removePendingRequest(on: displayID)
        guard expandedDisplayID == displayID else {
            return
        }
        beginCollapse(of: displayID)
    }

    /// didFinishCollapse is the compatibility entry point for surfaces that do
    /// not retain a generation. Generated completions remain the safe path.
    func didFinishCollapse(on displayID: CGDirectDisplayID) {
        guard let generation = closingGeneration else { return }
        didFinishCollapse(on: displayID, generation: generation)
    }

    func cancelExpansion(
        on displayID: CGDirectDisplayID,
        generation : UInt64
    ) {
        guard latestRequests[displayID]?.generation == generation else { return }
        latestRequests.removeValue(forKey: displayID)
        if pendingRequests[displayID]?.generation == generation {
            removePendingRequest(on: displayID)
        }
    }

    /// setInteractionHold is the concrete ownership hook used by Spotlight,
    /// calibration, popovers and drag integration in the app shell.
    func setInteractionHold(
        _ kind     : NotchInteractionKind,
        on displayID: CGDirectDisplayID,
        active     : Bool
    ) {
        var holds = interactionHolds[displayID] ?? []
        if active {
            holds.insert(kind)
            if interactionOwnerDisplayID == nil {
                interactionOwnerDisplayID = displayID
            }
        } else {
            holds.remove(kind)
        }
        interactionHolds[displayID] = holds.isEmpty ? nil : holds

        guard !active,
              interactionOwnerDisplayID == displayID,
              !hasInteractionHold(on: displayID) else {
            return
        }

        interactionOwnerDisplayID = interactionHolds.keys.first
        advanceExternalSurfaceReservation()
        guard interactionOwnerDisplayID == nil else { return }
        if let expandedDisplayID, !pendingRequests.isEmpty {
            beginCollapse(of: expandedDisplayID)
        } else if expandedDisplayID == nil {
            resumeNewestPendingRequest()
        }
    }

    private func acceptExpansion(_ request: DisplayExpansionRequest) {
        guard isStarted, isVisible, surfaces[request.displayID] != nil else { return }
        if let latest = latestRequests[request.displayID], latest.generation > request.generation {
            return
        }
        latestRequests[request.displayID] = request

        guard let owner = expandedDisplayID else {
            if let interactionOwnerDisplayID,
               interactionOwnerDisplayID != request.displayID {
                enqueue(request)
                return
            }
            grant(request)
            return
        }
        guard owner != request.displayID else {
            if closingDisplayID == owner {
                closingDisplayID = nil
                closingGeneration = nil
                surfaces[owner]?.surface.cancelClose()
            }
            grant(request)
            return
        }

        enqueue(request)
        guard interactionOwnerDisplayID == nil else {
            return
        }
        beginCollapse(of: owner)
    }

    private func beginCollapse(of displayID: CGDirectDisplayID) {
        guard closingDisplayID == nil,
              expandedDisplayID == displayID,
              let surface = surfaces[displayID]?.surface else {
            return
        }
        latestRequests.removeValue(forKey: displayID)
        removePendingRequest(on: displayID)
        nextClosingGeneration &+= 1
        closingDisplayID = displayID
        closingGeneration = nextClosingGeneration
        surface.close(animated: true, generation: nextClosingGeneration)
    }

    private func didFinishCollapse(
        on displayID: CGDirectDisplayID,
        generation : UInt64
    ) {
        guard closingDisplayID == displayID,
              closingGeneration == generation,
              expandedDisplayID == displayID else {
            return
        }

        closingDisplayID = nil
        closingGeneration = nil
        expandedDisplayID = nil
        expandedPageSelection = .automatic
        fileDropPreview = nil
        activityHost.setExpansion(.none)
        if let pendingPreferences {
            preferences = pendingPreferences
            self.pendingPreferences = nil
        }
        for (displayID, style) in pendingTransientStyles {
            transientStyles[displayID] = style
        }
        pendingTransientStyles.removeAll()
        reconcilePresentations()
        onDisplaysChanged?(displayDescriptors)

        activateExternalSurfaceIfReady()
        resumeNewestPendingRequest()
    }

    private func grant(_ request: DisplayExpansionRequest) {
        guard surfaces[request.displayID] != nil,
              latestRequests[request.displayID] == request else {
            return
        }
        let wasAlreadyOwner = expandedDisplayID == request.displayID
        expandedDisplayID = request.displayID
        pendingRequests.removeAll()
        pendingRequestOrder.removeAll()

        if request.trigger == .drag,
           contextualPage != nil, fileDropOnDrop != nil {
            beginFileDropPreview(on: request.displayID, openedForPreview: !wasAlreadyOwner)
            setInteractionHold(.drag, on: request.displayID, active: true)
        } else if let pendingExplicitPageSelection,
                  pendingExplicitPageSelection.displayID == request.displayID {
            expandedPageSelection = pendingExplicitPageSelection.selection
            self.pendingExplicitPageSelection = nil
            if case let .ordinary(selection) = expandedPageSelection {
                applyOrdinarySelection(selection)
            }
        } else if let activityID = request.activityID {
            let selection: ActivityExpansionSelection = routedDisplayIDs().contains(request.displayID)
                ? .activity(activityID)
                : .widgets
            expandedPageSelection = .ordinary(selection)
            activityHost.setExpansion(selection)
        } else if !wasAlreadyOwner {
            if let contextualPage, contextualPagePrefersDefault {
                expandedPageSelection = .contextual(contextualPage.id, .defaultOccupied)
                applyOrdinarySelection(resolvedOrdinarySelection(on: request.displayID))
            } else {
                expandedPageSelection = .automatic
                applyOrdinarySelection(resolvedOrdinarySelection(on: request.displayID))
            }
        } else if case .automatic = expandedPageSelection {
            applyOrdinarySelection(resolvedOrdinarySelection(on: request.displayID))
        }
        reconcilePresentations()
    }

    private func resolvedOrdinarySelection(
        on displayID: CGDirectDisplayID
    ) -> ActivityExpansionSelection {
        let isRouted = routedDisplayIDs().contains(displayID)
        if isRouted, let primary = activityHost.selection.primary {
            return .activity(primary.id)
        }
        return isRouted ? .fallback : .widgets
    }

    private func applyOrdinarySelection(_ selection: ActivityExpansionSelection) {
        if activityHost.expansionSelection != selection {
            activityHost.setExpansion(selection)
        }
    }

    private func selectOrdinaryPage() {
        guard let displayID = expandedDisplayID else { return }
        let selection: ActivityExpansionSelection
        switch expandedPageSelection {
        case let .ordinary(existing):
            selection = existing
        default:
            selection = activityHost.expansionSelection == .none
                ? resolvedOrdinarySelection(on: displayID)
                : activityHost.expansionSelection
        }
        expandedPageSelection = .ordinary(selection)
        applyOrdinarySelection(selection)
    }

    private func beginFileDropPreview(
        on displayID: CGDirectDisplayID,
        openedForPreview: Bool
    ) {
        guard let contextualPage else { return }
        if fileDropPreview == nil {
            fileDropPreview = FileDropPreview(
                displayID: displayID,
                previousSelection: expandedPageSelection,
                openedForPreview: openedForPreview
            )
        }
        expandedPageSelection = .contextual(contextualPage.id, .preview)
    }

    private func endFileDropPreview(keepContextual: Bool) {
        guard let preview = fileDropPreview else { return }
        fileDropPreview = nil
        if keepContextual, let contextualPage {
            expandedPageSelection = .contextual(contextualPage.id, .manual)
            reconcilePresentations()
            return
        }
        expandedPageSelection = preview.previousSelection
        if preview.openedForPreview, expandedDisplayID == preview.displayID {
            requestCollapse(on: preview.displayID)
        } else {
            reconcilePresentations()
        }
    }

    private func reconcileInventory() {
        guard isStarted else {
            return
        }

        let entries = Dictionary(uniqueKeysWithValues: inventory.displays.map {
            ($0.snapshot.displayID, $0)
        })
        let removed = Set(surfaces.keys).subtracting(entries.keys)
        let ownerWasRemoved = expandedDisplayID.map(removed.contains) == true
        let interactionOwnerWasRemoved = interactionOwnerDisplayID.map(removed.contains) == true

        for displayID in removed {
            if let record = surfaces.removeValue(forKey: displayID) {
                clearCallbacks(on: record.surface)
                record.surface.stop()
            }
            latestRequests.removeValue(forKey: displayID)
            removePendingRequest(on: displayID)
            interactionHolds.removeValue(forKey: displayID)
            transientStyles.removeValue(forKey: displayID)
            pendingTransientStyles.removeValue(forKey: displayID)
            if dragDisplayID == displayID { dragDisplayID = nil }
            if settingsDisplayID == displayID { settingsDisplayID = nil }
            if pendingExplicitPageSelection?.displayID == displayID {
                pendingExplicitPageSelection = nil
            }
        }

        if ownerWasRemoved || interactionOwnerWasRemoved {
            expandedDisplayID = nil
            pendingRequests.removeAll()
            pendingRequestOrder.removeAll()
            closingDisplayID = nil
            closingGeneration = nil
            interactionOwnerDisplayID = nil
            expandedPageSelection = .automatic
            pendingExplicitPageSelection = nil
            fileDropPreview = nil
            activityHost.setExpansion(.none)
        } else if closingDisplayID.map(removed.contains) == true {
            closingDisplayID = nil
            closingGeneration = nil
        }

        for (displayID, entry) in entries {
            if var record = surfaces[displayID] {
                if record.entry.snapshot != entry.snapshot {
                    record.entry = entry
                    surfaces[displayID] = record
                    record.surface.updateDisplay(entry.snapshot)
                } else {
                    record.entry = entry
                    surfaces[displayID] = record
                }
            } else {
                let surface = makeSurface(entry.snapshot)
                installCallbacks(on: surface, displayID: displayID)
                surfaces[displayID] = SurfaceRecord(surface: surface, entry: entry)
                surface.setHapticsEnabled(isHapticsEnabled)
                surface.setBorderAppearance(borderAppearance)
                surface.setSensitiveContentVisible(isSensitiveContentVisible)
                surface.start()
                surface.setVisible(isVisible)
            }
        }

        resolveFocusAndReconcile()
        activateExternalSurfaceIfReady()
        onDisplaysChanged?(displayDescriptors)
    }

    private func installCallbacks(
        on surface: any NotchDisplayPresenting,
        displayID: CGDirectDisplayID
    ) {
        surface.onExpansionRequested = { [weak self] request in
            self?.acceptExpansion(request)
        }
        surface.onExpansionCancelled = { [weak self] generation in
            self?.cancelExpansion(on: displayID, generation: generation)
        }
        surface.onCollapseRequested = { [weak self] in
            self?.requestCollapse(on: displayID)
        }
        surface.onCollapseFinished = { [weak self] generation in
            self?.didFinishCollapse(on: displayID, generation: generation)
        }
        surface.onInteractionHoldChanged = { [weak self] kind, active in
            self?.setInteractionHold(kind, on: displayID, active: active)
        }
        surface.onDragOwnershipChanged = { [weak self] active in
            guard let self else { return }
            self.dragDisplayID = active ? displayID : (self.dragDisplayID == displayID ? nil : self.dragDisplayID)
            self.setInteractionHold(.drag, on: displayID, active: active)
        }
        surface.onRetainedActivityRootsChanged = { [weak self] in
            self?.reconcilePresentations()
        }
        surface.onSettingsRequested = { [weak self] in
            guard let self else { return }
            self.settingsDisplayID = displayID
            self.onSettingsRequested?()
        }
        surface.onExpandedFrameChanged = { [weak self] frame in
            guard self?.expandedDisplayID == displayID else { return }
            self?.onExpandedFrameChanged?(frame)
        }
        surface.onFileDragHoverChanged = { [weak self] urls in
            self?.handleFileDragHover(urls, on: displayID)
        }
        surface.onFileDrop = { [weak self] urls in
            self?.handleFileDrop(urls, on: displayID) ?? false
        }
        surface.onUnsupportedFileDrop = { [weak self] in
            self?.handleUnsupportedFileDrop(on: displayID)
        }
        surface.setFileDropEnabled(contextualPage != nil && fileDropOnDrop != nil)
    }

    private func clearCallbacks(on surface: any NotchDisplayPresenting) {
        surface.onExpansionRequested = nil
        surface.onExpansionCancelled = nil
        surface.onCollapseRequested = nil
        surface.onCollapseFinished = nil
        surface.onInteractionHoldChanged = nil
        surface.onDragOwnershipChanged = nil
        surface.onRetainedActivityRootsChanged = nil
        surface.onSettingsRequested = nil
        surface.onExpandedFrameChanged = nil
        surface.onFileDragHoverChanged = nil
        surface.onFileDrop = nil
        surface.onUnsupportedFileDrop = nil
        surface.setFileDropEnabled(false)
    }

    private func updateFileDropReadiness() {
        let isReady = contextualPage != nil && fileDropOnDrop != nil
        for record in surfaces.values {
            record.surface.setFileDropEnabled(isReady)
        }
    }

    private func handleFileDragHover(_ urls: [URL]?, on displayID: CGDirectDisplayID) {
        guard contextualPage != nil, fileDropOnDrop != nil else { return }
        if urls == nil, let nativeFileDragHoverDisplayID,
           nativeFileDragHoverDisplayID != displayID {
            return
        }
        fileDropOnHover?(urls)
        if let urls, !urls.isEmpty {
            nativeFileDragHoverDisplayID = displayID
            fileDragReleaseTask?.cancel()
            fileDragReleaseTask = nil
            fileDropLog.info("phase=hover count=\(urls.count)")
            if expandedDisplayID == displayID {
                beginFileDropPreview(on: displayID, openedForPreview: false)
                setInteractionHold(.drag, on: displayID, active: true)
                reconcilePresentations()
            } else {
                requestExpansion(on: displayID, activityID: nil, trigger: .drag)
            }
        } else {
            let endedNativeHover = nativeFileDragHoverDisplayID == displayID
            if endedNativeHover {
                nativeFileDragHoverDisplayID = nil
            }
            endFileDropPreview(keepContextual: false)
            setInteractionHold(.drag, on: displayID, active: false)
            if endedNativeHover, !isRecognizedFileDragGestureActive {
                clearRecognizedFileDrag()
            }
        }
    }

    private func handleFileDrop(_ urls: [URL], on displayID: CGDirectDisplayID) -> Bool {
        guard displayID == expandedDisplayID,
              contextualPage != nil,
              let fileDropOnDrop else { return false }
        let accepted = fileDropOnDrop(urls)
        fileDropLog.info("phase=drop accepted=\(accepted) count=\(urls.count)")
        fileDropOnHover?(nil)
        nativeFileDragHoverDisplayID = nil
        endFileDropPreview(keepContextual: accepted)
        setInteractionHold(.drag, on: displayID, active: false)
        clearRecognizedFileDrag(keepContextual: accepted)
        return accepted
    }

    private func handleUnsupportedFileDrop(on displayID: CGDirectDisplayID) {
        fileDropOnUnsupported?()
        fileDropLog.notice("phase=offer error=unsupported")
        fileDropOnHover?(nil)
        if nativeFileDragHoverDisplayID == displayID {
            nativeFileDragHoverDisplayID = nil
        }
        endFileDropPreview(keepContextual: false)
        setInteractionHold(.drag, on: displayID, active: false)
        if !isRecognizedFileDragGestureActive {
            clearRecognizedFileDrag()
        }
    }

    private func resolveFocusAndReconcile() {
        let frames = Dictionary(uniqueKeysWithValues: surfaces.map {
            ($0.key, $0.value.entry.snapshot.frame)
        })
        focusedDisplayID = FocusedDisplayResolver.resolve(
            window  : focusedWindow,
            pointer : pointerLocation,
            frames  : frames,
            previous: focusedDisplayID,
            main    : mainDisplay()
        )
        reconcilePresentations()
    }

    private func routedDisplayIDs() -> Set<CGDirectDisplayID> {
        switch preferences.activityMode {
        case .allDisplays:
            return Set(surfaces.keys)
        case .focusedDisplay:
            guard let focusedDisplayID, surfaces[focusedDisplayID] != nil else { return [] }
            return [focusedDisplayID]
        case let .fixedDisplay(identity):
            return Set(surfaces.compactMap { displayID, record in
                record.entry.identity == identity ? displayID : nil
            })
        }
    }

    private func reconcilePresentations() {
        guard isStarted else {
            return
        }
        guard !isReconciling else {
            needsReconciliation = true
            return
        }

        isReconciling = true
        repeat {
            needsReconciliation = false
            let revision = activityHost.presentationValidityRevision
            let routed = routedDisplayIDs()
            if let owner = expandedDisplayID,
               routed.contains(owner),
               latestRequests[owner]?.activityID == nil,
               case .automatic = expandedPageSelection {
                let expansion = activityHost.selection.primary.map {
                    ActivityExpansionSelection.activity($0.id)
                } ?? .fallback
                if activityHost.expansionSelection != expansion {
                    activityHost.setExpansion(expansion)
                    needsReconciliation = true
                    continue
                }
            }
            let selection = activityHost.selection
            var projections: [CGDirectDisplayID: DisplayPresentation] = [:]

            for displayID in surfaces.keys {
                let receivesActivities = routed.contains(displayID)
                let isOwner = expandedDisplayID == displayID
                let contextualIsSelected: Bool
                if case let .contextual(id, _) = expandedPageSelection {
                    contextualIsSelected = isOwner && contextualPage?.id == id
                } else {
                    contextualIsSelected = false
                }
                let expandedIsLiveActivity: Bool
                if !contextualIsSelected, case .activity = activityHost.expansionSelection {
                    expandedIsLiveActivity = isOwner && selection.expanded != nil
                } else {
                    expandedIsLiveActivity = false
                }
                projections[displayID] = DisplayPresentation(
                    primary     : receivesActivities ? selection.primary : nil,
                    secondary   : receivesActivities ? selection.secondary : nil,
                    notice      : focusedDisplayID == displayID ? selection.notice : nil,
                    expanded    : isOwner && !contextualIsSelected ? selection.expanded : nil,
                    expandedIsLiveActivity: expandedIsLiveActivity,
                    showsWidgets: isOwner && !contextualIsSelected && selection.expanded == nil,
                    contextualPage: contextualPage,
                    contextualPageIsSelected: contextualIsSelected,
                    widgetContentRevision: widgetContentRevision,
                    style       : style(for: displayID, preferences: preferences)
                )
            }

            for record in surfaces.values {
                let invalid = Set(record.surface.retainedActivityRoots.compactMap { activity in
                    activityHost.isPresentationValid(activity) ? nil : ObjectIdentifier(activity)
                })
                if !invalid.isEmpty {
                    record.surface.discardRetainedActivityRoots(invalid)
                }
            }

            let plannedRoots = projections.values.flatMap(\.visibleActivityRoots)
            let retainedRoots = surfaces.values.flatMap { $0.surface.retainedActivityRoots }
            let union = plannedRoots + retainedRoots
            let result = activityHost.setVisibleActivities(union)
            if revision != activityHost.presentationValidityRevision {
                needsReconciliation = true
                continue
            }

            let widgetsVisible = projections.values.contains { $0.showsWidgets }
            if widgetsVisible {
                widgetHost.update(state: .open)
            }
            let accepted = Set(result.accepted.map(ObjectIdentifier.init))
            for (displayID, projection) in projections {
                guard let surface = surfaces[displayID]?.surface else { continue }
                surface.applyPresentation(projection.removingInvalidRoots(
                    accepted: accepted,
                    host    : activityHost
                ))
            }
            let appliedRoots = plannedRoots
                + surfaces.values.flatMap { $0.surface.retainedActivityRoots }
            _ = activityHost.setVisibleActivities(appliedRoots)
            if revision != activityHost.presentationValidityRevision {
                needsReconciliation = true
                continue
            }
            if !widgetsVisible {
                widgetHost.update(state: .closed)
            }
        } while needsReconciliation
        isReconciling = false
    }

    private func handlePointer(at point: CGPoint) {
        pointerLocation = point
        if isRecognizedFileDragGestureActive {
            routeRecognizedFileDrag(at: point)
        }
        let pointed = surfaces.first { $0.value.entry.snapshot.frame.contains(point) }?.key
        var destinations = Set([pointed, previousPointerDisplayID, expandedDisplayID].compactMap { $0 })
        if let dragDisplayID { destinations.insert(dragDisplayID) }
        for displayID in destinations {
            surfaces[displayID]?.surface.handlePointer(at: point)
        }
        previousPointerDisplayID = pointed
        resolveFocusAndReconcile()
    }

    private func handleRecognizedFileDrag(active: Bool, at point: CGPoint) {
        guard contextualPage != nil, fileDropOnDrop != nil else { return }
        pointerLocation = point
        if active {
            if !isRecognizedFileDragGestureActive {
                fileDropLog.info("phase=begin")
            }
            fileDragGestureGeneration &+= 1
            fileDragReleaseTask?.cancel()
            fileDragReleaseTask = nil
            isRecognizedFileDragGestureActive = true
            routeRecognizedFileDrag(at: point)
        } else {
            if let displayID = recognizedFileDragDisplayID {
                surfaces[displayID]?.surface.endRecognizedFileDragGesture()
            }
            isRecognizedFileDragGestureActive = false
            guard nativeFileDragHoverDisplayID == nil else { return }
            let generation = fileDragGestureGeneration
            fileDragReleaseTask?.cancel()
            fileDragReleaseTask = Task { [weak self] in
                await Task.yield()
                guard let self,
                      !Task.isCancelled,
                      !self.isRecognizedFileDragGestureActive,
                      self.fileDragGestureGeneration == generation else { return }
                self.fileDragReleaseTask = nil
                self.clearRecognizedFileDrag()
            }
        }
    }

    private func routeRecognizedFileDrag(at point: CGPoint) {
        guard isRecognizedFileDragGestureActive,
              contextualPage != nil, fileDropOnDrop != nil else { return }
        let pointed = surfaces.first { $0.value.entry.snapshot.frame.contains(point) }?.key
        guard pointed != recognizedFileDragDisplayID else { return }
        if let previous = recognizedFileDragDisplayID {
            surfaces[previous]?.surface.setRecognizedFileDragActive(false, at: point)
        }
        recognizedFileDragDisplayID = pointed
        if let pointed {
            surfaces[pointed]?.surface.setRecognizedFileDragActive(true, at: point)
        }
    }

    private func clearRecognizedFileDrag(keepContextual: Bool = false) {
        isRecognizedFileDragGestureActive = false
        fileDragReleaseTask?.cancel()
        fileDragReleaseTask = nil
        let displayID = recognizedFileDragDisplayID
            ?? nativeFileDragHoverDisplayID
            ?? fileDropPreview?.displayID
        recognizedFileDragDisplayID = nil
        nativeFileDragHoverDisplayID = nil
        if let displayID {
            surfaces[displayID]?.surface.setRecognizedFileDragActive(false, at: pointerLocation)
            setInteractionHold(.drag, on: displayID, active: false)
        }
        endFileDropPreview(keepContextual: keepContextual)
    }

    private func handlePointerButton(isPressed: Bool) {
        if !isPressed, let dragDisplayID {
            surfaces[dragDisplayID]?.surface.handlePointerButton(isPressed: false)
            return
        }
        let pointed = surfaces.first {
            $0.value.entry.snapshot.frame.contains(pointerLocation)
        }?.key
        if let pointed {
            surfaces[pointed]?.surface.handlePointerButton(isPressed: isPressed)
        }
    }

    private func handleSpaceChange() {
        let destinations = Set([expandedDisplayID, previousPointerDisplayID].compactMap { $0 })
        for displayID in destinations {
            surfaces[displayID]?.surface.handleSpaceChange()
        }
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if !visible {
            clearRecognizedFileDrag()
            if let externalDisplayID, isExternalSurfaceActive {
                surfaces[externalDisplayID]?.surface.setExternalSurfacePresented(false)
            }
            externalDisplayID = nil
            externalReady = nil
            isExternalSurfaceActive = false
            pendingRequests.removeAll()
            pendingRequestOrder.removeAll()
            latestRequests.removeAll()
            closingDisplayID = nil
            closingGeneration = nil
            expandedDisplayID = nil
            interactionHolds.removeAll()
            interactionOwnerDisplayID = nil
            dragDisplayID = nil
            expandedPageSelection = .automatic
            pendingExplicitPageSelection = nil
            fileDropPreview = nil
            for record in surfaces.values {
                record.surface.setVisible(false)
            }
        }
        activityHost.setVisible(visible)
        if !visible { activityHost.setExpansion(.none) }
        if visible {
            for record in surfaces.values {
                record.surface.setVisible(true)
            }
        }
        reconcilePresentations()
    }

    private func activateExternalSurfaceIfReady() {
        guard isVisible, expandedDisplayID == nil || expandedDisplayID == externalDisplayID,
              !isExternalSurfaceActive,
              let displayID = externalDisplayID,
              let surface = surfaces[displayID]?.surface else { return }
        isExternalSurfaceActive = true
        surface.setExternalSurfacePresented(true)
        let ready = externalReady
        externalReady = nil
        ready?()
    }

    private func advanceExternalSurfaceReservation() {
        guard let externalDisplayID else { return }
        guard let owner = expandedDisplayID else {
            activateExternalSurfaceIfReady()
            return
        }
        guard owner != externalDisplayID else {
            activateExternalSurfaceIfReady()
            return
        }
        guard interactionOwnerDisplayID == externalDisplayID else { return }
        beginCollapse(of: owner)
    }

    private func hasInteractionHold(on displayID: CGDirectDisplayID) -> Bool {
        interactionHolds[displayID]?.isEmpty == false
    }

    private func enqueue(_ request: DisplayExpansionRequest) {
        nextRequestOrder &+= 1
        pendingRequests[request.displayID] = request
        pendingRequestOrder[request.displayID] = nextRequestOrder
    }

    private func removePendingRequest(on displayID: CGDirectDisplayID) {
        pendingRequests.removeValue(forKey: displayID)
        pendingRequestOrder.removeValue(forKey: displayID)
    }

    private func resumeNewestPendingRequest() {
        guard expandedDisplayID == nil,
              interactionOwnerDisplayID == nil else { return }
        let request = pendingRequests.values
            .filter { surfaces[$0.displayID] != nil && latestRequests[$0.displayID] == $0 }
            .max { lhs, rhs in
                (pendingRequestOrder[lhs.displayID] ?? 0)
                    < (pendingRequestOrder[rhs.displayID] ?? 0)
            }
        guard let request else {
            pendingRequests.removeAll()
            pendingRequestOrder.removeAll()
            return
        }
        grant(request)
    }

    private func heldDisplay(for kind: NotchInteractionKind) -> CGDirectDisplayID? {
        interactionHolds.first { $0.value.contains(kind) }?.key
    }

    private func style(
        for displayID : CGDirectDisplayID,
        preferences   : DisplayPresentationPreferences
    ) -> ExternalNotchStyle {
        guard let record = surfaces[displayID] else { return .notch }
        guard !record.entry.snapshot.hasHardwareNotch else { return .notch }
        return transientStyles[displayID]
            ?? record.entry.identity.map(preferences.style(for:))
            ?? .notch
    }

    private func describedStyle(for displayID: CGDirectDisplayID) -> ExternalNotchStyle {
        if let style = pendingTransientStyles[displayID] {
            return style
        }
        return style(
            for        : displayID,
            preferences: pendingPreferences ?? preferences
        )
    }
}
