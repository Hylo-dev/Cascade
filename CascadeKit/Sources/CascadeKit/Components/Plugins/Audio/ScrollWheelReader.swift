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
struct ScrollWheelReader: NSViewRepresentable {

    let onScroll: (_ deltaY: Double, _ isPrecise: Bool, _ phase: NSEvent.Phase, _ momentum: NSEvent.Phase) -> Void

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
            Double(event.scrollingDeltaY),
            event.hasPreciseScrollingDeltas,
            event.phase,
            event.momentumPhase
        )
    }
}
