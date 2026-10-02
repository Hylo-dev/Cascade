//
//  BluetoothSourceTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import CascadePlugins
import CoreAudio
import Foundation
import Synchronization
import Testing

@testable import CascadePluginHost

/// BluetoothSourceTests drive the `bluetooth` source with a fake system: a connection observer
/// the test plays, a fixed metadata reader and controlled audio routes. Nothing here reaches
/// IOBluetooth, so the tests never ask macOS for Bluetooth access.
@Suite
struct BluetoothSourceTests {

    private let airPods = BluetoothConnectedDevice(deviceID: "AA-BB-CC-DD-EE-FF", name: "AirPods", symbolName: "airpods")
    private let keyboard = BluetoothConnectedDevice(deviceID: "11-22-33-44-55-66", name: "Keyboard", symbolName: "keyboard")
    private let output   = BluetoothAudioRouteSnapshot(uid: "AA-BB-CC-DD-EE-FF:output", name: "AirPods", transportType: kAudioDeviceTransportTypeBluetooth)
    private let speakers = BluetoothAudioRouteSnapshot(uid: "BuiltInSpeakerDevice", name: "Mac speakers", transportType: kAudioDeviceTransportTypeBuiltIn)

    /// listed is a device as a state lists it.
    private func listed(
        _ device: BluetoothConnectedDevice,
        battery : Int? = nil
    ) -> PluginBluetoothDevice {
        PluginBluetoothDevice(name: device.name, symbolName: device.symbolName, batteryLevel: battery)
    }

