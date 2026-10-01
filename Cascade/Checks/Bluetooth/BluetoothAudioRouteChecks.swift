//
//  BluetoothAudioRouteChecks.swift
//  Cascade
//

#if BLUETOOTH_AUDIO_ROUTE_TESTS
import AppKit
import CoreAudio
import Foundation

@main
struct BluetoothAudioRouteChecks {

    static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            fatalError("FAIL: audio route lifecycle failed to register, resume or finish its stream")
        }

        let builtIn = BluetoothAudioRouteSnapshot(
            uid          : "BuiltInSpeakerDevice",
            name         : "Mac speakers",
            transportType: kAudioDeviceTransportTypeBuiltIn
        )
        let airPods = BluetoothAudioRouteSnapshot(
            uid          : "EC-46-54-00-4B-67:output",
            name         : "Bellsprouts",
            transportType: kAudioDeviceTransportTypeBluetooth
        )

        var reducer = BluetoothAudioRouteReducer()
        expect(reducer.receive(airPods) == nil, "startup already routed to AirPods is silent")
        expect(reducer.receive(builtIn) == nil, "leaving Bluetooth updates the baseline silently")
        expect(
            reducer.receive(airPods)?.deviceID == "EC-46-54-00-4B-67",
            "return to AirPods emits even while ACL remains connected"
        )
        expect(
            reducer.receive(airPods) == nil,
            "repeated CoreAudio and Darwin hints do not duplicate the event"
        )
        expect(reducer.receive(nil) == nil, "unavailable output updates the baseline silently")
        expect(
            reducer.receive(airPods)?.name == "Bellsprouts",
            "return after absent output emits current name"
        )

        reducer.replaceBaseline(airPods)
        expect(reducer.receive(airPods) == nil, "wake snapshot does not replay current AirPods")

        let other = BluetoothAudioRouteSnapshot(
            uid          : "AA-BB-CC-DD-EE-FF:output",
            name         : "Second headphones",
            transportType: kAudioDeviceTransportTypeBluetoothLE
        )
        expect(
            reducer.receive(other)?.deviceID == "AA-BB-CC-DD-EE-FF",
            "switch between different Bluetooth outputs emits new device"
        )

        for uid in [
            "EC-46-54-00-4B-67:input",
            "EC-46-54-00-4B-67:output:extra",
            "prefix-EC-46-54-00-4B-67:output",
            "EC-46-54-00-4B-6Z:output",
            "EC-46-54-00-4B-67:output ",
            "Bellsprouts",
            "ec4654004b67",
            "EC:46:54:00:4B:67:output"
        ] {
            reducer.replaceBaseline(builtIn)

            let invalid = BluetoothAudioRouteSnapshot(
                uid          : uid,
                name         : "Bellsprouts",
                transportType: kAudioDeviceTransportTypeBluetooth
            )
            expect(
                reducer.receive(invalid) == nil,
                "unverified UID must not invent an address: \(uid)"
            )
        }

        reducer.replaceBaseline(builtIn)

        let virtual = BluetoothAudioRouteSnapshot(
            uid          : airPods.uid,
            name         : "Fake AirPods",
            transportType: kAudioDeviceTransportTypeVirtual
        )
        expect(
            reducer.receive(virtual) == nil,
            "virtual output cannot impersonate Bluetooth through its UID"
        )

        reducer.replaceBaseline(nil)

        let lowerCase = BluetoothAudioRouteSnapshot(
            uid          : "ec-46-54-00-4b-67:output",
            name         : "Bellsprouts",
            transportType: kAudioDeviceTransportTypeBluetooth
        )
        expect(
            reducer.receive(lowerCase)?.deviceID == "EC-46-54-00-4B-67",
            "hexadecimal casing normalizes to the connection address"
        )

        await checkMonitorLifecycle(builtIn: builtIn, airPods: airPods)

        print("Bluetooth audio route checks passed")
    }

    private static func checkMonitorLifecycle(
        builtIn: BluetoothAudioRouteSnapshot,
        airPods: BluetoothAudioRouteSnapshot
    ) async {
        let source    = ControlledAudioRouteSource(snapshot: airPods)
        let workspace = NotificationCenter()
        let monitor   = BluetoothAudioRouteMonitor(
            workspaceCenter: workspace,
            sourceFactory  : { queue in
                source.bind(to: queue)
                return source
            }
        )

        let stream    = monitor.start()
        let collector = Task { () -> [BluetoothConnectedDevice] in
            var values: [BluetoothConnectedDevice] = []
            for await value in stream { values.append(value) }

            return values
        }

        await source.waitForRegistration()
        await source.change(to: builtIn)
        await source.change(to: airPods)
        await source.change(to: airPods)
        await source.failRead()
        await source.change(to: airPods)

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        await source.change(to: builtIn)
        await source.change(to: airPods)

        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await source.waitForRegistration()
        await source.change(to: airPods)
        await source.change(to: builtIn)
        await source.change(to: airPods)
        await source.change(to: builtIn, notifies: false)

        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await source.waitForRegistration()
        await source.change(to: airPods)

        monitor.stop()
        await source.change(to: builtIn, includingRemovedCallback: true)
        await source.change(to: airPods, includingRemovedCallback: true)

        let result = await collector.value
        expect(
            result.map(\.deviceID) == ["EC-46-54-00-4B-67", "EC-46-54-00-4B-67", "EC-46-54-00-4B-67"],
            "monitor emits route returns, suppresses duplicates/sleep/wake baseline and stale callbacks"
        )
        expect(
            source.registrationBalance == 0,
            "stop unregisters both startup and resumed listeners"
        )

        let unavailableSource = ControlledAudioRouteSource(
            snapshot            : airPods,
            registrationSucceeds: false
        )
        let unavailable = BluetoothAudioRouteMonitor(
            workspaceCenter: workspace,
            sourceFactory  : { queue in
                unavailableSource.bind(to: queue)
                return unavailableSource
            }
        )
        var unavailableIterator = unavailable.start().makeAsyncIterator()
        let unavailableValue    = await unavailableIterator.next()
        expect(
            unavailableValue == nil,
            "failed registration finishes stream without a fabricated connection"
        )

        unavailable.stop()
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message  : String
    ) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }
}

