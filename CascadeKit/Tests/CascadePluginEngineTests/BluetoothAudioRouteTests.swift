//
//  BluetoothAudioRouteTests.swift
//  CascadeKit
//

import CoreAudio
import Foundation
import Synchronization
import Testing

@testable import CascadePluginHost

/// BluetoothAudioRouteTests are Cascade's audio route checks, carried over with the worker into
/// PluginHost: a return to Bluetooth output is an event even while the link stays connected,
/// duplicates and read failures are silent, only a verified output UID names a device, and a
/// stopped worker publishes nothing.
@Suite
struct BluetoothAudioRouteTests {

    private let builtIn = BluetoothAudioRouteSnapshot(uid: "BuiltInSpeakerDevice", name: "Mac speakers", transportType: kAudioDeviceTransportTypeBuiltIn)
    private let airPods = BluetoothAudioRouteSnapshot(uid: "EC-46-54-00-4B-67:output", name: "Bellsprouts", transportType: kAudioDeviceTransportTypeBluetooth)

    @Test
    func aReturnToBluetoothEmitsAndEverythingElseOnlyMovesTheBaseline() {
        var reducer = BluetoothAudioRouteReducer()
        let other   = BluetoothAudioRouteSnapshot(uid: "AA-BB-CC-DD-EE-FF:output", name: "Second headphones", transportType: kAudioDeviceTransportTypeBluetoothLE)

        let atStartup  = reducer.receive(airPods)
        let leaving    = reducer.receive(builtIn)
        let returning  = reducer.receive(airPods)
        let duplicate  = reducer.receive(airPods)
        let absent     = reducer.receive(nil)
        let afterGap   = reducer.receive(airPods)
        reducer.replaceBaseline(airPods)
        let afterWake  = reducer.receive(airPods)
        let switchedTo = reducer.receive(other)

        #expect(atStartup == nil)
        #expect(leaving == nil)
        #expect(returning?.deviceID == "EC-46-54-00-4B-67")
        #expect(duplicate == nil)
        #expect(absent == nil)
        #expect(afterGap?.name == "Bellsprouts")
        #expect(afterWake == nil)
        #expect(switchedTo?.deviceID == "AA-BB-CC-DD-EE-FF")
    }

    @Test
    func onlyAVerifiedBluetoothOutputUIDNamesADevice() {
        let unverified = [
            "EC-46-54-00-4B-67:input",
            "EC-46-54-00-4B-67:output:extra",
            "prefix-EC-46-54-00-4B-67:output",
            "EC-46-54-00-4B-6Z:output",
            "EC-46-54-00-4B-67:output ",
            "Bellsprouts",
            "ec4654004b67",
            "EC:46:54:00:4B:67:output",
        ]

        for uid in unverified {
            var reducer = BluetoothAudioRouteReducer()
            reducer.replaceBaseline(builtIn)

            let device = reducer.receive(BluetoothAudioRouteSnapshot(uid: uid, name: "Bellsprouts", transportType: kAudioDeviceTransportTypeBluetooth))
            #expect(device == nil, "\(uid) must not invent an address")
        }

        var reducer = BluetoothAudioRouteReducer()
        reducer.replaceBaseline(builtIn)
        let virtual = reducer.receive(BluetoothAudioRouteSnapshot(uid: airPods.uid, name: "Fake AirPods", transportType: kAudioDeviceTransportTypeVirtual))
        reducer.replaceBaseline(nil)
        let lowerCase = reducer.receive(BluetoothAudioRouteSnapshot(uid: "ec-46-54-00-4b-67:output", name: "Bellsprouts", transportType: kAudioDeviceTransportTypeBluetooth))

        #expect(virtual == nil)
        #expect(lowerCase?.deviceID == "EC-46-54-00-4B-67")
    }