    private func source(
        _ system : FakeBluetoothSystem,
        metadata : BluetoothDeviceMetadata = BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 64), model: .airPods),
        reader   : FakeMetadataReader? = nil,
        routes   : RouteSources = RouteSources(snapshot: nil)
    ) -> (BluetoothSource, Recorder<PluginBluetoothState>) {
        let source = BluetoothSource(
            makeObserver      : system.makeObserver,
            metadataReader    : reader ?? FakeMetadataReader(metadata: metadata),
            routeSourceFactory: routes.make,
            registrationQueue : DispatchQueue(label: "cascade.tests.bluetooth-registration"),
            metadataRetryDelay: .milliseconds(1)
        )
        let states = Recorder<PluginBluetoothState>()
        source.start { event in
            if let state = PluginBluetoothState(event) {
                states.record(state)
            }
        }

        return (source, states)
    }

    @Test
    func startingEmitsABaselineThenTheBatteriesItReadsAndDevicesAlreadyConnectedStaySilent() async throws {
        let system           = FakeBluetoothSystem(connected: [airPods])
        let (source, states) = source(system)
        #expect(try await eventually { states.values.count == 2 })

        system.latest?.connect(airPods)
        try await Task.sleep(for: .milliseconds(30))
        source.stop()

        #expect(states.values == [
            .baseline(isAvailable: true, connectedDevices: [listed(airPods)]),
            .baseline(isAvailable: true, connectedDevices: [listed(airPods, battery: 64)]),
        ])
    }

    @Test
    func aWakeRereadsTheBatteriesAndEmitsOnlyWhenOneChanged() async throws {
        let system           = FakeBluetoothSystem(connected: [airPods])
        let reader           = FakeMetadataReader(metadata: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 64)))
        let (source, states) = source(system, reader: reader)
        #expect(try await eventually { states.values.count == 2 })

        source.simulate(.didWake)
        #expect(try await eventually { reader.reads == 2 })
        try await Task.sleep(for: .milliseconds(30))
        #expect(states.values.count == 2)

        reader.answer(with: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 50)))
        source.simulate(.didWake)
        #expect(try await eventually { states.values.count == 3 })
        try await Task.sleep(for: .milliseconds(30))
        source.stop()

        #expect(states.values.map(\.connectedDevices) == [
            [listed(airPods)],
            [listed(airPods, battery: 64)],
            [listed(airPods, battery: 50)],
        ])
        #expect(states.values.allSatisfy { $0.eventID == 0 })
    }

    @Test
    func aConnectionBeforeABaselineBatteryIsReadCarriesItAndShowsOneNotice() async throws {
        let system           = FakeBluetoothSystem(connected: [airPods])
        let reader           = FakeMetadataReader(metadata: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 64)), holding: airPods.deviceID)
        let (source, states) = source(system, reader: reader)
        #expect(try await eventually { states.values.count == 1 })

        system.latest?.connect(keyboard)
        #expect(try await eventually { states.values.count == 2 })
        reader.letThrough()
        #expect(try await eventually { states.values.count == 4 })
        try await Task.sleep(for: .milliseconds(30))
        source.stop()

        let plugin     = BluetoothPlugin()
        let context    = PluginContext(plugin: BluetoothPlugin.id)
        let deliveries = try states.values.map { state in
            try plugin.handle(.source(state.event()), context: context).publications.first?.notice?.delivery
        }

        #expect(states.values.map(\.eventID) == [0, 1, 1, 1])
        #expect(states.values.map(\.revision) == [0, 0, 0, 1])
        #expect(states.values[2].connectedDevices == [listed(airPods, battery: 64), listed(keyboard)], "The connection's state again, with the battery read")
        #expect(states.values.last?.connectedDevices == [listed(airPods, battery: 64), listed(keyboard, battery: 64)])
        #expect(deliveries == [nil, .show, nil, .update])
    }

    @Test
    func aConnectionRereadsTheDevicesAlreadyListedAndTheirBatteriesShowNoNotice() async throws {
        let system           = FakeBluetoothSystem(connected: [airPods])
        let reader           = FakeMetadataReader(metadata: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 64)))
        let (source, states) = source(system, reader: reader)
        #expect(try await eventually { states.values.count == 2 })

        reader.answer(with: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 50)))
        system.latest?.connect(BluetoothConnectedDevice(deviceID: keyboard.deviceID, name: "Keyboard", symbolName: "keyboard", battery: BluetoothBatterySnapshot(level: 50)))
        #expect(try await eventually { states.values.count == 4 })
        try await Task.sleep(for: .milliseconds(30))
        source.stop()

        let plugin     = BluetoothPlugin()
        let context    = PluginContext(plugin: BluetoothPlugin.id)
        let deliveries = try states.values.map { state in
            try plugin.handle(.source(state.event()), context: context).publications.first?.notice?.delivery
        }

        #expect(states.values.count == 4)
        #expect(states.values.dropFirst(2).map(\.connectedDevices) == [
            [listed(airPods, battery: 64), listed(keyboard, battery: 50)],
            [listed(airPods, battery: 50), listed(keyboard, battery: 50)],
        ])
        #expect(states.values.map(\.eventID) == [0, 0, 1, 1])
        #expect(states.values.map(\.revision) == [0, 0, 0, 0], "The read rides the connection's own state again")
        #expect(deliveries == [nil, nil, .show, nil])
    }

    @Test
    func everyStateListsTheDevicesConnectedThenInTheOrderTheyConnected() async throws {
        let system           = FakeBluetoothSystem()
        let (source, states) = source(system, metadata: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 64)))
        #expect(try await eventually { states.values.count == 1 })

        system.latest?.connect(airPods)
        #expect(try await eventually { states.values.count == 3 })
        system.latest?.connect(keyboard)
        #expect(try await eventually { states.values.count == 5 })
        system.latest?.connect(BluetoothConnectedDevice(deviceID: keyboard.deviceID, name: "Keyboard", symbolName: "keyboard", battery: BluetoothBatterySnapshot(level: 30)))
        system.latest?.disconnect(airPods.deviceID)
        #expect(try await eventually { states.values.count == 7 })
        try await Task.sleep(for: .milliseconds(30))
        source.stop()

        #expect(states.values.map(\.connectedDevices) == [
            [],
            [listed(airPods)],
            [listed(airPods, battery: 64)],
            [listed(airPods, battery: 64), listed(keyboard)],
            [listed(airPods, battery: 64), listed(keyboard, battery: 64)],
            [listed(keyboard, battery: 30)],
            [listed(keyboard, battery: 64)],
        ])
        #expect(states.values.map(\.eventID) == [0, 1, 1, 2, 2, 3, 3], "A disconnection re-reads the devices still listed")
    }

    @Test
    func aWakeListsTheDevicesStillConnectedOnlyWhenTheListChanged() async throws {
        let system           = FakeBluetoothSystem(connected: [airPods, keyboard])
        let (source, states) = source(system, metadata: BluetoothDeviceMetadata())
        #expect(try await eventually { states.values.count == 1 })

        system.replaceConnected(with: [keyboard, airPods])
        source.simulate(.didWake)
        system.replaceConnected(with: [keyboard])
        source.simulate(.didWake)
        source.stop()

        #expect(states.values == [
            .baseline(isAvailable: true, connectedDevices: [listed(airPods), listed(keyboard)]),
            .baseline(isAvailable: true, connectedDevices: [listed(keyboard)]),
        ])
    }

    @Test
    func aFailedRegistrationSaysMonitoringIsUnavailable() async throws {
        let system           = FakeBluetoothSystem(registers: false)
        let (source, states) = source(system)

        #expect(try await eventually { states.values.count == 1 })
        #expect(states.values == [.baseline(isAvailable: false)])
        source.stop()
    }

    @Test
    func aConnectionIsNumberedRevisedByItsMetadataAndFollowedByItsDisconnection() async throws {
        let system           = FakeBluetoothSystem()
        let (source, states) = source(system)
        #expect(try await eventually { states.values.count == 1 })

        system.latest?.connect(airPods)
        #expect(try await eventually { states.values.count == 3 })
        system.latest?.disconnect(airPods.deviceID)
        #expect(try await eventually { states.values.count == 4 })
        source.stop()

        let events = states.values.dropFirst()
        #expect(events.map(\.eventID) == [1, 1, 2])
        #expect(events.map(\.revision) == [0, 1, 0])
        #expect(events.map(\.isConnected) == [true, true, false])
        #expect(events.dropFirst().first?.battery?.level == 64)
        #expect(events.dropFirst().first?.model == .airPods)
        #expect(events.allSatisfy { $0.isAvailable && $0.deviceID == airPods.deviceID && $0.kind == .connection })
    }

    @Test
    func aStoppedSourceIsSilentAndARestartKeepsCounting() async throws {
        let system           = FakeBluetoothSystem()
        let (source, states) = source(system, metadata: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 50)))
        #expect(try await eventually { states.values.count == 1 })
        system.latest?.connect(keyboard)
        #expect(try await eventually { states.values.count == 3 })

        let stopped = system.latest
        source.stop()
        stopped?.connect(airPods)
        try await Task.sleep(for: .milliseconds(30))
        #expect(states.values.count == 3)
        #expect(try await eventually { stopped?.isStopped == true })

        source.start { event in
            if let state = PluginBluetoothState(event) {
                states.record(state)
            }
        }
        #expect(try await eventually { states.values.count == 4 })
        system.latest?.connect(airPods)
        #expect(try await eventually { states.values.last?.eventID == 2 })
        source.stop()

        #expect(states.values[3] == .baseline(isAvailable: true))
    }

    @Test
    func audioComingBackIsAnEventSleepSilencesItAndAWakeRebaselines() async throws {
        let system           = FakeBluetoothSystem()
        let routes           = RouteSources(snapshot: output)
        let (source, states) = source(system, metadata: BluetoothDeviceMetadata(), routes: routes)
        #expect(try await eventually { states.values.count == 1 })

        #expect(try await eventually { routes.count == 1 })
        let first = try #require(routes.latest)
        await first.waitForRegistration()
        await first.change(to: speakers)
        await first.change(to: output)
        #expect(try await eventually { states.values.count == 2 })

        source.simulate(.willSleep)
        await first.change(to: speakers, includingRemovedCallback: true)
        await first.change(to: output, includingRemovedCallback: true)

        system.connect(keyboard)
        source.simulate(.didWake)
        #expect(try await eventually { routes.count == 2 })
        system.latest?.connect(keyboard)
        let second = try #require(routes.latest)
        await second.waitForRegistration()
        await second.change(to: speakers)
        await second.change(to: output)
        #expect(try await eventually { states.values.count == 4 })
        try await Task.sleep(for: .milliseconds(30))
        source.stop()

        let events = states.values.filter { $0.eventID != 0 }
        #expect(events.map(\.kind) == [.audioRoute, .audioRoute])
        #expect(events.map(\.eventID) == [1, 2])
        #expect(events.allSatisfy { $0.deviceID == "AA-BB-CC-DD-EE-FF" && $0.isConnected })
        #expect(states.values[2] == .baseline(isAvailable: true, connectedDevices: [listed(keyboard)]))
    }

    @Test
    func theBaselineComesBeforeAConnectionThatRacedIt() async throws {
        let system           = FakeBluetoothSystem(racing: [airPods])
        let (source, states) = source(system)

        #expect(try await eventually { states.values.count >= 2 })
        #expect(states.values.first?.eventID == 0)
        #expect(states.values.dropFirst().first?.isNewConnection == true)
        source.stop()
    }

    @Test
    func stoppingDoesNotWaitForASlowBaseline() async throws {
        let system      = FakeBluetoothSystem(baselineDelay: 0.6)
        let (source, _) = source(system)
        #expect(try await eventually { system.isReadingBaseline })

        let started = ContinuousClock.now
        source.stop()

        #expect(ContinuousClock.now - started < .milliseconds(200))
    }

    @Test
    func powerMessagesAreAllowedAtOnceAndReportedAsTransitions() {
        #expect(SystemPowerNotifications.response(to: 0xE000_0270) == SystemPowerNotifications.Response(allowsChange: true, transition: nil))
        #expect(SystemPowerNotifications.response(to: 0xE000_0280) == SystemPowerNotifications.Response(allowsChange: true, transition: .willSleep))
        #expect(SystemPowerNotifications.response(to: 0xE000_0300) == SystemPowerNotifications.Response(allowsChange: false, transition: .didWake))
        #expect(SystemPowerNotifications.response(to: 0xE000_0320) == SystemPowerNotifications.Response(allowsChange: false, transition: nil))
    }

    @Test
    func pluginHostOffersBluetooth() {
        #expect(PluginHostCatalog.names.contains(PluginBluetoothState.source))
    }
}

