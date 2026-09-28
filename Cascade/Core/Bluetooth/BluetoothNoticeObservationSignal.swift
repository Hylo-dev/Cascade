//
//  BluetoothNoticeObservationSignal.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// BluetoothNoticeObservationSignal bridges the C callback to one coalesced asynchronous event.
nonisolated final class BluetoothNoticeObservationSignal: @unchecked Sendable {
    // Cancellation is the only mutable state crossing actors. The lock is never held during AX work.
    private let cancellationLock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        cancellationLock.withLock { cancelled }
    }

    func cancel() {
        cancellationLock.withLock { cancelled = true }
        continuation.finish()
    }

    let events       : AsyncStream<Void>
    let continuation : AsyncStream<Void>.Continuation

    init() {
        let stream = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = stream.stream
        continuation = stream.continuation
    }
}
