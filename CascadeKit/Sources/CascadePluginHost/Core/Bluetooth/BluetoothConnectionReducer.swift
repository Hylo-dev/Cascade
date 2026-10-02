//
//  BluetoothConnectionReducer.swift
//  CascadeKit
//

import Foundation

/// BluetoothConnectionReducer turns noisy framework callbacks into real
/// connection transitions.
///
/// IOBluetooth can deliver the same callback more than once. The reducer keeps
/// one compact snapshot per connected address, suppresses duplicates, and lets
/// startup and wake reconciliation replace the baseline without emitting old
/// events.
struct BluetoothConnectionReducer {

    private var connectedDevicesByID     : [String: BluetoothConnectedDevice] = [:]
    private var connectionOrder          : [String]                           = []
    private var connectionEventsByID     : [String: BluetoothConnectionEvent] = [:]
    private var pendingInitialAudioRoutes: [String: TimeInterval]             = [:]

    /// connectedDevices lists the devices connected now, in the order they
    /// connected. A handful at most, so the order is a plain array of
    /// addresses beside the snapshots.
    var connectedDevices: [BluetoothConnectedDevice] {
        connectionOrder.compactMap { connectedDevicesByID[$0] }
    }

    /// replaceBaseline records the devices already connected at startup or
    /// wake. Its lack of a return value is deliberate: baseline devices are
    /// state, not new user-visible connections. A device still connected
    /// keeps its place in the order, since the framework reads the connected
    /// devices in no particular order; the others follow as it read them.
    ///
    /// The framework's snapshot carries no battery or identity, so a device
    /// still connected keeps what was known of it until the wake's own read
    /// of it answers. Without that, every wake would list it without a
    /// battery for a moment and emit the same list twice.
    mutating func replaceBaseline(with devices: [BluetoothConnectedDevice]) {
        let known = connectedDevicesByID
        connectedDevicesByID.removeAll(keepingCapacity: true)
        connectionEventsByID.removeAll(keepingCapacity: true)
        pendingInitialAudioRoutes.removeAll(keepingCapacity: true)

        for device in devices {
            connectedDevicesByID[device.deviceID] = known[device.deviceID].map { prior in
                device.enriched(with: BluetoothDeviceMetadata(
                    battery  : prior.battery,
                    model    : prior.model,
                    productID: prior.productID,
                    colorID  : prior.colorID
                ))
            } ?? device
        }

        connectionOrder.removeAll { connectedDevicesByID[$0] == nil }
        for device in devices where !connectionOrder.contains(device.deviceID) {
            connectionOrder.append(device.deviceID)
        }
    }

