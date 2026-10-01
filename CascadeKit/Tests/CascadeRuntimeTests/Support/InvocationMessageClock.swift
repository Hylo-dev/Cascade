//
//  InvocationMessageClock.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

final class InvocationMessageClock: RuntimeClock, @unchecked Sendable {

    private let lock  = NSLock()
    private var value = RuntimeInstant(wall: Date(timeIntervalSince1970: 1_000), monotonic: .zero)

    func now() -> RuntimeInstant { lock.withLock { value } }

    func advance(_ seconds: Double) {
        lock.withLock {
            value = RuntimeInstant(
                wall     : value.wall.addingTimeInterval(seconds),
                monotonic: value.monotonic + .seconds(seconds)
            )
        }
    }
}
