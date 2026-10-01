//
//  TransferClock.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

final class TransferClock: RuntimeClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value = RuntimeInstant(
        wall     : Date(timeIntervalSince1970: 0),
        monotonic: .zero
    )
    private var samples = 0
    private var wantedSample = 0
    private var arrival: CheckedContinuation<Void, Never>?
    func now() -> RuntimeInstant {
        lock.withLock {
            samples += 1
            if samples >= wantedSample {
                arrival?.resume()
                arrival = nil
            }
            return value
        }
    }
    func reached(_ count: Int) async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if samples >= count { continuation.resume() }
                else {
                    wantedSample = count
                    arrival = continuation
                }
            }
        }
    }
    func set(
        _ monotonic: Duration,
        wall: Double = 0
    ) {
        lock.withLock { value = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: wall),
            monotonic: monotonic
        ) }
    }
}
