//
//  CivilClock.swift
//  ServiceConsumer
//

import Foundation
import Testing
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract
import FocusSessionsExampleProvider

final class CivilClock: @unchecked Sendable {

    private let lock  = NSLock()
    private var value = instant

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(to date: Date) {
        lock.lock()
        defer { lock.unlock() }
        value = date
    }
}
