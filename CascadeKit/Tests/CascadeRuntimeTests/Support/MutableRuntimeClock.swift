//
//  MutableRuntimeClock.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class MutableRuntimeClock: RuntimeClock, @unchecked Sendable {

    private var instant: RuntimeInstant

    init(instant: RuntimeInstant) {
        self.instant = instant
    }

    func now() -> RuntimeInstant { instant }

    func set(_ instant: RuntimeInstant) {
        self.instant = instant
    }
}
