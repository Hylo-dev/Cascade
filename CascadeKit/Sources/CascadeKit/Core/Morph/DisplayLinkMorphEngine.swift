//
//  DisplayLinkMorphEngine.swift
//  CascadeKit
//

import AppKit
import QuartzCore

/// DisplayLinkMorphEngine drives the morph from a `CADisplayLink`, so frames
/// land in lock-step with the display — 120 Hz on ProMotion, whatever the
/// panel's screen actually runs.
///
/// On macOS a display link is vended by a view (`NSView.displayLink(target:
/// selector:)`, macOS 14+), so we hold the host view the notch is drawn in and
/// create the link from it. We invalidate the link the moment the morph
/// settles: a display link left running is a wakeup every single frame forever,
/// and on battery that is not acceptable.
final class DisplayLinkMorphEngine: MorphEngineDriving {

    private weak var view     : NSView?
    private var link          : CADisplayLink?
    private var onFrame       : ((CFTimeInterval) -> Void)?
    private var lastTimestamp : CFTimeInterval = 0

    init(view: NSView) {
        self.view = view
    }

    var isRunning: Bool {
        link != nil
    }

    func start(onFrame: @escaping (CFTimeInterval) -> Void) {

        guard link == nil, let view else {
            return
        }

        self.onFrame       = onFrame
        self.lastTimestamp = 0

        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link          = nil
        onFrame       = nil
        lastTimestamp = 0
    }

    deinit {
        stop()
    }

    @objc
    private func tick(_ link: CADisplayLink) {

        // The first tick after a (re)start has no previous timestamp; assume a
        // nominal 120 Hz frame so the spring takes a sane first step.
        let delta = lastTimestamp == 0
            ? 1.0 / 120.0
            : link.timestamp - lastTimestamp

        lastTimestamp = link.timestamp
        onFrame?(delta)
    }
}
