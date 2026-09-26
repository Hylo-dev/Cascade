//
//  BluetoothConnectionReducerTests.swift
//  Cascade
//

#if BLUETOOTH_MONITOR_TESTS
enum BluetoothConnectionReducerTests {

    static func run() throws {
        try baselineDoesNotEmitAnEvent()
        try duplicateConnectionIsSuppressed()
        try disconnectionAndReconnectBothEmit()
        try replacingBaselineAfterWakeIsSilent()
        try repeatedBaselineIdentityIsDeduplicated()
        try queuedCallbackBeforeWakeIsRejected()
        try audioReturnEmitsWhileBluetoothLinkRemainsConnected()
        try physicalConnectionAndAudioRouteCoalesce()
        try routeBeforeLinkDoesNotDuplicate()
        try audioReturnDoesNotReuseOldBatteryMeasurements()
    }

    private static func audioReturnEmitsWhileBluetoothLinkRemainsConnected() throws {
        var reducer = BluetoothConnectionReducer()
        let device = BluetoothConnectedDevice(
            deviceID: "66-77-88-99-AA-BB", name: "AirPods", symbolName: "headphones"
        )
        reducer.replaceBaseline(with: [device])
        let first = reducer.recordAudioRoute(device, eventID: 1, now: 100)
        try expectBluetoothMonitorBehavior(
            first?.kind == .audioRoute && first?.isConnected == true,
            "Returning audio to a baselined Bluetooth link must emit a route notice."
        )
        let second = reducer.recordAudioRoute(device, eventID: 2, now: 110)
        let metadata = BluetoothDeviceMetadata(battery: nil, model: .airPodsPro, productID: 0x2024)
        try expectBluetoothMonitorBehavior(
            second?.eventID == 2,
            "A later audio return must emit again without requiring an ACL disconnect."
        )
        try expectBluetoothMonitorBehavior(
            reducer.enrichConnection(deviceID: device.deviceID, eventID: 1, metadata: metadata) == nil,
            "Metadata from the prior route must not update a newer route event."
        )
        try expectBluetoothMonitorBehavior(
            reducer.enrichConnection(deviceID: device.deviceID, eventID: 2, metadata: metadata)?.kind == .audioRoute,
            "Metadata enrichment must preserve the audio route meaning."
        )
    }

    private static func physicalConnectionAndAudioRouteCoalesce() throws {
        var reducer = BluetoothConnectionReducer()
        let device = BluetoothConnectedDevice(
            deviceID: "77-88-99-AA-BB-CC", name: "Headphones", symbolName: "headphones"
        )
        _ = reducer.recordConnection(device, eventID: 1, now: 100)
        try expectBluetoothMonitorBehavior(
            reducer.recordAudioRoute(device, eventID: 2, now: 100.2) == nil,
            "The initial audio route must not replay the fresh physical connection notice."
        )
        try expectBluetoothMonitorBehavior(
            reducer.recordAudioRoute(device, eventID: 3, now: 101)?.kind == .audioRoute,
            "Only the first route after a physical connection may be coalesced."
        )
    }

    private static func routeBeforeLinkDoesNotDuplicate() throws {
        var reducer = BluetoothConnectionReducer()
        let device = BluetoothConnectedDevice(
            deviceID: "88-99-AA-BB-CC-DD", name: "Headphones", symbolName: "headphones"
        )
        _ = reducer.recordAudioRoute(device, eventID: 1, now: 100)
        try expectBluetoothMonitorBehavior(
            reducer.recordConnection(device, eventID: 2, now: 100.2) == nil,
            "An ACL callback after the audio route must not duplicate the notice."
        )
    }

