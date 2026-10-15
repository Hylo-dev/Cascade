//
//  NetworkPathMonitoring.swift
//  CascadeKit
//

import Dispatch

/// NetworkPathMonitoring is the system's network path monitor as the network source sees it:
/// started once on a queue, it hands that queue every path it reports, reduced to a snapshot,
/// until it is cancelled, after which it cannot start again. It is a protocol so the source can
/// be tested against a fake monitor, without the Network framework.
protocol NetworkPathMonitoring {

    /// start begins reporting paths on `queue`, the current one first.
    func start(
        queue   : DispatchQueue,
        onUpdate: @escaping @Sendable (NetworkPathSnapshot) -> Void
    )

    /// cancel stops reporting; an update the system had already queued may still arrive.
    func cancel()
}