/// FakeBluetoothSystem stands in for IOBluetooth: it builds the source's connection observers,
/// says whether registering works and which devices are connected when a baseline is read.
final class FakeBluetoothSystem: Sendable {

    private let registers    : Bool
    private let state        : Mutex<(observers: [FakeConnectionObserver], connected: [BluetoothConnectedDevice])>
    private let reading      = Mutex(false)
    let racing               : [BluetoothConnectedDevice]
    let baselineDelay        : TimeInterval

    /// init makes a system; `racing` devices connect while a baseline is read, so the observer
    /// holds their callbacks and replays them after it, and `baselineDelay` makes reading the
    /// baseline as slow as a stuck bluetoothd.
    init(
        registers    : Bool = true,
        connected    : [BluetoothConnectedDevice] = [],
        racing       : [BluetoothConnectedDevice] = [],
        baselineDelay: TimeInterval = 0
    ) {
        self.registers     = registers
        self.state         = Mutex((observers: [], connected: connected))
        self.racing        = racing
        self.baselineDelay = baselineDelay
    }

    /// isReadingBaseline is true once a baseline read has begun.
    var isReadingBaseline: Bool {
        get { reading.withLock { $0 } }
        set { reading.withLock { $0 = newValue } }
    }

    var latest: FakeConnectionObserver? {
        state.withLock { $0.observers.last }
    }

