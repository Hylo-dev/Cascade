//
//  NotchController.swift
//  CascadeKit
//

import AppKit
import Observation
import os
import QuartzCore

/// NotchController is the brain of the notch: it owns the discrete state, wires
/// the event monitor to the morph, and runs the per-frame spring math.
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
final class NotchController {

    private(set) var state        : NotchState = .closed
    private(set) var activeDisplay: ActiveDisplay?

    @ObservationIgnored private let configuration: NotchConfiguration
    @ObservationIgnored private let resolver     : ActiveDisplayResolving
    @ObservationIgnored private let monitor      : EventMonitoring
    @ObservationIgnored private let morphEngine  : MorphEngineDriving
    @ObservationIgnored private let panel        : NotchPanel
    @ObservationIgnored private let hostView     : NotchHostView

    @ObservationIgnored private var leadingSpring : Spring
    @ObservationIgnored private var trailingSpring: Spring

    @ObservationIgnored
    private let log = Logger(subsystem: "hylo.Cascade", category: "NotchController")

    /// Slack (in points) added around the stay-open region. It absorbs pointer
    /// jitter at the edges and — crucially — extends the region past the very
    /// top of the screen: a half-open `CGRect` excludes its `maxY` edge, so
    /// without this the topmost pixel row would read as "outside" and snap the
    /// notch shut the moment the pointer reaches the screen edge.
    @ObservationIgnored private let hoverHysteresis: CGFloat = 8

    @ObservationIgnored private let widgetHost = WidgetHost()

    init(
        configuration: NotchConfiguration,
        resolver     : ActiveDisplayResolving,
        monitor      : EventMonitoring,
        morphEngine  : MorphEngineDriving,
        panel        : NotchPanel,
        hostView     : NotchHostView
    ) {
        self.configuration  = configuration
        self.resolver       = resolver
        self.monitor        = monitor
        self.morphEngine    = morphEngine
        self.panel          = panel
        self.hostView       = hostView
        self.leadingSpring  = Spring(parameters: configuration.spring)
        self.trailingSpring = Spring(parameters: configuration.spring)
    }

    // MARK: - Lifecycle

    /// Resolve the active display, place the panel, and start listening.
    func start() {

        hostView.setChromeColor(configuration.chromeColor)

        widgetHost.onContentChanged = { [weak self] in
            self?.renderContent()
        }

        refreshActiveDisplay()

        monitor.onPointerMoved = { [weak self] location in
            self?.handlePointer(at: location)
        }

        monitor.onActiveDisplayMayHaveChanged = { [weak self] in
            self?.refreshActiveDisplay()
        }

        monitor.start()
        panel.orderFrontRegardless()

        log.notice("Notch started. panel=\(NSStringFromRect(self.panel.frame), privacy: .public) visible=\(self.panel.isVisible, privacy: .public) level=\(self.panel.level.rawValue, privacy: .public)")
    }

    /// Hide the overlay and stop all observation and animation.
    func stop() {
        monitor.stop()
        morphEngine.stop()
        panel.orderOut(nil)
    }

    /// Register a widget with the host. Safe to call before or after `start()`.
    func register(_ widget: NotchWidget) {
        widgetHost.register(widget)
    }

    // MARK: - Active display

    /// Re-resolve which screen we follow; only re-place the panel when the
    /// screen actually changed — the coalescing the project insists on, so a
    /// mouse drifting within one screen never triggers window work.
    private func refreshActiveDisplay() {

        guard let display = resolver.resolveActiveDisplay() else {
            return
        }

        let didChange = display.displayID != activeDisplay?.displayID

        activeDisplay = display

        log.notice("Active display \(display.displayID, privacy: .public) frame=\(NSStringFromRect(display.frame), privacy: .public) hasHardwareNotch=\(display.hasHardwareNotch, privacy: .public) changed=\(didChange, privacy: .public)")

        guard didChange else {
            return
        }

        layoutPanel(for: display)
        renderCurrentFrame()
    }

    /// Park the panel as a fixed band across the top of the active screen. The
    /// band is tall enough for a fully expanded notch, so it never resizes while
    /// morphing — only the layer path moves, which is cheap.
    private func layoutPanel(for display: ActiveDisplay) {

        let bandHeight = configuration.expandedHeight
        let frame      = CGRect(
            x     : display.frame.minX,
            y     : display.frame.maxY - bandHeight,
            width : display.frame.width,
            height: bandHeight
        )

        panel.setFrame(frame, display: true)
        hostView.frame = CGRect(origin: .zero, size: frame.size)
    }

    // MARK: - Interaction

