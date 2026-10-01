//
//  LifecycleClock.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeAddonSDK
@testable import CascadeRuntime

final class LifecycleClock: RuntimeClock, @unchecked Sendable {

    private let lock    = NSLock()
    private var instant = RuntimeInstant(
        wall     : Date(timeIntervalSince1970: 2_000_000_000),
        monotonic: .seconds(10)
    )

    func now() -> RuntimeInstant { lock.withLock { instant } }

    func advance(seconds: Int) {
        lock.withLock {
            instant = RuntimeInstant(
                wall     : instant.wall.addingTimeInterval(Double(seconds)),
                monotonic: instant.monotonic + .seconds(seconds)
            )
        }
    }
}