    var connectedDevices: [BluetoothConnectedDevice] {
        state.withLock { $0.connected }
    }

    /// connect marks a device as connected for the next baseline, as if it connected in sleep.
    func connect(_ device: BluetoothConnectedDevice) {
        state.withLock { $0.connected.append(device) }
    }

    /// replaceConnected sets the devices the next baseline reads, in the order it reads them.
    func replaceConnected(with devices: [BluetoothConnectedDevice]) {
        state.withLock { $0.connected = devices }
    }

    var makeObserver: BluetoothSource.ObserverFactory {
        { [self] sessionID, handler in
            let observer = FakeConnectionObserver(system: self, sessionID: sessionID, registers: registers, handler: handler)
            state.withLock { $0.observers.append(observer) }
            return observer
        }
    }
}

/// FakeConnectionObserver is one session's connection observer: the test calls `connect` and
/// `disconnect` as IOBluetooth would call the observer's selectors.
final class FakeConnectionObserver: BluetoothConnectionObserving {

    private let system   : FakeBluetoothSystem
    private let sessionID: UInt64
    private let registers: Bool
    private let handler  : @Sendable (IOBluetoothConnectionCallback) -> Void
    private let state     = Mutex((epoch: UInt64.zero, isStopped: false))

    init(
        system   : FakeBluetoothSystem,
        sessionID: UInt64,
        registers: Bool,
        handler  : @escaping @Sendable (IOBluetoothConnectionCallback) -> Void
    ) {
        self.system    = system
        self.sessionID = sessionID
        self.registers = registers
        self.handler   = handler
    }