    /// Decide whether the pointer at `location` should open or close the notch.
    /// While closed we open when the pointer enters the resting trigger band;
    /// while open we close only when it leaves the *expanded* region, so sliding
    /// down into the open notch does not immediately snap it shut.
    private func handlePointer(at location: CGPoint) {

        guard let display = activeDisplay else {
            return
        }

        if state.isClosed {
            if restingTriggerZone(for: display).contains(location) {
                setState(.open)
            }
        } else {
            // Inset negatively to grow the region, so the top screen edge and a
            // little slack around the island all count as "still hovering".
            let stayOpen = expandedRegion(for: display)
                .insetBy(dx: -hoverHysteresis, dy: -hoverHysteresis)

            if !stayOpen.contains(location) {
                setState(.closed)
            }
        }
    }

    /// The top-center trigger band, in AppKit global coordinates. It exists
    /// whether or not a hardware notch is drawn there.
    private func restingTriggerZone(for display: ActiveDisplay) -> CGRect {

        let size = restingSize(for: display)

        return CGRect(
            x     : display.frame.midX - size.width / 2,
            y     : display.frame.maxY - size.height,
            width : size.width,
            height: size.height
        )
    }

    /// The fully expanded footprint, in AppKit global coordinates. Used as the
    /// "stay open" region so the notch only closes when the pointer truly
    /// leaves it.
    private func expandedRegion(for display: ActiveDisplay) -> CGRect {

        CGRect(
            x     : display.frame.midX - configuration.expandedHalfWidth,
            y     : display.frame.maxY - configuration.expandedHeight,
            width : configuration.expandedHalfWidth * 2,
            height: configuration.expandedHeight
        )
    }

    // MARK: - State & morph

    /// Apply a new discrete state and make sure the morph engine is running to
    /// animate toward it. Starting the engine is idempotent.
    private func setState(_ newState: NotchState) {

        guard newState != state else {
            return
        }

        state = newState
        widgetHost.update(state: newState)
        renderContent()
        startMorphIfNeeded()
    }

    private func startMorphIfNeeded() {

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

        let leadingTarget : Double = state.contains(.leading)  ? 1 : 0
        let trailingTarget: Double = state.contains(.trailing) ? 1 : 0

        leadingSpring.advance(toward: leadingTarget,  dt: dt)
        trailingSpring.advance(toward: trailingTarget, dt: dt)

        renderCurrentFrame()

        if leadingSpring.isSettled(at: leadingTarget),
           trailingSpring.isSettled(at: trailingTarget) {

            leadingSpring.snap(to: leadingTarget)
            trailingSpring.snap(to: trailingTarget)

            renderCurrentFrame()
            morphEngine.stop()
        }
    }

    /// Resolve the current geometry from the springs and hand it to the host
    /// view. Cheap and allocation-light, safe to call every frame.
    private func renderCurrentFrame() {

        guard let display = activeDisplay else {
            return
        }

        let resting = restingSize(for: display)

        let geometry = NotchGeometry.resolve(
            configuration   : configuration,
            restingHalfWidth: resting.width / 2,
            restingHeight   : resting.height,
            leadingProgress : CGFloat(leadingSpring.value),
            trailingProgress: CGFloat(trailingSpring.value)
        )

        // The notch hangs from the top of the host view; in the view's own
        // (non-flipped) coordinates that is `bounds.maxY`, centered.
        hostView.apply(
            geometry       : geometry,
            centerX        : hostView.bounds.midX,
            topY           : hostView.bounds.maxY,
            isChromeVisible: shouldDrawChrome(for: display)
        )
    }

    /// The resting size: the measured hardware notch where one exists, the
    /// configured fallback band where it does not.
    private func restingSize(for display: ActiveDisplay) -> CGSize {
        display.hasHardwareNotch
            ? display.notch.size
            : configuration.fallbackRestingSize
    }

    /// Whether to draw the chrome on this display. Production draws only where a
    /// hardware notch exists; the dev flag forces it on so the overlay is
    /// visible while building on a notch-less screen.
    private func shouldDrawChrome(for display: ActiveDisplay) -> Bool {
        display.hasHardwareNotch || configuration.drawsChromeWithoutHardwareNotch
    }

    /// Show the widgets inside the open notch and hide them when it closes.
    ///
    /// The content lives in its own hosting view above the chrome, placed in the
    /// expanded interior and inset so it sits inside the rounded shape. It is a
    /// discrete swap on state change — not part of the per-frame morph loop — so
    /// it never touches the 120 Hz path.
    private func renderContent() {

        guard activeDisplay != nil else {
            return
        }

        let width  = configuration.expandedHalfWidth * 2
        let height = configuration.expandedHeight

        let interior = CGRect(
            x     : hostView.bounds.midX - width / 2,
            y     : hostView.bounds.maxY - height,
            width : width,
            height: height
        )
        .insetBy(dx: 20, dy: 16)

        hostView.setContent(
            widgetHost.makeContentView(),
            frame    : interior,
            isVisible: !state.isClosed
        )
    }
}
