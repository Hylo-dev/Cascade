//
//  Spring.swift
//  CascadeKit
//

import Foundation

/// Spring is the allocation-free integrator that drives one side of the morph.
///
/// It is a damped harmonic oscillator solved with semi-implicit Euler: each
/// frame we pull `value` toward a target with `stiffness`, bleed velocity with
/// `damping`, and step by the frame's `dt`. Everything is plain `Double` math
/// on a `@frozen` value, so a `Spring` lives on the stack and the per-frame
/// `advance` never touches the heap or ARC — which is the whole point on the
/// 120 Hz path.
nonisolated struct Spring {

    private(set) var value   : Double
    private(set) var velocity: Double

    let parameters: SpringParameters

    init(
        value     : Double = 0,
        parameters: SpringParameters
    ) {
        self.value      = value
        self.velocity   = 0
        self.parameters = parameters
    }

    /// Step the spring one frame toward `target`.
    ///
    /// `dt` is clamped before use: after the display link pauses (an idle
    /// notch), the first frame's delta can be huge, and an unclamped step would
    /// make the spring explode. Clamping to a sane maximum keeps the
    /// integration stable without a real cost in normal frames.
    mutating func advance(
        toward target: Double,
        dt           : Double
    ) {
        let step  = min(max(dt, 0), 1.0 / 30.0)
        let force = -parameters.stiffness * (value - target) - parameters.damping * velocity

        velocity += force * step
        value    += velocity * step
    }

    /// Whether the spring has effectively reached `target` and stopped moving.
    ///
    /// Both the position error and the velocity must fall under the rest
    /// threshold. The morph engine stops the display link once every spring is
    /// settled, so this predicate is what lets an idle notch cost zero CPU.
    func isSettled(at target: Double) -> Bool {
        abs(value - target) < parameters.restThreshold &&
        abs(velocity)       < parameters.restThreshold
    }

    /// Snap immediately to `value`, killing velocity. Used when the notch
    /// should jump rather than animate — e.g. when it moves to a new screen.
    mutating func snap(to value: Double) {
        self.value    = value
        self.velocity = 0
    }
}
