//
//  Clock.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneFocusProvider
import Testing

final class Clock: @unchecked Sendable {

    private let lock  = NSLock()
    private var value = Date(timeIntervalSince1970: 2_000_000_000)

    func now() -> Date { lock.withLock { value } }

    func advance(_ seconds: Double) { lock.withLock { value.addTimeInterval(seconds) } }
}
