//
//  SpringParameters.swift
//  CascadeKit
//

import Foundation

/// SpringParameters tunes the damped spring that drives the morph. It is pure
/// data — the integrator lives in `Spring` (Core) — so the numbers can be
/// stored, themed and unit-tested without pulling in any framework.
///
/// `stiffness` pulls the value toward the target; `damping` bleeds off velocity
/// so the morph settles instead of ringing forever. `restThreshold` is how
/// close (in both position and velocity) counts as "settled": the morph engine
/// stops the display link once every spring is settled, and that is exactly
/// what keeps an idle notch off the CPU.
@frozen
public nonisolated struct SpringParameters: Sendable {

    public let stiffness    : Double
    public let damping      : Double
    public let restThreshold: Double

    public init(
        stiffness    : Double,
        damping      : Double,
        restThreshold: Double
    ) {
        self.stiffness     = stiffness
        self.damping       = damping
        self.restThreshold = restThreshold
    }

    /// A snappy, barely-overshooting morph that settles quickly.
    public static let snappy = SpringParameters(
        stiffness    : 240.0,
        damping      : 28.0,
        restThreshold: 0.001
    )
}