    var isStopped: Bool {
        state.withLock { $0.isStopped }
    }

    func start() -> Bool {
        registers
    }

    func stop() {
        state.withLock { $0.isStopped = true }
    }

    func beginBaselineReplacement() -> UInt64 {
        state.withLock { state in
            state.epoch &+= 1
            return state.epoch
        }
    }

    func connectedDevices() -> [BluetoothConnectedDevice] {
        system.isReadingBaseline = true
        if system.baselineDelay > 0 {
            Thread.sleep(forTimeInterval: system.baselineDelay)
        }

        return system.connectedDevices
    }

    func finishBaselineReplacement() -> [IOBluetoothConnectionCallback] {
        system.racing.map { .connected(identity: identity, device: $0) }
    }

    func connect(_ device: BluetoothConnectedDevice) {
        handler(.connected(identity: identity, device: device))
    }

    func disconnect(_ deviceID: String) {
        handler(.disconnected(identity: identity, deviceID: deviceID))
    }

    private var identity: BluetoothConnectionCallbackIdentity {
        BluetoothConnectionCallbackIdentity(sessionID: sessionID, baselineEpoch: state.withLock { $0.epoch })
    }
}

/// RouteSources hands each audio route worker a new controlled source that starts at `snapshot`.
final class RouteSources: Sendable {

    private let snapshot: BluetoothAudioRouteSnapshot?
    private let sources  = Mutex<[ControlledAudioRouteSource]>([])

    init(snapshot: BluetoothAudioRouteSnapshot?) {
        self.snapshot = snapshot
    }

    var latest: ControlledAudioRouteSource? {
        sources.withLock { $0.last }
    }

    var count: Int {
        sources.withLock { $0.count }
    }

    var make: @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource {
        { [self] queue in
            let source = ControlledAudioRouteSource(snapshot: snapshot)
            source.bind(to: queue)
            sources.withLock { $0.append(source) }
            return source
        }
    }
}

/// FakeMetadataReader answers every read with the metadata the test set last and counts the
/// reads. A device it holds is answered only once the test lets it through, so a test can put
/// that read after an event; the reads behind it wait too, as they do on the enricher's queue.
final class FakeMetadataReader: BluetoothDeviceMetadataReading {

    private let state  : Mutex<(metadata: BluetoothDeviceMetadata, reads: Int)>
    private let held   : String?
    private let release = DispatchSemaphore(value: 0)

    init(
        metadata: BluetoothDeviceMetadata,
        holding : String? = nil
    ) {
        self.state = Mutex((metadata: metadata, reads: 0))
        self.held  = holding
    }

    var reads: Int {
        state.withLock { $0.reads }
    }

    func answer(with metadata: BluetoothDeviceMetadata) {
        state.withLock { $0.metadata = metadata }
    }

    func letThrough() {
        release.signal()
    }

    func metadata(for deviceID: String) -> BluetoothDeviceMetadata {
        if deviceID == held {
            release.wait()
        }

        return state.withLock { state in
            state.reads += 1
            return state.metadata
        }
    }
}