    /// recordConnection emits only when the address moves from disconnected to
    /// connected. Duplicate callbacks still refresh metadata for a later
    /// disconnect event.
    mutating func recordConnection(
        _ device: BluetoothConnectedDevice,
        eventID : UInt64 = 0,
        now     : TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BluetoothConnectionEvent? {
        if let prior = connectedDevicesByID[device.deviceID] {
            connectedDevicesByID[device.deviceID] = device.enriched(with: BluetoothDeviceMetadata(
                battery  : device.battery?.fillingMissing(from: prior.battery) ?? prior.battery,
                model    : device.model == .generic ? prior.model : device.model,
                productID: device.productID ?? prior.productID,
                colorID  : device.colorID ?? prior.colorID
            ))
            return nil
        }

        connectedDevicesByID[device.deviceID] = device
        connectionOrder.append(device.deviceID)
        let event = BluetoothConnectionEvent(
            deviceID   : device.deviceID,
            name       : device.name,
            symbolName : device.symbolName,
            isConnected: true,
            battery    : device.battery,
            model      : device.model,
            productID  : device.productID,
            colorID    : device.colorID,
            eventID    : eventID
        )
        connectionEventsByID[device.deviceID]      = event
        pendingInitialAudioRoutes[device.deviceID] = now

        return event
    }

    /// recordAudioRoute handles audio routing returning to the Mac while the
    /// underlying Bluetooth link stays connected to both devices. The route
    /// monitor deduplicates output changes; here only the first route following
    /// a fresh ACL event is coalesced, so subsequent returns remain visible.
    mutating func recordAudioRoute(
        _ device: BluetoothConnectedDevice,
        eventID : UInt64,
        now     : TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BluetoothConnectionEvent? {
        let previous                 = connectedDevicesByID[device.deviceID]
        let linkedAt                 = pendingInitialAudioRoutes.removeValue(forKey: device.deviceID)
        let coalescesFreshConnection = linkedAt.map { now >= $0 && now - $0 < 2 } ?? false

        // Identity remains useful across routes, measurements do not. Old
        // earbud values must not override a new aggregate charge, and a known
        // device keeps its own name and symbol: CoreAudio names the route and
        // calls every output headphones.
        let routed = BluetoothConnectedDevice(
            deviceID  : device.deviceID,
            name      : previous?.name ?? device.name,
            symbolName: previous?.symbolName ?? device.symbolName,
            battery   : coalescesFreshConnection
                ? device.battery?.fillingMissing(from: previous?.battery) ?? previous?.battery
                : device.battery,
            model     : device.model == .generic ? previous?.model ?? .generic : device.model,
            productID : device.productID ?? previous?.productID,
            colorID   : device.colorID ?? previous?.colorID
        )
        connectedDevicesByID[device.deviceID] = routed
        if previous == nil {
            connectionOrder.append(device.deviceID)
        }
        if coalescesFreshConnection {
            return nil
        }

        let event = BluetoothConnectionEvent(
            deviceID   : routed.deviceID,
            name       : routed.name,
            symbolName : routed.symbolName,
            isConnected: true,
            battery    : routed.battery,
            model      : routed.model,
            productID  : routed.productID,
            colorID    : routed.colorID,
            eventID    : eventID,
            kind       : .audioRoute
        )
        connectionEventsByID[device.deviceID] = event

        return event
    }

    /// enrichConnection issues a new revision of the same event only while
    /// its original connection remains current. Baselines never own events.
    mutating func enrichConnection(
        deviceID: String,
        eventID : UInt64,
        metadata: BluetoothDeviceMetadata
    ) -> BluetoothConnectionEvent? {
        guard let current = connectionEventsByID[deviceID],
              current.eventID == eventID,
              let device = connectedDevicesByID[deviceID]
        else { return nil }

        let enriched = device.enriched(with: metadata)
        guard enriched.battery != current.battery
              || enriched.model != current.model
              || enriched.productID != current.productID
              || enriched.colorID != current.colorID
        else { return nil }

        connectedDevicesByID[deviceID] = enriched
        let event = BluetoothConnectionEvent(
            deviceID   : enriched.deviceID,
            name       : enriched.name,
            symbolName : enriched.symbolName,
            isConnected: true,
            battery    : enriched.battery,
            model      : enriched.model,
            productID  : enriched.productID,
            colorID    : enriched.colorID,
            eventID    : eventID,
            revision   : current.revision &+ 1,
            kind       : current.kind
        )
        connectionEventsByID[deviceID] = event

        return event
    }

    /// enrichListedDevice applies a read of a device the list carries, made
    /// at a start, a wake or another device's event, to the list alone: an
    /// event already numbered keeps what it carried, and the device's own
    /// next revision starts from the read. It says whether the battery level
    /// changed, the only part of the reading a state's list carries.
    mutating func enrichListedDevice(
        deviceID: String,
        metadata: BluetoothDeviceMetadata
    ) -> Bool {
        guard let device = connectedDevicesByID[deviceID] else { return false }

        let enriched = device.enriched(with: metadata)
        connectedDevicesByID[deviceID] = enriched

        return enriched.battery?.level != device.battery?.level
    }

    /// recordDisconnection emits only for an address currently known to be
    /// connected, then removes it so a later connection is a real transition.
    mutating func recordDisconnection(
        deviceID: String,
        eventID : UInt64 = 0
    ) -> BluetoothConnectionEvent? {
        guard let device = connectedDevicesByID.removeValue(forKey: deviceID) else { return nil }

        connectionOrder.removeAll { $0 == deviceID }
        connectionEventsByID[deviceID]      = nil
        pendingInitialAudioRoutes[deviceID] = nil

        return BluetoothConnectionEvent(
            deviceID   : device.deviceID,
            name       : device.name,
            symbolName : device.symbolName,
            isConnected: false,
            battery    : device.battery,
            model      : device.model,
            productID  : device.productID,
            colorID    : device.colorID,
            eventID    : eventID
        )
    }
}
