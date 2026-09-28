//
//  RuntimeClock.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeClock supplies trusted synchronous wall and monotonic time samples.
protocol RuntimeClock: Sendable {
    func now() -> RuntimeInstant
}
