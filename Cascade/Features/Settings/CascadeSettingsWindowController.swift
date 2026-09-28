//
//  CascadeSettingsWindowController.swift
//  Cascade
//

import AppKit
import SwiftUI

/// CascadeSettingsPresenting keeps native window ownership out of the services.
@MainActor
protocol CascadeSettingsPresenting: AnyObject {
    func show(
        services  : CascadeServices,
        notchFrame: CGRect
    )
    func updateNotchFrame(_ frame: CGRect?)
    func close()
}

/// CascadeSettingsWindowController owns one reusable settings window. Key-window
/// callbacks hold the notch open only for the lifetime of keyboard focus.
@MainActor
final class CascadeSettingsWindowController: NSWindowController, CascadeSettingsPresenting, NSWindowDelegate {
    private let onFocusChanged: (Bool) -> Void
    private let onPresentationChanged: (Bool) -> Void
    private var notchFrame: CGRect?
    private var isConstraining = false
    private var isPresentationReported = false

    init(
        onFocusChanged       : @escaping (Bool) -> Void,
        onPresentationChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onFocusChanged        = onFocusChanged
        self.onPresentationChanged = onPresentationChanged
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    func show(
        services  : CascadeServices,
        notchFrame: CGRect
    ) {
        self.notchFrame = notchFrame
        if window == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 760, height: 570),
                styleMask  : [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing    : .buffered,
                defer      : false
            )
            window.title = "Impostazioni di Cascade"
            window.identifier = NSUserInterfaceItemIdentifier("cascade.settings")
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.collectionBehavior = [.fullScreenAuxiliary, .fullScreenNone]
            let hosting = NSHostingController(rootView: CascadeSettingsView(services: services))
            // Assigning a content controller adopts its fitting size. Keep
            // AppKit in charge, then restore the intended size before anchoring.
            hosting.sizingOptions = []
            window.contentViewController = hosting
            window.setContentSize(CGSize(width: 760, height: 570))
            window.delegate = self
            self.window = window
        }
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        var frame = window.frame
        frame.origin = CGPoint(x: notchFrame.midX - frame.width / 2, y: notchFrame.minY - 8 - frame.height)
        window.setFrame(frame, display: false)
        constrainWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !isPresentationReported {
            isPresentationReported = true
            onPresentationChanged(true)
        }
        onFocusChanged(window.isKeyWindow)
    }

    /// updateNotchFrame follows geometry while preserving the invocation
    /// anchor through an ordinary collapse, such as a display-style change.
    func updateNotchFrame(_ frame: CGRect?) {
        guard let frame else { return }
        notchFrame = frame
        if window?.isVisible == true { constrainWindow() }
    }

    override func close() {
        onFocusChanged(false)
        reportPresentationEnded()
        super.close()
    }

    func windowDidBecomeKey(_ notification: Notification) { onFocusChanged(true) }
    func windowDidResignKey(_ notification: Notification) { onFocusChanged(false) }
    func windowWillClose(_ notification: Notification) {
        onFocusChanged(false)
        reportPresentationEnded()
    }
    func windowDidMove(_ notification: Notification) { constrainWindow() }
    func windowDidResize(_ notification: Notification) { constrainWindow() }

    /// constrainWindow responds to AppKit events rather than installing a timer.
    /// It also caps resizing, including zoom, at the area below the notch.
    private func constrainWindow() {
        guard !isConstraining, let window, let notchFrame,
              let screen = NSScreen.screens.first(where: {
                  $0.frame.contains(CGPoint(x: notchFrame.midX, y: notchFrame.maxY - 1))
              }) else { return }
        isConstraining = true
        defer { isConstraining = false }
        let available = screen.visibleFrame
        let maxHeight = max(0, min(available.maxY, notchFrame.minY - 8) - available.minY)
        window.minSize = CGSize(width: min(620, available.width), height: min(420, maxHeight))
        window.maxSize = CGSize(width: available.width, height: maxHeight)
        let frame = SettingsWindowPlacement.constrain(window.frame, below: notchFrame, within: available)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }

    private func reportPresentationEnded() {
        guard isPresentationReported else { return }
        isPresentationReported = false
        onPresentationChanged(false)
    }
}
