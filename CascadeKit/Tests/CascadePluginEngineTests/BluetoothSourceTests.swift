//
//  BluetoothSourceTests.swift
//  CascadeKit
//

import CascadeContracts
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

    private func source(
        _ system : FakeBluetoothSystem,
        metadata : BluetoothDeviceMetadata = BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 64), model: .airPods),
        routes   : RouteSources = RouteSources(snapshot: nil)
    ) -> (BluetoothSource, Recorder<PluginBluetoothState>) {
        let source = BluetoothSource(
            makeObserver      : system.makeObserver,
            metadataReader    : FixedMetadataReader(metadata: metadata),
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
    func startingEmitsABaselineAndDevicesAlreadyConnectedStaySilent() async throws {
        let system           = FakeBluetoothSystem(connected: [airPods])
        let (source, states) = source(system)
        #expect(try await eventually { states.values.count == 1 })

        system.latest?.connect(airPods)
        try await Task.sleep(for: .milliseconds(30))
        source.stop()

        #expect(states.values == [.baseline(isAvailable: true)])
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
        #expect(try await eventually { states.values.count == 3 })
        try await Task.sleep(for: .milliseconds(30))
        source.stop()

        let events = states.values.dropFirst()
        #expect(events.map(\.kind) == [.audioRoute, .audioRoute])
        #expect(events.map(\.eventID) == [1, 2])
        #expect(events.allSatisfy { $0.deviceID == "AA-BB-CC-DD-EE-FF" && $0.isConnected })
    }

    @Test
    func pluginHostOffersBluetooth() {
        #expect(PluginHostCatalog.names.contains(PluginBluetoothState.source))
    }
}

/// FakeBluetoothSystem stands in for IOBluetooth: it builds the source's connection observers,
/// says whether registering works and which devices are connected when a baseline is read.
final class FakeBluetoothSystem: Sendable {

    private let registers: Bool
    private let state    : Mutex<(observers: [FakeConnectionObserver], connected: [BluetoothConnectedDevice])>

    init(
        registers: Bool = true,
        connected: [BluetoothConnectedDevice] = []
    ) {
        self.registers = registers
        self.state     = Mutex((observers: [], connected: connected))
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
        system.connectedDevices
    }

    func finishBaselineReplacement() -> [IOBluetoothConnectionCallback] {
        []
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

/// FixedMetadataReader answers every read with the same metadata.
struct FixedMetadataReader: BluetoothDeviceMetadataReading {

    let metadata: BluetoothDeviceMetadata

    func metadata(for deviceID: String) -> BluetoothDeviceMetadata {
        metadata
    }
}
