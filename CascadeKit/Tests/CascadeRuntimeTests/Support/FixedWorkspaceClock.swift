//
//  FixedWorkspaceClock.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

struct FixedWorkspaceClock: RuntimeClock {

    let instant: RuntimeInstant

    init(_ instant: RuntimeInstant) {
        self.instant = instant
    }

    func now() -> RuntimeInstant { instant }
}
