//
//  AudioSpectrumBehaviorChecks.swift
//  Cascade
//

#if AUDIO_SPECTRUM_TESTS

import Foundation
import AudioToolbox
import Dispatch
import os

@main
enum AudioSpectrumBehaviorChecks {

    static func main() async {
        await checkStartupPermissionRequest()

        let analyzer = AudioSpectrumAnalyzer()
        let silence  = [Float](repeating: 0, count: 2_048)
        check(measure(analyzer, silence) == .silence, "Silence must produce six exact zeros")

        // Moving a tone through the audible spectrum must move the strongest bar.
        // Canned motion, broadband RMS, or identical per-band math fails this check.
        for (frequency, band) in [(93.75, 0), (281.25, 1), (750.0, 2), (2_250.0, 3), (6_000.0, 4), (12_000.0, 5)] {
            let isolatedAnalyzer = AudioSpectrumAnalyzer()
            let tone             = signal(frequency: frequency, amplitude: 0.4)
            var frame            = AudioSpectrumFrame.silence

            for _ in 0..<8 {
                frame = measure(isolatedAnalyzer, tone)
            }

            let strongest = frame.bands.enumerated().max { $0.element < $1.element }?.offset
            check(
                strongest == band,
                "Tone at \(frequency) Hz must dominate band \(band), got \(frame.bands)"
            )
            check(frame.bands[band] > 0.5, "An audible tone must not be suppressed")
        }

        let quiet = measure(AudioSpectrumAnalyzer(), signal(frequency: 750, amplitude: 0.015))
        let loud  = measure(AudioSpectrumAnalyzer(), signal(frequency: 750, amplitude: 0.7))
        check(loud.bands[2] > quiet.bands[2], "Actual amplitude must control height")

        let transientAnalyzer = AudioSpectrumAnalyzer()
        var impulse           = silence
        impulse[1_024]        = 1

        let transient = measure(transientAnalyzer, impulse)
        check(transient.bands.contains { $0 > 0 }, "A real transient must register")
        check(
            measure(transientAnalyzer, silence) == .silence,
            "Silent PCM must immediately clear old energy"
        )

        let antiphaseTone = signal(frequency: 750, amplitude: 0.4)
        let invertedTone  = antiphaseTone.map { -$0 }
        let stereo        = antiphaseTone.withUnsafeBufferPointer { left in
            invertedTone.withUnsafeBufferPointer { right in
                AudioSpectrumAnalyzer().analyze(
                    left      : left,
                    right     : right,
                    sampleRate: 48_000
                )
            }
        }
        check(stereo.bands[2] > 0, "Opposite stereo phases must not cancel audible energy")

        let invalid = [Float](repeating: .nan, count: 2_048)
        check(
            measure(AudioSpectrumAnalyzer(), invalid) == .silence,
            "Invalid samples must not escape as NaN"
        )
        check(
            loud.bands.allSatisfy { $0.isFinite && (0...1).contains($0) },
            "Bars must be finite and normalized"
        )

        checkPCMExchange()
        await checkMonitorLifecycle()

        print("Audio spectrum checks passed")
    }

