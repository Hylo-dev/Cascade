//
//  RecordingFocusedWindowTransport.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

nonisolated final class RecordingFocusedWindowTransport: FocusedWindowTransport, @unchecked Sendable {

    private typealias Completion = @Sendable (FocusedWindowTransportResult) -> Void

    private let lock = NSLock()

    private var changeHandler: (@Sendable () -> Void)?
    private var completions  : [Completion?] = []
    private var processIDs   : [pid_t?] = []

    var requestCount: Int {
        lock.withLock { completions.count }
    }

    var requestedProcessIDs: [pid_t?] {
        lock.withLock { processIDs }
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        lock.withLock { changeHandler = onChange }
    }

    func requestSnapshot(
        processID : pid_t?,
        completion: @escaping @Sendable (FocusedWindowTransportResult) -> Void
    ) {
        lock.withLock {
            processIDs.append(processID)
            completions.append(completion)
        }
    }

    func stop() {
        lock.withLock { changeHandler = nil }
    }

    func sendObservedChange() {
        let handler = lock.withLock { changeHandler }
        handler?()
    }

    func completeRequest(
        at index: Int,
        result  : FocusedWindowTransportResult
    ) {
        let completion = lock.withLock { () -> Completion? in
            guard completions.indices.contains(index) else {
                return nil
            }

            let completion = completions[index]
            completions[index] = nil
            return completion
        }
        completion?(result)
    }
}
