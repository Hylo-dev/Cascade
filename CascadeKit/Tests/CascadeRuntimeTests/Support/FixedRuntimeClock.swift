//
//  FixedRuntimeClock.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

struct FixedRuntimeClock: RuntimeClock {

    let instant: RuntimeInstant

    func now() -> RuntimeInstant { instant }
}