/// ControlledAudioRouteSource replaces only the external CoreAudio
/// registration/read boundary. The production worker, reducer, stream and
/// workspace lifecycle execute normally.
nonisolated private final class ControlledAudioRouteSource: BluetoothAudioRouteSource, @unchecked Sendable {

    private let lock                 = NSLock()
    private var queue               : DispatchQueue?
    private var current             : BluetoothAudioRouteReadResult
    private var handler             : (@Sendable () -> Void)?
    private var removedHandler      : (@Sendable () -> Void)?
    private let registrationSucceeds: Bool
    private var balance              = 0
    private let starts               = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)

    init(
        snapshot            : BluetoothAudioRouteSnapshot?,
        registrationSucceeds: Bool = true
    ) {
        current                   = snapshot.map(BluetoothAudioRouteReadResult.output) ?? .noOutput
        self.registrationSucceeds = registrationSucceeds
    }

    var registrationBalance: Int { lock.withLock { balance } }

    func bind(to queue: DispatchQueue) { lock.withLock { self.queue = queue } }

    func start(onChange: @escaping @Sendable () -> Void) -> Bool {
        if registrationSucceeds {
            handler = onChange
            lock.withLock { balance += 1 }
        }

        starts.continuation.yield(())

        return registrationSucceeds
    }

    func snapshot() -> BluetoothAudioRouteReadResult { current }

    func stop() {
        if let handler {
            removedHandler = handler
            self.handler   = nil
            lock.withLock { balance -= 1 }
        }
    }

    func failRead() async {
        guard let queue = lock.withLock({ queue }) else { fatalError("Source was never bound") }

        await withCheckedContinuation { continuation in
            queue.async { [self] in
                current = .unavailable
                handler?()
                queue.async { continuation.resume() }
            }
        }
    }

    func waitForRegistration() async {
        var iterator = starts.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func change(
        to snapshot             : BluetoothAudioRouteSnapshot?,
        includingRemovedCallback: Bool = false,
        notifies                : Bool = true
    ) async {
        guard let queue = lock.withLock({ queue }) else { fatalError("Source was never bound") }

        await withCheckedContinuation { continuation in
            queue.async { [self] in
                current = snapshot.map(BluetoothAudioRouteReadResult.output) ?? .noOutput
                if notifies { (handler ?? (includingRemovedCallback ? removedHandler : nil))?() }
                // The production callback schedules the read on this queue; this
                // second item is a barrier after that read, with no timed sleeps.
                queue.async { continuation.resume() }
            }
        }
    }
}

#endif
