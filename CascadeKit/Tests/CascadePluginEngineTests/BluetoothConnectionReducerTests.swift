//
//  BluetoothConnectionReducerTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing

@testable import CascadePluginHost

/// BluetoothConnectionReducerTests are Cascade's Bluetooth monitor checks, carried over with the
/// reducer into PluginHost: baselines stay silent, duplicates are suppressed, audio coming back
/// is its own event, and late metadata only revises the event it belongs to.
@Suite
struct BluetoothConnectionReducerTests {

    private func device(
        _ deviceID: String,
        name      : String = "Headphones",
        battery   : BluetoothBatterySnapshot? = nil,
        model     : PluginBluetoothDeviceModel = .generic,
        productID : UInt16? = nil
    ) -> BluetoothConnectedDevice {
        BluetoothConnectedDevice(
            deviceID  : deviceID,
            name      : name,
            symbolName: "headphones",
            battery   : battery,
            model     : model,
            productID : productID
        )
    }

    @Test
    func aDeviceConnectedBeforeMonitoringIsASilentBaseline() {
        var reducer = BluetoothConnectionReducer()
        let studio  = device("AA-BB-CC-DD-EE-FF")
        reducer.replaceBaseline(with: [studio])

        let event = reducer.recordConnection(studio)

        #expect(event == nil)
    }

    @Test
    func aDuplicateConnectionIsSuppressed() {
        var reducer   = BluetoothConnectionReducer()
        let keyboard  = device("11-22-33-44-55-66", name: "Keyboard")
        let first     = reducer.recordConnection(keyboard)
        let duplicate = reducer.recordConnection(keyboard)

        #expect(first?.isConnected == true)
        #expect(duplicate == nil)
    }

    @Test
    func aDisconnectionAndAReconnectBothEmit() {
        var reducer = BluetoothConnectionReducer()
        let mouse   = BluetoothConnectedDevice(deviceID: "22-33-44-55-66-77", name: "Mouse", symbolName: "computermouse")
        _ = reducer.recordConnection(mouse)

        let disconnection = reducer.recordDisconnection(deviceID: mouse.deviceID)
        let reconnect     = reducer.recordConnection(mouse)

        #expect(disconnection == BluetoothConnectionEvent(deviceID: mouse.deviceID, name: "Mouse", symbolName: "computermouse", isConnected: false))
        #expect(reconnect?.isConnected == true)
    }

    @Test
    func aWakeBaselineForgetsAndAdoptsDevicesSilently() {
        var reducer    = BluetoothConnectionReducer()
        let oldDevice  = device("33-44-55-66-77-88", name: "Old Device")
        let wakeDevice = device("44-55-66-77-88-99", name: "Wake Device")
        reducer.replaceBaseline(with: [oldDevice])
        reducer.replaceBaseline(with: [wakeDevice])

        let forgotten = reducer.recordDisconnection(deviceID: oldDevice.deviceID)
        let adopted   = reducer.recordConnection(wakeDevice)

        #expect(forgotten == nil)
        #expect(adopted == nil)
    }

    @Test
    func repeatedBaselineEntriesCollapseToTheLatest() {
        var reducer = BluetoothConnectionReducer()
        reducer.replaceBaseline(with: [device("55-66-77-88-99-AA", name: "Old Name"), device("55-66-77-88-99-AA", name: "New Name")])

        let disconnection = reducer.recordDisconnection(deviceID: "55-66-77-88-99-AA")

        #expect(disconnection?.name == "New Name")
    }

    @Test
    func aCallbackQueuedBeforeAWakeIsRejected() {
        var gate = BluetoothConnectionCallbackGate()
        gate.beginSession(sessionID: 7)
        let queued = gate.identity
        gate.replaceBaseline(epoch: 1)

        #expect(!gate.accepts(queued))
        #expect(gate.accepts(BluetoothConnectionCallbackIdentity(sessionID: 7, baselineEpoch: 1)))
    }

    @Test
    func audioComingBackEmitsWhileTheLinkStaysConnected() {
        var reducer  = BluetoothConnectionReducer()
        let airPods  = device("66-77-88-99-AA-BB", name: "AirPods")
        let metadata = BluetoothDeviceMetadata(model: .airPodsPro, productID: 0x2024)
        reducer.replaceBaseline(with: [airPods])

        let first        = reducer.recordAudioRoute(airPods, eventID: 1, now: 100)
        let second       = reducer.recordAudioRoute(airPods, eventID: 2, now: 110)
        let staleUpdate  = reducer.enrichConnection(deviceID: airPods.deviceID, eventID: 1, metadata: metadata)
        let routeUpdate  = reducer.enrichConnection(deviceID: airPods.deviceID, eventID: 2, metadata: metadata)

        #expect(first?.kind == .audioRoute && first?.isConnected == true)
        #expect(second?.eventID == 2)
        #expect(staleUpdate == nil, "Metadata from the prior route must not update a newer route event")
        #expect(routeUpdate?.kind == .audioRoute)
    }

