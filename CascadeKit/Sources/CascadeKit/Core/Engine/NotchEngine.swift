//
//  NotchEngine.swift
//  CascadeKit
//

import AppKit

/// NotchEngine wires the notch's parts together and is the single entry point
/// the app shell touches. Construct it once, call `start()`, and keep it alive.
///
/// It owns the object graph — panel, host view, resolver, event monitor, morph
/// engine and controller — and injects each concrete piece behind its protocol.
/// Swapping a resolver or a morph engine (for tests, or a different strategy)
/// therefore means changing this one place and nothing else.
@MainActor
public final class NotchEngine {

    private let panel     : NotchPanel
    private let hostView  : NotchHostView
    private let controller: NotchController

    public init(configuration: NotchConfiguration = .default) {

        let hostView = NotchHostView(frame: .zero)
        let panel    = NotchPanel(contentView: hostView)

        let resolver     = SafeAreaNotchDetector()
        let monitor      = MouseEventMonitor()
        let morphEngine  = DisplayLinkMorphEngine(view: hostView)
        let windowPinner = SkyLightWindowPinner()

        self.hostView   = hostView
        self.panel      = panel
        self.controller = NotchController(
            configuration: configuration,
            resolver     : resolver,
            monitor      : monitor,
            morphEngine  : morphEngine,
            panel        : panel,
            hostView     : hostView,
            windowPinner : windowPinner
        )
    }

    /// Register a widget. Call before `start()` so it is live the first time its
    /// region opens. Widgets are decoupled — the engine only knows the protocol.
    public func register(_ widget: NotchWidget) {
        controller.register(widget)
    }

    /// Show the overlay and begin following the active display.
    public func start() {
        controller.start()
    }

    /// Hide the overlay and stop all observation and animation.
    public func stop() {
        controller.stop()
    }
}
