//
//  AudioHostServiceTests.swift
//  CascadeKit
//

@testable import CascadeAudioHost
import AppKit
import CascadeAudioRender
import CascadeContracts
import CoreAudio
import Foundation
import Synchronization
import Testing

@Suite
struct AudioHostServiceTests {

    private static let builtIn = "built-in"
    private static let usb     = "usb"

    private let chrome  : AudioAppIdentity
    private let spotify : AudioAppIdentity

    init() throws {
        chrome  = try AudioAppIdentity(bundleID: "com.google.Chrome")
        spotify = try AudioAppIdentity(bundleID: "com.spotify.client")
    }

    // MARK: - Harness

    /// Harness wires a service to a fake HAL, a manual clock and scheduler, and a private
    /// notification center, and records every published snapshot.
    private final class Harness: Sendable {

        static let queueKey = SpecificKey()

        let hal       = FakeAudioHostHAL()
        let time      = ManualAudioHostTime()
        let queue     = DispatchQueue(label: "test.audiohost.control")
        let center    = NotificationCenter()
        let recorder  = SnapshotRecorder()

        nonisolated(unsafe) var service: AudioHostService?

        init(
            processes : [AudioProcessRecord],
            lookup    : (@Sendable (String) -> AudioBundleInfo?)? = nil
        ) {
            queue.setSpecific(key: Self.queueKey.key, value: ())

            let key = Self.queueKey

            hal.processRecords    = processes
            hal.outputs           = [AudioHostServiceTests.builtIn, AudioHostServiceTests.usb]
            hal.systemOutput      = AudioHostServiceTests.builtIn
            hal.isOnExpectedQueue = { DispatchQueue.getSpecific(key: key.key) != nil }

            let recorder = self.recorder

            service = AudioHostService(
                hal                : hal,
                queue              : queue,
                clock              : time.clock,
                schedule           : time.schedule,
                publish            : { snapshot in recorder.record(snapshot) },
                bundleInfo         : lookup ?? { _ in nil },
                notificationCenter : center
            )

            flush()
        }

        var latest: AudioHostSnapshot? {
            recorder.latest
        }

        var publishedCount: Int {
            recorder.count
        }

        func flush() {
            queue.sync {}
        }

        func advance(_ interval: Duration) {
            time.advance(by: interval, flush: flush)
        }

        func send(_ command: AudioHostCommand) throws -> Bool {
            try sendRaw(try AudioHostWire.encode(command))
        }

        func sendRaw(_ data: Data) throws -> Bool {
            let semaphore = DispatchSemaphore(value: 0)
            let accepted  = Mutex(false)

            try #require(service).send(data) { reply in
                accepted.withLock { $0 = reply }
                semaphore.signal()
            }

            #expect(semaphore.wait(timeout: .now() + 5) == .success)

            return accepted.withLock { $0 }
        }

        func count(_ matches: (FakeAudioHostHAL.Call) -> Bool) -> Int {
            hal.calls.filter(matches).count
        }

