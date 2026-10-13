//
//  ScrollWheelReader.swift
//  CascadeKit
//

import AppKit
import SwiftUI

/// ScrollWheelReader tells its owner about the scroll events that happen over its frame, without
/// taking part in them. SwiftUI has no scroll-wheel input, and a widget tile sits inside a board
/// that must keep every click and drag, so this is a bystander: its view never hit-tests, and its
/// monitor returns every event unchanged.
///
/// The monitor lives only while the view is in a window. A local monitor is process-wide and runs
/// on every scroll event the app receives, so one left installed by a view that was removed from
/// the board would cost that work for nothing. It is installed in `viewDidMoveToWindow` and
/// removed when the window goes nil, and again in `deinit` in case the window never said so.
/// Events for another window, or outside the frame, are ignored after one comparison.
///
/// The delta it reports is the physical one: positive when the fingers move up the trackpad, or
/// the wheel rolls away from the user, whatever the user's scrolling-direction setting. See
/// `physicalDeltaY`.
struct ScrollWheelReader: NSViewRepresentable {

    let onScroll: (_ deltaY: Double, _ isPrecise: Bool, _ phase: NSEvent.Phase, _ momentum: NSEvent.Phase) -> Void

    /// physicalDeltaY undoes the user's scrolling-direction setting. With natural scrolling macOS
    /// flips the sign of `scrollingDeltaY` so that content follows the fingers, which means a
    /// swipe up arrives negative; a volume control wants the gesture itself, not the content's
    /// motion, so it asks the event whether the device direction was inverted and flips it back.
    /// Upward is positive, with natural scrolling on or off, on a trackpad or a wheel.
    static func physicalDeltaY(
        _ deltaY           : Double,
        isDirectionInverted: Bool
    ) -> Double {
        isDirectionInverted ? -deltaY : deltaY
    }

    func makeNSView(context: Context) -> ScrollWheelView {
        ScrollWheelView()
    }

    func updateNSView(
        _ view : ScrollWheelView,
        context: Context
    ) {
        view.onScroll = onScroll
    }

    static func dismantleNSView(
        _ view     : ScrollWheelView,
        coordinator: ()
    ) {
        view.removeMonitor()
    }
}

final class ScrollWheelView: NSView {

    var onScroll: ((_ deltaY: Double, _ isPrecise: Bool, _ phase: NSEvent.Phase, _ momentum: NSEvent.Phase) -> Void)?

    private nonisolated(unsafe) var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard
            let window,
            event.window === window,
            bounds.contains(convert(event.locationInWindow, from: nil))
        else { return }

        onScroll?(
            ScrollWheelReader.physicalDeltaY(
                Double(event.scrollingDeltaY),
                isDirectionInverted: event.isDirectionInvertedFromDevice
            ),
            event.hasPreciseScrollingDeltas,
            event.phase,
            event.momentumPhase
        )
    }
}
