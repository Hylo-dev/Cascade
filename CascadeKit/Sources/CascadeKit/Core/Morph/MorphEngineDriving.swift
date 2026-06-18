//
//  MorphEngineDriving.swift
//  CascadeKit
//

import QuartzCore

/// MorphEngineDriving turns "the notch is morphing" into a stream of frame
/// ticks, and — crucially — stops itself when there is nothing left to animate.
///
/// It is a protocol so the controller can be stepped deterministically in tests
/// (a fake engine that calls `onFrame` with fixed deltas) instead of waiting on
/// a real display link.
protocol MorphEngineDriving: AnyObject {

    /// Whether a frame stream is currently running.
    var isRunning: Bool { get }

    /// Begin ticking. `onFrame` is called once per display refresh with the
    /// elapsed time since the previous tick, on the main thread.
    func start(onFrame: @escaping (CFTimeInterval) -> Void)

    /// Stop ticking and release the underlying timer. Called the instant the
    /// morph settles, so an idle notch holds no display link.
    func stop()
}
