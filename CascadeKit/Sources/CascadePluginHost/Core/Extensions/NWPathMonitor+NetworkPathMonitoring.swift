//
//  NWPathMonitor+NetworkPathMonitoring.swift
//  CascadeKit
//

import Network

/// NWPathMonitor is the real path monitor behind the network source. Its handler runs on the
/// queue it starts on and reduces each path to a snapshot there; `cancel` is its own.
extension NWPathMonitor: NetworkPathMonitoring {

    func start(
        queue   : DispatchQueue,
        onUpdate: @escaping @Sendable (NetworkPathSnapshot) -> Void
    ) {
        pathUpdateHandler = { path in onUpdate(NetworkPathSnapshot(path)) }
        start(queue: queue)
    }
}