    private static func audioReturnDoesNotReuseOldBatteryMeasurements() throws {
        var reducer = BluetoothConnectionReducer()
        let oldDevice = BluetoothConnectedDevice(
            deviceID: "99-AA-BB-CC-DD-EE", name: "AirPods", symbolName: "headphones",
            battery: BluetoothBatterySnapshot(left: 83, right: 91), model: .airPodsPro,
            productID: 0x2024
        )
        reducer.replaceBaseline(with: [oldDevice])
        let returned = BluetoothConnectedDevice(
            deviceID: oldDevice.deviceID, name: oldDevice.name, symbolName: oldDevice.symbolName
        )
        let event = reducer.recordAudioRoute(returned, eventID: 5, now: 500)
        try expectBluetoothMonitorBehavior(
            event?.battery == nil && event?.productID == oldDevice.productID,
            "A new route must preserve model identity but discard old battery measurements."
        )
        let refreshed = reducer.enrichConnection(
            deviceID: returned.deviceID, eventID: 5,
            metadata: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 35))
        )
        try expectBluetoothMonitorBehavior(
            refreshed?.battery?.level == 35 && refreshed?.battery?.left == nil,
            "Fresh aggregate charge must not be overridden by earbud values from a prior route."
        )
    }

    private static func baselineDoesNotEmitAnEvent() throws {

        var reducer = BluetoothConnectionReducer()
        let device  = BluetoothConnectedDevice(
            deviceID   : "AA-BB-CC-DD-EE-FF",
            name       : "Studio Headphones",
            symbolName : "headphones"
        )

        reducer.replaceBaseline(with: [device])

        try expectBluetoothMonitorBehavior(
            reducer.recordConnection(device) == nil,
            "A device connected before monitoring starts must remain a silent baseline."
        )
    }

    private static func duplicateConnectionIsSuppressed() throws {

        var reducer = BluetoothConnectionReducer()
        let device  = BluetoothConnectedDevice(
            deviceID   : "11-22-33-44-55-66",
            name       : "Keyboard",
            symbolName : "keyboard"
        )

        let first     = reducer.recordConnection(device)
        let duplicate = reducer.recordConnection(device)

        try expectBluetoothMonitorBehavior(
            first?.isConnected == true,
            "The first connection must emit."
        )
        try expectBluetoothMonitorBehavior(
            duplicate == nil,
            "A duplicate connection callback must not emit."
        )
    }

    private static func disconnectionAndReconnectBothEmit() throws {

        var reducer = BluetoothConnectionReducer()
        let device  = BluetoothConnectedDevice(
            deviceID   : "22-33-44-55-66-77",
            name       : "Mouse",
            symbolName : "computermouse"
        )

        _ = reducer.recordConnection(device)
        let disconnection = reducer.recordDisconnection(deviceID: device.deviceID)
        let reconnect     = reducer.recordConnection(device)

        try expectBluetoothMonitorBehavior(
            disconnection == BluetoothConnectionEvent(
                deviceID   : device.deviceID,
                name       : device.name,
                symbolName : device.symbolName,
                isConnected: false
            ),
            "A known disconnection must emit the metadata retained at connection time."
        )
        try expectBluetoothMonitorBehavior(
            reconnect?.isConnected == true,
            "A real reconnect must emit again."
        )
    }

    private static func replacingBaselineAfterWakeIsSilent() throws {

        var reducer = BluetoothConnectionReducer()
        let oldDevice = BluetoothConnectedDevice(
            deviceID   : "33-44-55-66-77-88",
            name       : "Old Device",
            symbolName : "antenna.radiowaves.left.and.right"
        )
        let wakeDevice = BluetoothConnectedDevice(
            deviceID   : "44-55-66-77-88-99",
            name       : "Wake Device",
            symbolName : "headphones"
        )

        reducer.replaceBaseline(with: [oldDevice])
        reducer.replaceBaseline(with: [wakeDevice])

        try expectBluetoothMonitorBehavior(
            reducer.recordDisconnection(deviceID: oldDevice.deviceID) == nil,
            "Wake reconciliation must forget devices no longer connected without replaying events."
        )
        try expectBluetoothMonitorBehavior(
            reducer.recordConnection(wakeDevice) == nil,
            "Wake reconciliation must silently baseline devices already connected on wake."
        )
    }

    private static func repeatedBaselineIdentityIsDeduplicated() throws {

        var reducer = BluetoothConnectionReducer()
        let first = BluetoothConnectedDevice(
            deviceID   : "55-66-77-88-99-AA",
            name       : "Old Name",
            symbolName : "headphones"
        )
        let refreshed = BluetoothConnectedDevice(
            deviceID   : first.deviceID,
            name       : "New Name",
            symbolName : "speaker.wave.2"
        )

        reducer.replaceBaseline(with: [first, refreshed])

        try expectBluetoothMonitorBehavior(
            reducer.recordDisconnection(deviceID: first.deviceID)?.name == "New Name",
            "Repeated cached device entries must collapse to the latest metadata."
        )
    }

    private static func queuedCallbackBeforeWakeIsRejected() throws {

        var gate = BluetoothConnectionCallbackGate()
        gate.beginSession(sessionID: 7)
        let queuedCallback = gate.identity

        gate.replaceBaseline(epoch: 1)

        try expectBluetoothMonitorBehavior(
            !gate.accepts(queuedCallback),
            "A callback queued before wake must not mutate the replacement baseline."
        )
        try expectBluetoothMonitorBehavior(
            gate.accepts(
                BluetoothConnectionCallbackIdentity(
                    sessionID    : 7,
                    baselineEpoch: 1
                )
            ),
            "A callback from the current wake baseline must remain valid."
        )
    }
}
#endif
