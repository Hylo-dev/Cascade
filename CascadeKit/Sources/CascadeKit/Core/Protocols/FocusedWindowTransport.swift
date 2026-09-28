//
//  FocusedWindowTransport.swift
//  CascadeKit
//

import AppKit

/// FocusedWindowTransport isolates every cross-process AX operation behind one
/// injectable worker-only boundary.
nonisolated protocol FocusedWindowTransport: AnyObject, Sendable {

    func start(onChange: @escaping @Sendable () -> Void)

    func requestSnapshot(
        processID : pid_t?,
        completion: @escaping @Sendable (FocusedWindowTransportResult) -> Void
    )

    func stop()
}