    /// checkPCMExchange catches corrupted stereo transfer, stale windows, and publication faster than PCM cadence.
    static func checkPCMExchange() {
        let signal = DispatchSource.makeUserDataAddSource(queue: .global(qos: .utility))
        signal.setEventHandler { @Sendable in }
        signal.resume()
        defer { signal.cancel() }

        let exchange = AudioSpectrumPCMExchange(sampleRate: 48_000, signal: signal)
        let left     = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
        let right    = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
        left.initialize(repeating: 0, count: 2_048)
        right.initialize(repeating: 0, count: 2_048)

        defer {
            left.deallocate()
            right.deallocate()
        }

        check(!exchange.copyLatest(left: left, right: right), "No PCM must mean no new snapshot")

        feed(
            exchange,
            frames: 1_024,
            value : 0.25
        )
        check(
            !exchange.copyLatest(left: left, right: right),
            "A partial initial window cannot be analyzed"
        )
        feed(
            exchange,
            frames: 1_024,
            value : 0.25
        )
        check(exchange.copyLatest(left: left, right: right), "A full window must become available")
        check(left[0] == 0.25 && right[0] == -0.25, "Stereo channels and signs must survive capture")
        check(!exchange.copyLatest(left: left, right: right), "Reading must consume the snapshot")

        feed(
            exchange,
            frames: 800,
            value : 0.5
        )
        check(
            !exchange.copyLatest(left: left, right: right),
            "Sub-cadence callbacks must not wake a new analysis"
        )
        feed(
            exchange,
            frames: 800,
            value : 0.5
        )
        check(
            exchange.copyLatest(left: left, right: right),
            "Publication must resume at the PCM cadence"
        )
        check(
            left[0] == 0.25 && left[2_047] == 0.5,
            "The rolling window must preserve chronological PCM"
        )

        for value: Float in [0.6, 0.7, 0.8, 0.9] {
            feed(
                exchange,
                frames: 2_048,
                value : value
            )
        }
        check(
            exchange.copyLatest(left: left, right: right),
            "A slow consumer must still receive bounded snapshots"
        )
        check(
            left[2_047] == 0.8,
            "The newest available slot must win; a full exchange drops later input"
        )
        check(!exchange.copyLatest(left: left, right: right), "Drain must reclaim all ready slots")

        feed(
            exchange,
            frames: 2_048,
            value : 1
        )
        check(
            exchange.copyLatest(left: left, right: right) && left[0] == 1,
            "Capture must recover after backpressure"
        )
    }