    @Test
    func theWorkerEmitsReturnsAndNothingOnceStopped() async {
        let source = ControlledAudioRouteSource(snapshot: airPods)
        let routes = Mutex<[String]>([])
        let worker = BluetoothAudioRouteWorker(
            sourceFactory: { queue in
                source.bind(to: queue)
                return source
            },
            onRoute      : { device in routes.withLock { $0.append(device.deviceID) } }
        )

        worker.start()
        await source.waitForRegistration()
        await source.change(to: builtIn)
        await source.change(to: airPods)
        await source.change(to: airPods)
        await source.failRead()
        await source.change(to: airPods)
        worker.stop()
        await source.change(to: builtIn, includingRemovedCallback: true)
        await source.change(to: airPods, includingRemovedCallback: true)

        #expect(routes.withLock { $0 } == ["EC-46-54-00-4B-67"])
        #expect(source.registrationBalance == 0)
    }

    @Test
    func aFailedRegistrationNeverFabricatesARoute() async {
        let source = ControlledAudioRouteSource(snapshot: airPods, registrationSucceeds: false)
        let routes = Mutex(0)
        let worker = BluetoothAudioRouteWorker(
            sourceFactory: { queue in
                source.bind(to: queue)
                return source
            },
            onRoute      : { _ in routes.withLock { $0 += 1 } }
        )

        worker.start()
        await source.waitForRegistration()
        await source.change(to: builtIn, includingRemovedCallback: true)
        await source.change(to: airPods, includingRemovedCallback: true)
        worker.stop()

        #expect(routes.withLock { $0 } == 0)
        #expect(source.registrationBalance == 0)
    }
}

/// ControlledAudioRouteSource replaces only the CoreAudio registration and read boundary; the
/// worker and its reducer run as they do in PluginHost. Every change runs on the worker's queue
/// and resumes after a second block on it, which comes after the read the change triggered, so
/// the test needs no timed sleeps. Its state is touched only on that queue, except the lock-held
/// queue and balance, which is what makes it safe to share.
final class ControlledAudioRouteSource: BluetoothAudioRouteSource, @unchecked Sendable {

    private let lock                 = NSLock()
    private let registrationSucceeds: Bool
    private let starts               = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)

    private var queue         : DispatchQueue?
    private var current       : BluetoothAudioRouteReadResult
    private var handler       : (@Sendable () -> Void)?
    private var removedHandler: (@Sendable () -> Void)?
    private var balance        = 0

    init(
        snapshot            : BluetoothAudioRouteSnapshot?,
        registrationSucceeds: Bool = true
    ) {
        current                   = snapshot.map(BluetoothAudioRouteReadResult.output) ?? .noOutput
        self.registrationSucceeds = registrationSucceeds
    }

    var registrationBalance: Int {
        lock.withLock { balance }
    }

    func bind(to queue: DispatchQueue) {
        lock.withLock { self.queue = queue }
    }

    func start(onChange: @escaping @Sendable () -> Void) -> Bool {
        if registrationSucceeds {
            handler = onChange
            lock.withLock { balance += 1 }
        }
        starts.continuation.yield(())

        return registrationSucceeds
    }

    func snapshot() -> BluetoothAudioRouteReadResult {
        current
    }

    func stop() {
        guard let handler else { return }

        removedHandler = handler
        self.handler   = nil
        lock.withLock { balance -= 1 }
    }

    func waitForRegistration() async {
        var iterator = starts.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func failRead() async {
        await onQueue { source in
            source.current = .unavailable
            source.handler?()
        }
    }

    func change(
        to snapshot             : BluetoothAudioRouteSnapshot?,
        includingRemovedCallback: Bool = false
    ) async {
        await onQueue { source in
            source.current = snapshot.map(BluetoothAudioRouteReadResult.output) ?? .noOutput
            (source.handler ?? (includingRemovedCallback ? source.removedHandler : nil))?()
        }
    }

    private func onQueue(_ work: @escaping @Sendable (ControlledAudioRouteSource) -> Void) async {
        guard let queue = lock.withLock({ queue }) else { return }

        await withCheckedContinuation { continuation in
            queue.async { [self] in
                work(self)
                queue.async { continuation.resume() }
            }
        }
    }
}
