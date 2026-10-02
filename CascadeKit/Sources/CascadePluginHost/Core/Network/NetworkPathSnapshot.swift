//
//  NetworkPathSnapshot.swift
//  CascadeKit
//

import CascadeContracts
import Network

/// NetworkPathSnapshot is what the network source keeps of an `NWPath`: whether it is
/// satisfied, the kinds of link it uses, and the system's expensive and constrained flags. It
/// is copied out on the monitor's queue, so no path object outlives its callback, and it is
/// plain values, so the source's tests build it without the Network framework.
struct NetworkPathSnapshot: Sendable {

    let isSatisfied      : Bool
    let usesWifi         : Bool
    let usesWiredEthernet: Bool
    let usesCellular     : Bool
    let isExpensive      : Bool
    let isConstrained    : Bool

    /// state is the snapshot as plugins see it. A path that is not satisfied is offline, with no
    /// interface and neither flag, whatever links it still lists; one that uses several links
    /// names the first of Wi-Fi, Ethernet and cellular. A Mac on an iPhone's hotspot is on
    /// Wi-Fi, and only the expensive flag tells it apart.
    var state: PluginNetworkState {
        guard isSatisfied else {
            return PluginNetworkState(isConnected: false, interface: .none, isExpensive: false, isConstrained: false)
        }

        let interface: PluginNetworkInterface = if usesWifi {
            .wifi
        } else if usesWiredEthernet {
            .ethernet
        } else if usesCellular {
            .cellular
        } else {
            .other
        }

        return PluginNetworkState(
            isConnected  : true,
            interface    : interface,
            isExpensive  : isExpensive,
            isConstrained: isConstrained
        )
    }
}

extension NetworkPathSnapshot {

    /// init(_:) copies a path's properties; asking whether it uses a link reads no network name.
    init(_ path: NWPath) {
        self.init(
            isSatisfied      : path.status == .satisfied,
            usesWifi         : path.usesInterfaceType(.wifi),
            usesWiredEthernet: path.usesInterfaceType(.wiredEthernet),
            usesCellular     : path.usesInterfaceType(.cellular),
            isExpensive      : path.isExpensive,
            isConstrained    : path.isConstrained
        )
    }
}