    static func feed(
        _ exchange: AudioSpectrumPCMExchange,
        frames    : Int,
        value     : Float
    ) {
        var samples = [Float](repeating: value, count: frames * 2)
        for index in stride(from: 1, to: samples.count, by: 2) {
            samples[index] = -value
        }

        samples.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers      : AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize  : UInt32(bytes.count),
                    mData          : bytes.baseAddress
                )
            )
            withUnsafePointer(to: &list) { exchange.receive($0) }
        }
    }

    /// checkMonitorLifecycle uses a delayed HAL substitute because real start would prompt for recording permission.
    static func checkMonitorLifecycle() async {
        let driver  = DelayedSpectrumCaptureDriver()
        let monitor = CoreAudioSpectrumMonitor(driver: driver)

        let first         = monitor.start(sourceBundleIdentifier: "test.player.first")
        var firstIterator = first.makeAsyncIterator()
        let firstSilence  = await firstIterator.next()
        check(firstSilence == .silence, "A fresh source must clear the last source's waveform")

        let oldRequest = driver.latest()

        let second         = monitor.start(sourceBundleIdentifier: "test.player.second")
        var secondIterator = second.makeAsyncIterator()
        let secondSilence  = await secondIterator.next()
        check(secondSilence == .silence, "Replacing a capture must start from measured silence")

        let newRequest = driver.latest()
        check(
            newRequest.source == "test.player.second",
            "Capture must target the current player's bundle"
        )

        newRequest.status(.capturing)
        await drainMainActor()
        check(monitor.status == .capturing, "A current capture update must reach observation")

        oldRequest.status(.permissionRequired)
        oldRequest.continuation.yield(AudioSpectrumFrame(bands: [1, 1, 1, 1, 1, 1]))
        await drainMainActor()
        check(monitor.status == .capturing, "Late status from a replaced tap must be ignored")

        let oldResult = await firstIterator.next()
        check(oldResult == nil, "Replacing capture must finish its previous stream")

        let measured = AudioSpectrumFrame(bands: [0, 0.2, 0.8, 0.3, 0, 0])
        newRequest.continuation.yield(measured)
        let currentResult = await secondIterator.next()
        check(currentResult == measured, "Current measured PCM must reach the subscriber unchanged")

        monitor.stop()
        newRequest.status(.capturing)
        newRequest.continuation.yield(measured)
        await drainMainActor()
        check(monitor.status == .stopped, "Late callbacks cannot revive a stopped capture")

        let stoppedResult = await secondIterator.next()
        check(stoppedResult == nil, "Stop must finish the stream synchronously")
        check(driver.stopCount >= 3, "Replacing and ending streams must release the capture driver")

        var shortLived       : CoreAudioSpectrumMonitor? = CoreAudioSpectrumMonitor(driver: driver)
        let orphaned          = shortLived?.start(sourceBundleIdentifier: nil)
        let stopsBeforeDeinit = driver.stopCount

        shortLived = nil
        check(
            driver.stopCount == stopsBeforeDeinit + 1,
            "Deinitialization must release an active capture"
        )
        _ = orphaned
    }

    /// checkStartupPermissionRequest verifies that a startup probe requests
    /// capture without a player, then releases all resources on completion or
    /// cancellation. It must not wait for audible PCM.
    static func checkStartupPermissionRequest() async {
        let driver    = DelayedSpectrumCaptureDriver()
        let requester = AudioCapturePermissionRequester(driver: driver)
        let task      = Task { await requester.requestAccess() }

        await drainMainActor()
        check(driver.requestCount == 1, "Startup must request system audio even with no player running")

        let request = driver.latest()
        check(request.source == nil, "Startup permission must not depend on music metadata")

        request.status(.capturing)
        let result = await task.value
        check(result == .capturing, "Successful setup must finish without waiting for audible samples")
        check(driver.stopCount == 1, "Permission-only capture must close immediately after setup")

        let denied = Task { await requester.requestAccess() }
        await drainMainActor()
        driver.latest().status(.permissionRequired)
        let denial = await denied.value
        check(
            denial == .permissionRequired,
            "Permission denial must remain distinguishable from silence"
        )
        check(driver.stopCount == 2, "A denied request must release its native resources")

        let cancelled = Task { await requester.requestAccess() }
        await drainMainActor()
        cancelled.cancel()
        let cancellation = await cancelled.value
        check(cancellation == .stopped, "Cancelled startup must finish without reviving capture")
        check(driver.stopCount >= 3, "Cancelled startup must stop the permission probe")
    }

    static func drainMainActor() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    static func signal(
        frequency: Double,
        amplitude: Float
    ) -> [Float] {
        (0..<2_048).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / 48_000)) }
    }

    static func measure(
        _ analyzer: AudioSpectrumAnalyzer,
        _ samples : [Float]
    ) -> AudioSpectrumFrame {
        samples.withUnsafeBufferPointer {
            analyzer.analyze(
                left      : $0,
                right     : nil,
                sampleRate: 48_000
            )
        }
    }

    static func check(
        _ condition: @autoclosure () -> Bool,
        _ message  : String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}

/// DelayedSpectrumCaptureDriver preserves callbacks after stop to exercise stale-delivery defenses.
private nonisolated final class DelayedSpectrumCaptureDriver: AudioSpectrumCaptureDriving, @unchecked Sendable {

    struct Request: Sendable {

        let source      : String?
        let continuation: AsyncStream<AudioSpectrumFrame>.Continuation
        let status      : @Sendable (AudioSpectrumStatus) -> Void
    }

    private let requests = OSAllocatedUnfairLock<[Request]>(initialState: [])
    private let stops    = OSAllocatedUnfairLock<Int>(initialState: 0)

    var stopCount   : Int { stops.withLock { $0 } }
    var requestCount: Int { requests.withLock { $0.count } }

    func start(
        sourceBundleIdentifier: String?,
        continuation          : AsyncStream<AudioSpectrumFrame>.Continuation,
        status                : @escaping @Sendable (AudioSpectrumStatus) -> Void
    ) {
        requests.withLock {
            $0.append(
                Request(
                    source      : sourceBundleIdentifier,
                    continuation: continuation,
                    status      : status
                )
            )
        }
    }

    func stop() {
        stops.withLock { $0 += 1 }
    }

    func latest() -> Request {
        requests.withLock { requests in
            guard let request = requests.last else { fatalError("Expected an actual start request") }

            return request
        }
    }
}

#endif