    @Test
    func theFirstRouteAfterAFreshConnectionIsCoalescedOnly() {
        var reducer = BluetoothConnectionReducer()
        let phones  = device("77-88-99-AA-BB-CC")
        _ = reducer.recordConnection(phones, eventID: 1, now: 100)

        let coalesced = reducer.recordAudioRoute(phones, eventID: 2, now: 100.2)
        let later     = reducer.recordAudioRoute(phones, eventID: 3, now: 101)

        #expect(coalesced == nil)
        #expect(later?.kind == .audioRoute)
    }

    @Test
    func aLinkAfterItsAudioRouteIsNotADuplicate() {
        var reducer = BluetoothConnectionReducer()
        let phones  = device("88-99-AA-BB-CC-DD")
        _ = reducer.recordAudioRoute(phones, eventID: 1, now: 100)

        let link = reducer.recordConnection(phones, eventID: 2, now: 100.2)

        #expect(link == nil)
    }

    @Test
    func audioComingBackDiscardsOldMeasurementsButKeepsIdentity() {
        var reducer   = BluetoothConnectionReducer()
        let oldDevice = device("99-AA-BB-CC-DD-EE", name: "AirPods", battery: BluetoothBatterySnapshot(left: 83, right: 91), model: .airPodsPro, productID: 0x2024)
        reducer.replaceBaseline(with: [oldDevice])

        let returned  = reducer.recordAudioRoute(device(oldDevice.deviceID, name: "AirPods"), eventID: 5, now: 500)
        let refreshed = reducer.enrichConnection(deviceID: oldDevice.deviceID, eventID: 5, metadata: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 35)))

        #expect(returned?.battery == nil && returned?.productID == 0x2024)
        #expect(refreshed?.battery?.level == 35 && refreshed?.battery?.left == nil)
    }

    @Test
    func productAndColourWithoutABatteryStillReviseTheEvent() {
        var reducer  = BluetoothConnectionReducer()
        let renamed  = device("AA-BB-CC-DD-EE-FF", name: "Renamed")
        let metadata = BluetoothDeviceMetadata(productID: 0x201F, colorID: 19)
        _ = reducer.recordConnection(renamed, eventID: 29)

        let update    = reducer.enrichConnection(deviceID: renamed.deviceID, eventID: 29, metadata: metadata)
        let redundant = reducer.enrichConnection(deviceID: renamed.deviceID, eventID: 29, metadata: metadata)
        _ = reducer.recordConnection(renamed)
        let disconnected = reducer.recordDisconnection(deviceID: renamed.deviceID)
        let reconnected  = reducer.recordConnection(renamed, eventID: 30)

        #expect(update?.productID == 0x201F && update?.colorID == 19 && update?.revision == 1)
        #expect(redundant == nil)
        #expect(disconnected?.productID == 0x201F && disconnected?.colorID == 19)
        #expect(reconnected?.productID == nil && reconnected?.colorID == nil, "A new connection must not reuse an expired sample")
    }

    @Test
    func lateMeasurementsReviseTheOriginalEventOnly() {
        var reducer  = BluetoothConnectionReducer()
        let phones   = device("AA-BB-CC-DD-EE-FF")
        let metadata = BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(left: 58, right: 32), model: .airPodsPro)
        let initial  = reducer.recordConnection(phones, eventID: 12)

        let update    = reducer.enrichConnection(deviceID: phones.deviceID, eventID: 12, metadata: metadata)
        let redundant = reducer.enrichConnection(deviceID: phones.deviceID, eventID: 12, metadata: metadata)
        _ = reducer.recordConnection(phones)
        var sparseCopy   = reducer
        let sparseLeaves = sparseCopy.recordDisconnection(deviceID: phones.deviceID)

        #expect(update?.eventID == initial?.eventID && update?.revision == 1 && update?.battery?.level == 32)
        #expect(redundant == nil)
        #expect(sparseLeaves?.battery?.level == 32, "A sparse duplicate keeps the last measured battery")

        _ = reducer.recordConnection(device(phones.deviceID, battery: BluetoothBatterySnapshot(left: 58, right: 18), model: .airPodsPro))
        let disconnected = reducer.recordDisconnection(deviceID: phones.deviceID)
        _ = reducer.recordConnection(phones, eventID: 13)
        let priorSample = reducer.enrichConnection(deviceID: phones.deviceID, eventID: 12, metadata: metadata)
        reducer.replaceBaseline(with: [phones])
        let afterWake = reducer.enrichConnection(deviceID: phones.deviceID, eventID: 13, metadata: metadata)

        #expect(disconnected?.battery?.level == 18 && disconnected?.model == .airPodsPro)
        #expect(priorSample == nil, "A late sample from a prior connection must not mutate a reconnect")
        #expect(afterWake == nil, "A wake baseline must never replay an update")
    }
}
