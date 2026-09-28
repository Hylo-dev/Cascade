//
//  BluetoothConnectionReducer.swift
//  Cascade
//

import Foundation

/// BluetoothConnectedDevice is the framework-free snapshot retained while a
/// Bluetooth device is connected.
///
/// Keeping this value separate from `IOBluetoothDevice` makes transition
/// handling deterministic and preserves the last useful name and icon when a
/// disconnect callback arrives after the framework has discarded metadata.
nonisolated struct BluetoothConnectedDevice: Equatable, Sendable {

    let deviceID  : String
    let name      : String
    let symbolName: String
    let battery   : BluetoothBatterySnapshot?
    let model     : BluetoothDeviceModel
    let productID : UInt16?
    let colorID   : UInt8?

    init(
        deviceID  : String,
        name      : String,
        symbolName: String,
        battery   : BluetoothBatterySnapshot? = nil,
        model     : BluetoothDeviceModel = .generic,
        productID : UInt16? = nil,
        colorID   : UInt8? = nil
    ) {
        self.deviceID   = deviceID
        self.name       = name
        self.symbolName = symbolName
        self.battery    = battery
        self.model      = model
        self.productID  = productID
        self.colorID    = colorID
    }

    /// enriched keeps known fields when sparse duplicate callbacks omit them.
    func enriched(with metadata: BluetoothDeviceMetadata) -> BluetoothConnectedDevice {
        BluetoothConnectedDevice(
            deviceID  : deviceID,
            name      : name,
            symbolName: symbolName,
            battery   : metadata.battery?.fillingMissing(from: battery) ?? battery,
            model     : metadata.model == .generic ? model : metadata.model,
            productID : metadata.productID ?? productID,
            colorID   : metadata.colorID ?? colorID
        )
    }
}

/// BluetoothConnectionCallbackIdentity identifies both a monitoring session
/// and the silent baseline within that session which accepted a callback.
nonisolated struct BluetoothConnectionCallbackIdentity: Equatable, Sendable {
    let sessionID    : UInt64
    let baselineEpoch: UInt64
}

/// BluetoothConnectionCallbackGate rejects callback work queued before a stop,
/// restart, or wake baseline replacement.
nonisolated struct BluetoothConnectionCallbackGate {

    private(set) var identity = BluetoothConnectionCallbackIdentity(
        sessionID    : 0,
        baselineEpoch: 0
    )

    mutating func beginSession(sessionID: UInt64) {
        identity = BluetoothConnectionCallbackIdentity(
            sessionID    : sessionID,
            baselineEpoch: 0
        )
    }

    mutating func replaceBaseline(epoch: UInt64) {
        identity = BluetoothConnectionCallbackIdentity(
            sessionID    : identity.sessionID,
            baselineEpoch: epoch
        )
    }

    func accepts(_ callbackIdentity: BluetoothConnectionCallbackIdentity) -> Bool {
        callbackIdentity == identity
    }
}

/// BluetoothConnectionReducer turns noisy framework callbacks into real
/// connection transitions.
///
/// IOBluetooth can deliver the same callback more than once. The reducer keeps
/// one compact snapshot per connected address, suppresses duplicates, and lets
/// startup and wake reconciliation replace the baseline without emitting old
/// events.
struct BluetoothConnectionReducer {

    private var connectedDevicesByID : [String: BluetoothConnectedDevice] = [:]
    private var connectionEventsByID : [String: BluetoothConnectionEvent] = [:]
    private var pendingInitialAudioRoutes: [String: TimeInterval] = [:]

    /// replaceBaseline records the devices already connected at startup or
    /// wake. Its lack of a return value is deliberate: baseline devices are
    /// state, not new user-visible connections.
    mutating func replaceBaseline(with devices: [BluetoothConnectedDevice]) {
        connectedDevicesByID.removeAll(keepingCapacity: true)
        connectionEventsByID.removeAll(keepingCapacity: true)
        pendingInitialAudioRoutes.removeAll(keepingCapacity: true)

        for device in devices {
            connectedDevicesByID[device.deviceID] = device
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
        connectionEventsByID[device.deviceID] = event
        pendingInitialAudioRoutes[device.deviceID] = now
        return event
    }

    /// Audio routing can return to the Mac while the underlying Bluetooth
    /// link stays connected to both devices. The route monitor deduplicates
    /// output changes; here only the first route following a fresh ACL event
    /// is coalesced, so subsequent returns remain visible.
    mutating func recordAudioRoute(
        _ device: BluetoothConnectedDevice,
        eventID: UInt64,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BluetoothConnectionEvent? {
        let previous = connectedDevicesByID[device.deviceID]
        let linkedAt = pendingInitialAudioRoutes.removeValue(forKey: device.deviceID)
        let coalescesFreshConnection = linkedAt.map { now >= $0 && now - $0 < 2 } ?? false
        let routed = device.enriched(with: BluetoothDeviceMetadata(
            // Identity remains useful across routes, measurements do not.
            // Old earbud values must not override a new aggregate charge.
            battery: coalescesFreshConnection
                ? device.battery?.fillingMissing(from: previous?.battery) ?? previous?.battery
                : device.battery,
            model: device.model == .generic ? previous?.model ?? .generic : device.model,
            productID: device.productID ?? previous?.productID,
            colorID: device.colorID ?? previous?.colorID
        ))
        connectedDevicesByID[device.deviceID] = routed
        if coalescesFreshConnection {
            return nil
        }
        let event = BluetoothConnectionEvent(
            deviceID: routed.deviceID,
            name: routed.name,
            symbolName: routed.symbolName,
            isConnected: true,
            battery: routed.battery,
            model: routed.model,
            productID: routed.productID,
            colorID: routed.colorID,
            eventID: eventID,
            kind: .audioRoute
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
        guard let current = connectionEventsByID[deviceID], current.eventID == eventID,
              let device = connectedDevicesByID[deviceID] else { return nil }
        let enriched = device.enriched(with: metadata)
        guard enriched.battery != current.battery || enriched.model != current.model
                || enriched.productID != current.productID || enriched.colorID != current.colorID else { return nil }
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

    /// recordDisconnection emits only for an address currently known to be
    /// connected, then removes it so a later connection is a real transition.
    mutating func recordDisconnection(
        deviceID: String,
        eventID : UInt64 = 0
    ) -> BluetoothConnectionEvent? {

        guard let device = connectedDevicesByID.removeValue(forKey: deviceID) else {
            return nil
        }

        connectionEventsByID[deviceID] = nil
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
