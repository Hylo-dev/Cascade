//
//  RuntimeClock.swift
//  CascadeKit
//

/// RuntimeClock supplies trusted synchronous wall and monotonic time samples.
protocol RuntimeClock: Sendable {

    func now() -> RuntimeInstant
}