        var tapCount      : Int { count { if case .createTap = $0 { true } else { false } } }
        var teardownCount : Int { count { if case .destroyTap = $0 { true } else { false } } }
        var stopCount     : Int { count { if case .stop = $0 { true } else { false } } }
    }

    /// SnapshotRecorder keeps what the service published, safe to read from the test thread.
    private final class SnapshotRecorder: Sendable {

        private let snapshots = Mutex<[AudioHostSnapshot]>([])

        var latest: AudioHostSnapshot? { snapshots.withLock { $0.last } }
        var count : Int                { snapshots.withLock { $0.count } }

        func record(_ snapshot: AudioHostSnapshot) {
            snapshots.withLock { $0.append(snapshot) }
        }
    }

    /// SpecificKey carries a `DispatchSpecificKey` into `@Sendable` closures; the key is an
    /// immutable token that is only ever compared, never mutated.
    private struct SpecificKey: @unchecked Sendable {

        let key = DispatchSpecificKey<Void>()
    }

    // MARK: - Fixtures

    private func record(
        _ objectID : UInt32,
        _ bundleID : String,
        running    : Bool    = true,
        path       : String? = nil
    ) -> AudioProcessRecord {
        AudioProcessRecord(
            objectID        : objectID,
            pid             : Int32(objectID),
            bundleID        : bundleID,
            executablePath  : path,
            isRunningOutput : running
        )
    }

    private func intent(
        gain    : Double   = 0.5,
        outputs : [String] = []
    ) throws -> AudioAppIntent {
        try AudioAppIntent(gain: gain, isMuted: false, outputUIDs: outputs)
    }

    private func chromeApp(in snapshot: AudioHostSnapshot?) -> AudioAppSnapshot? {
        snapshot?.apps.first { $0.identity == chrome }
    }

    /// Pushes one slice of audio through the kernel the service's last pipeline was given, the
    /// way the IOProc would, so its callback count moves.
    private func pushAudio(through hal: FakeAudioHostHAL) throws {
        let render = try #require(hal.startedRender)
        let frames = 64

        let input  = [Float](repeating: 0.1, count: frames * 2)
        var output = [Float](repeating: 0, count: frames * 2)

        input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                let inputList  = AudioBufferList.allocate(maximumBuffers: 1)
                let outputList = AudioBufferList.allocate(maximumBuffers: 1)
                defer {
                    free(inputList.unsafeMutablePointer)
                    free(outputList.unsafeMutablePointer)
                }

                inputList[0] = AudioBuffer(
                    mNumberChannels : 2,
                    mDataByteSize   : UInt32(inputBytes.count),
                    mData           : UnsafeMutableRawPointer(mutating: inputBytes.baseAddress)
                )
                outputList[0] = AudioBuffer(
                    mNumberChannels : 2,
                    mDataByteSize   : UInt32(outputBytes.count),
                    mData           : outputBytes.baseAddress
                )

                CascadeAudioRenderProcess(
                    render,
                    inputList.unsafePointer,
                    outputList.unsafeMutablePointer,
                    UInt32(frames)
                )
            }
        }
    }

    // MARK: - Intents

    @Test
    func setIntentBuildsAndPublishesApplied() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        let initial = try #require(chromeApp(in: harness.latest))
        #expect(initial.enforcement == .native)
        #expect(initial.intent.isNeutral)
        #expect(harness.latest?.generation == 1)
        #expect(harness.hal.calls.isEmpty)

        #expect(try harness.send(.setIntent(chrome, try intent(gain: 0.5))))

        #expect(
            harness.hal.calls == [
                .createTap(processObjectIDs: [10], streamOfOutput: Self.builtIn),
                .createAggregate(tapUUID: FakeAudioHostHAL.tapUUID, outputUIDs: [Self.builtIn]),
                .streamFormat(ofOutput: Self.builtIn),
                .start(aggregate: FakeAudioHostHAL.aggregateID),
            ]
        )

        let applied = try #require(chromeApp(in: harness.latest))
        #expect(applied.enforcement == .applied)
        #expect(applied.intent.gain == 0.5)
        #expect(applied.effectiveOutputUIDs == [Self.builtIn])
        #expect(harness.latest?.generation == 2)
        #expect(harness.latest?.captureAllowed == nil)
    }

    @Test
    func neutralIntentTearsDownAndPublishesNative() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        #expect(try harness.send(.setIntent(chrome, try intent())))
        #expect(harness.teardownCount == 0)

        #expect(try harness.send(.setIntent(chrome, .neutral)))

        #expect(harness.stopCount == 1)
        #expect(harness.teardownCount == 1)

        let native = try #require(chromeApp(in: harness.latest))
        #expect(native.enforcement == .native)
        #expect(native.intent.isNeutral)
    }

    @Test
    func replaceIntentsAppliesTheWholeSet() throws {
        let harness = Harness(
            processes: [record(10, "com.google.Chrome"), record(20, "com.spotify.client")]
        )

        #expect(try harness.send(.replaceIntents([chrome: try intent(gain: 0.5)])))
        #expect(harness.tapCount == 1)
        #expect(harness.hal.calls.contains(.createTap(processObjectIDs: [10], streamOfOutput: Self.builtIn)))

        #expect(try harness.send(.replaceIntents([spotify: try intent(gain: 0.25)])))

        // Chrome is absent from the new set, so it is back to neutral and its pipeline is gone;
        // Spotify, new in the set, has one.
        #expect(harness.hal.calls.contains(.createTap(processObjectIDs: [20], streamOfOutput: Self.builtIn)))
        #expect(harness.teardownCount == 1)

        let apps = try #require(harness.latest).apps
        #expect(apps.map(\.identity) == [chrome, spotify])
        #expect(apps[0].enforcement == .native)
        #expect(apps[0].intent.isNeutral)
        #expect(apps[1].enforcement == .applied)
        #expect(apps[1].intent.gain == 0.25)
    }

    @Test
    func returnToNativeClearsANativeFallback() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        #expect(try harness.send(.setIntent(chrome, try intent())))

        // A pipeline that stalls and, once rebuilt, stalls again is a configuration the host
        // gives up on: the watchdog reports each stall as a broken running pipeline, and the
        // second episode for the same configuration is the verdict.
        harness.advance(.seconds(3))
        #expect(harness.tapCount == 2)

        harness.advance(.seconds(3))
        #expect(harness.tapCount == 2)
        #expect(chromeApp(in: harness.latest)?.enforcement == .notApplied)

        #expect(try harness.send(.returnToNative(chrome)))

        let native = try #require(chromeApp(in: harness.latest))
        #expect(native.enforcement == .native)
        #expect(native.intent.isNeutral)
    }

    @Test
    func aMalformedCommandIsRejected() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])
        let before  = harness.publishedCount

        #expect(try harness.sendRaw(Data("not a command".utf8)) == false)
        #expect(harness.publishedCount == before)
    }

    // MARK: - Apps

    @Test
    func appLeavesThreeSecondsAfterSilence() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])
        #expect(harness.latest?.apps.count == 1)

        let published = harness.publishedCount

        harness.hal.processRecords = [record(10, "com.google.Chrome", running: false)]
        harness.hal.onProcesses?()
        harness.flush()

        // Silent but still listed, and listing it again is not a new snapshot.
        #expect(harness.latest?.apps.count == 1)
        #expect(harness.publishedCount == published)
        #expect(harness.time.pendingDelays == [.seconds(3)])

        harness.advance(.milliseconds(2_900))
        #expect(harness.latest?.apps.count == 1)

        harness.advance(.milliseconds(200))
        #expect(harness.latest?.apps.isEmpty == true)
        #expect(harness.time.pendingCount == 0)
    }

    @Test
    func anAppThatResumesStaysListed() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        harness.hal.processRecords = [record(10, "com.google.Chrome", running: false)]
        harness.hal.onProcesses?()
        harness.flush()

        harness.advance(.seconds(2))

        harness.hal.processRecords = [record(10, "com.google.Chrome")]
        harness.hal.onProcesses?()
        harness.flush()

        harness.advance(.seconds(5))
        #expect(harness.latest?.apps.count == 1)
    }

    @Test
    func lateHelperJoinsTheAppsTap() throws {
        let appPath    = "/Applications/Chrome.app"
        let helperPath = "\(appPath)/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        let chromeInfo = AudioBundleInfo(bundleID: "com.google.Chrome", displayName: "Google Chrome")

        let harness = Harness(
            processes: [record(10, "com.google.Chrome", path: "\(appPath)/Contents/MacOS/Chrome")],
            lookup   : { path in path == appPath ? chromeInfo : nil }
        )

        #expect(try harness.send(.setIntent(chrome, try intent())))
        #expect(harness.hal.calls.contains(.createTap(processObjectIDs: [10], streamOfOutput: Self.builtIn)))

        // The helper starts playing after the tap exists. The tap is built for a fixed set of
        // processes, so it must be rebuilt to include the newcomer, not left deaf to it.
        harness.hal.processRecords.append(
            record(11, "com.google.Chrome.helper", path: helperPath)
        )
        harness.hal.onProcesses?()
        harness.flush()

        #expect(harness.teardownCount == 1)
        #expect(harness.hal.calls.contains(.createTap(processObjectIDs: [10, 11], streamOfOutput: Self.builtIn)))

        let apps = try #require(harness.latest).apps
        #expect(apps.count == 1)
        #expect(apps[0].displayName == "Google Chrome")
        #expect(apps[0].enforcement == .applied)
    }

    @Test
    func appsAreSortedByDisplayName() throws {
        let zebra = AudioBundleInfo(bundleID: "com.example.zebra", displayName: "Zebra")
        let apple = AudioBundleInfo(bundleID: "com.example.apple", displayName: "apple")

        let harness = Harness(
            processes: [
                record(10, "com.example.zebra", path: "/Applications/Zebra.app/Contents/MacOS/z"),
                record(20, "com.example.apple", path: "/Applications/Apple.app/Contents/MacOS/a"),
            ],
            lookup: { path in
                switch path {
                    case "/Applications/Zebra.app": zebra
                    case "/Applications/Apple.app": apple
                    default: nil
                }
            }
        )

        #expect(harness.latest?.apps.map(\.displayName) == ["apple", "Zebra"])
    }

    // MARK: - Environment

    @Test
    func wakeRebuilds() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        #expect(try harness.send(.setIntent(chrome, try intent())))
        #expect(harness.tapCount == 1)

        harness.center.post(name: NSWorkspace.didWakeNotification, object: nil)
        harness.flush()

        #expect(harness.teardownCount == 1)
        #expect(harness.tapCount == 2)
        #expect(chromeApp(in: harness.latest)?.enforcement == .applied)

        harness.hal.onServiceRestart?()
        harness.flush()

        #expect(harness.teardownCount == 2)
        #expect(harness.tapCount == 3)
    }

    @Test
    func crossfadeKeepsBothPipelinesAtMostHundredMilliseconds() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        #expect(try harness.send(.setIntent(chrome, try intent(outputs: [Self.builtIn]))))
        #expect(harness.tapCount == 1)

        #expect(try harness.send(.setIntent(chrome, try intent(outputs: [Self.usb]))))

        // The new pipeline is up beside the old one, which has not been touched yet.
        #expect(harness.tapCount == 2)
        #expect(harness.hal.calls.contains(.createTap(processObjectIDs: [10], streamOfOutput: Self.usb)))
        #expect(harness.stopCount == 0)
        #expect(harness.teardownCount == 0)
        #expect(harness.time.pendingDelays.contains(.milliseconds(100)))

        harness.advance(.milliseconds(99))
        #expect(harness.stopCount == 0)

        harness.advance(.milliseconds(1))
        #expect(harness.stopCount == 1)
        #expect(harness.teardownCount == 1)

        let app = try #require(chromeApp(in: harness.latest))
        #expect(app.enforcement == .applied)
        #expect(app.effectiveOutputUIDs == [Self.usb])
    }

    @Test
    func aFailedCrossfadeLeavesTheOldPipelineRunning() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        #expect(try harness.send(.setIntent(chrome, try intent(outputs: [Self.builtIn]))))

        harness.hal.tapShouldFail = true
        #expect(try harness.send(.setIntent(chrome, try intent(outputs: [Self.usb]))))

        #expect(harness.stopCount == 0)
        #expect(harness.teardownCount == 0)
        #expect(chromeApp(in: harness.latest)?.effectiveOutputUIDs == [Self.builtIn])
    }

    // MARK: - Watchdog

    @Test
    func watchdogStartsOnlyWithRunningPipelines() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        // A listed app with a neutral intent has nothing tapped, hence nothing to watch.
        #expect(harness.time.pendingCount == 0)

        #expect(try harness.send(.setIntent(chrome, try intent())))
        #expect(harness.time.pendingDelays == [.seconds(1)])

        harness.advance(.seconds(1))
        #expect(harness.time.pendingDelays == [.seconds(1)])

        #expect(try harness.send(.setIntent(chrome, .neutral)))

        // The chain ends by itself: the tick that finds nothing running does not re-arm.
        harness.advance(.seconds(1))
        #expect(harness.time.pendingCount == 0)
    }

    @Test
    func staleCallbacksTriggerRecovery() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        #expect(try harness.send(.setIntent(chrome, try intent())))
        #expect(harness.tapCount == 1)

        // The first tick is a baseline, the next two are stale: nothing happens before the third.
        harness.advance(.seconds(2))
        #expect(harness.teardownCount == 0)

        harness.advance(.seconds(1))
        #expect(harness.teardownCount == 1)
        #expect(harness.tapCount == 2)
        #expect(chromeApp(in: harness.latest)?.enforcement == .applied)
    }

    @Test
    func aPipelineThatKeepsRenderingIsLeftAlone() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        #expect(try harness.send(.setIntent(chrome, try intent())))

        for _ in 0..<6 {
            try pushAudio(through: harness.hal)
            harness.advance(.seconds(1))
        }

        #expect(harness.teardownCount == 0)
        #expect(harness.tapCount == 1)
    }

    // MARK: - Threading

    @Test
    func noHALCallOffTheControlQueue() throws {
        let harness = Harness(processes: [record(10, "com.google.Chrome")])

        #expect(try harness.send(.setIntent(chrome, try intent(outputs: [Self.builtIn]))))
        #expect(try harness.send(.setIntent(chrome, try intent(outputs: [Self.usb]))))

        harness.hal.processRecords.append(record(11, "com.google.Chrome"))
        harness.hal.onProcesses?()
        harness.hal.onDevices?()
        harness.center.post(name: NSWorkspace.didWakeNotification, object: nil)
        harness.flush()

        // The scheduler may fire on any thread; the service must bring the work to its queue.
        DispatchQueue.global().sync {
            harness.advance(.seconds(4))
        }

        #expect(!harness.hal.calls.isEmpty)
        #expect(harness.hal.offQueueCallCount == 0)
    }

    @Test
    func helloRepliesWithThePID() throws {
        let harness   = Harness(processes: [])
        let semaphore = DispatchSemaphore(value: 0)
        let received  = Mutex<Int32>(0)

        try #require(harness.service).hello { pid in
            received.withLock { $0 = pid }
            semaphore.signal()
        }

        #expect(semaphore.wait(timeout: .now() + 5) == .success)
        #expect(received.withLock { $0 } == getpid())
    }
}
