//
//  TestClock.swift
//  CascadeKit
//

import Foundation
import Synchronization

/// TestClock is the clock a time-dependent plugin is given in tests: it reads `now` until the
/// test moves it, so a test can step over a midnight without waiting for one.
final class TestClock: Sendable {

    private let date: Mutex<Date>

    init(_ date: Date) {
        self.date = Mutex(date)
    }

    var now: Date {
        date.withLock { $0 }
    }

    func move(to date: Date) {
        self.date.withLock { $0 = date }
    }
}
