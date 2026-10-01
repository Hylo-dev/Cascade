//
//  CoreAudioSpectrumCaptureSession.swift
//  Cascade
//

import AudioToolbox
import CoreAudio
import Dispatch
import Foundation
import os

/// CoreAudioSpectrumCaptureSession owns a private, unmuted output tap and a tap-only aggregate.
/// Its serial worker performs HAL calls and FFTs. The IO block only copies bounded Float32 PCM
/// into a preallocated exchange. No microphone, output routing, volume, or defaults are changed.
nonisolated final class CoreAudioSpectrumCaptureSession: @unchecked Sendable {

    private let queue       : DispatchQueue
    private let continuation: AsyncStream<AudioSpectrumFrame>.Continuation
    private let isCurrent   : @Sendable () -> Bool
    private let invalidate  : @Sendable () -> Void

    private let analyzer = AudioSpectrumAnalyzer()
    private let left     = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    private let right    = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    private let logger   = Logger(subsystem: "app.cascade", category: "AudioSpectrum")

    private var tapID       = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc     : AudioDeviceIOProcID?
    private var source     : (any DispatchSourceUserDataAdd)?
    private var exchange   : AudioSpectrumPCMExchange?
    private var sampleRate  = 48_000.0
    private var previous    = AudioSpectrumFrame.silence
    private var isRunning   = false
    private var listeners  : [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(
        queue       : DispatchQueue,
        continuation: AsyncStream<AudioSpectrumFrame>.Continuation,
        isCurrent   : @escaping @Sendable () -> Bool,
        invalidate  : @escaping @Sendable () -> Void
    ) {
        self.queue        = queue
        self.continuation = continuation
        self.isCurrent    = isCurrent
        self.invalidate   = invalidate

        left.initialize(repeating: 0, count: 2_048)
        right.initialize(repeating: 0, count: 2_048)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    /// start follows Apple's Core Audio tap capture API.
    /// https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
    func start(sourceBundleIdentifier: String?) throws {
        guard isCurrent() else { throw SpectrumCaptureFailure("Capture cancelled") }

        let description = makeTapDescription(sourceBundleIdentifier: sourceBundleIdentifier)
        description.name         = "Cascade Playback Spectrum"
        description.isPrivate    = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), operation: "Create output tap")
        guard isCurrent() else { throw SpectrumCaptureFailure("Capture cancelled") }

        var format = AudioStreamBasicDescription()
        try readValue(
            object  : tapID,
            selector: kAudioTapPropertyFormat,
            value   : &format
        )
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              format.mBitsPerChannel == 32,
              (1...2).contains(format.mChannelsPerFrame),
              format.mSampleRate.isFinite,
              (8_000...384_000).contains(format.mSampleRate)
        else {
            throw SpectrumCaptureFailure("Unsupported playback PCM format")
        }
        sampleRate = format.mSampleRate

        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey        : "Cascade Private Playback Analysis",
            kAudioAggregateDeviceUIDKey         : UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey   : true,
            kAudioAggregateDeviceIsStackedKey   : false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey     : [[
                kAudioSubTapUIDKey              : description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        try check(
            AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregateID),
            operation: "Create private tap aggregate"
        )
        guard isCurrent() else { throw SpectrumCaptureFailure("Capture cancelled") }

        let signal = DispatchSource.makeUserDataAddSource(queue: queue)
        let pcm    = AudioSpectrumPCMExchange(sampleRate: sampleRate, signal: signal)

        source   = signal
        exchange = pcm
        signal.setEventHandler { [weak self] in self?.analyzeLatest() }
        signal.resume()

        // Core Audio retains this block and its exchange until DestroyIOProcID completes.
        // The session stops/destroys the proc before releasing the event source or buffers;
        // callbacks already delivered to the worker find isRunning false after teardown.
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, input, _, _, _ in
                pcm.receive(input)
            },
            operation: "Create audio callback"
        )
        guard isCurrent() else { throw SpectrumCaptureFailure("Capture cancelled") }

        try check(AudioDeviceStart(aggregateID, ioProc), operation: "Start output capture")
        isRunning = true

        try observe(object: tapID, selector: kAudioTapPropertyFormat)
        try observe(
            object  : AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )
        try observe(
            object  : AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyServiceRestarted
        )
        if #unavailable(macOS 26), sourceBundleIdentifier != nil {
            try observe(
                object  : AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyProcessObjectList
            )
        }
    }

    /// stop releases the HAL callback before its storage and is safe after any failed setup step.
    func stop() {
        isRunning = false

        for (object, savedAddress, listener) in listeners {
            var address = savedAddress
            logCleanup(
                AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener),
                operation: "Remove capture listener"
            )
        }
        listeners.removeAll()

        if let ioProc, aggregateID != kAudioObjectUnknown {
            logCleanup(AudioDeviceStop(aggregateID, ioProc), operation: "Stop output capture")
            logCleanup(
                AudioDeviceDestroyIOProcID(aggregateID, ioProc),
                operation: "Destroy audio callback"
            )
        }
        ioProc = nil
        source?.cancel()
        source   = nil
        exchange = nil

        if aggregateID != kAudioObjectUnknown {
            logCleanup(
                AudioHardwareDestroyAggregateDevice(aggregateID),
                operation: "Destroy private aggregate"
            )
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            logCleanup(AudioHardwareDestroyProcessTap(tapID), operation: "Destroy output tap")
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func analyzeLatest() {
        guard isRunning,
              isCurrent(),
              let exchange,
              exchange.copyLatest(left: left, right: right)
        else { return }

        let frame = analyzer.analyze(
            left      : UnsafeBufferPointer(start: left, count: 2_048),
            right     : UnsafeBufferPointer(start: right, count: 2_048),
            sampleRate: sampleRate
        )
        guard frame != previous else { return }

        previous = frame
        continuation.yield(frame)
    }

    private func makeTapDescription(sourceBundleIdentifier: String?) -> CATapDescription {
        if let sourceBundleIdentifier, !sourceBundleIdentifier.isEmpty {
            if #available(macOS 26, *) {
                let description = CATapDescription(stereoMixdownOfProcesses: [])
                description.bundleIDs               = [sourceBundleIdentifier]
                description.isProcessRestoreEnabled = true
                return description
            }

            let processes = processObjects(bundleIdentifier: sourceBundleIdentifier)
            if !processes.isEmpty {
                return CATapDescription(stereoMixdownOfProcesses: processes)
            }
            logger.info("Player process unavailable; measuring the real system output mix")
        }

        return CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    }

    private func processObjects(bundleIdentifier: String) -> [AudioObjectID] {
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0,
              size <= 1_048_576
        else { return [] }

        var processes = [AudioObjectID](
            repeating: 0,
            count    : Int(size) / MemoryLayout<AudioObjectID>.size
        )
        let result = processes.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, base)
        }
        guard result == noErr else { return [] }

        return processes.filter { object in
            var property     = propertyAddress(kAudioProcessPropertyBundleID)
            var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var name: Unmanaged<CFString>?
            let result = withUnsafeMutablePointer(to: &name) {
                AudioObjectGetPropertyData(object, &property, 0, nil, &propertySize, $0)
            }
            guard result == noErr, let name else { return false }
            return (name.takeRetainedValue() as String) == bundleIdentifier
        }
    }

    private func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
    }

    /// observe rebuilds a tap only after a real HAL change; queued notifications from old sessions are inert.
    private func observe(
        object  : AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws {
        var address = propertyAddress(selector)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isRunning, self.isCurrent() else { return }

            self.isRunning = false
            self.continuation.yield(.silence)
            self.invalidate()
        }

        try check(
            AudioObjectAddPropertyListenerBlock(object, &address, queue, listener),
            operation: "Observe playback configuration"
        )
        listeners.append((object, address, listener))
    }

    private func readValue<Value: BitwiseCopyable>(
        object  : AudioObjectID,
        selector: AudioObjectPropertySelector,
        value   : inout Value
    ) throws {
        var address = propertyAddress(selector)
        var size    = UInt32(MemoryLayout<Value>.size)

        let result = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        try check(result, operation: "Read playback format")
    }

    private func check(
        _ result : OSStatus,
        operation: String
    ) throws {
        guard result == noErr else {
            throw SpectrumCaptureFailure(operation, result: result)
        }
    }

    private func logCleanup(
        _ result : OSStatus,
        operation: String
    ) {
        guard result != noErr else { return }

        logger.error("\(operation, privacy: .public): Core Audio \(result)")
    }
}
