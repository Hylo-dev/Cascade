//
//  AppAudioPipelineTests.swift
//  CascadeKit
//

@testable import CascadeAudioHost
import CascadeAudioRender
import CascadeContracts
import CoreAudio
import Foundation
import Testing

@Suite
struct AppAudioPipelineTests {

    private static let builtIn = "built-in"
    private static let usb     = "usb"

    private let chrome: AudioAppIdentity

    init() throws {
        chrome = try AudioAppIdentity(bundleID: "com.google.Chrome")
    }

    // MARK: - Fixtures

    private func intent(
        gain    : Double   = 0.25,
        muted   : Bool     = false,
        outputs : [String] = []
    ) throws -> AudioAppIntent {
        try AudioAppIntent(gain: gain, isMuted: muted, outputUIDs: outputs)
    }

    private func configuration(
        _ outputs : [String],
        streamTap : Bool
    ) -> AudioPipelineConfiguration {
        AudioPipelineConfiguration(
            processObjectIDs : [10, 11],
            outputUIDs       : outputs,
            streamTap        : streamTap
        )
    }

    private func pipeline(
        _ hal         : FakeAudioHostHAL,
        configuration : AudioPipelineConfiguration,
        intent        : AudioAppIntent
    ) -> AppAudioPipeline? {
        AppAudioPipeline(
            identity      : chrome,
            token         : 1,
            configuration : configuration,
            intent        : intent,
            hal           : hal
        )
    }

    /// Pushes `frames` frames of a constant stereo `value` through the kernel the HAL was
    /// given, the way the IOProc would, and returns the last frame of the output.
    private func lastOutputFrame(
        of hal : FakeAudioHostHAL,
        value  : Float,
        frames : Int = 2_000
    ) throws -> [Float] {
        let render = try #require(hal.startedRender)

        let input  = [Float](repeating: value, count: frames * 2)
        var output = [Float](repeating: -1, count: frames * 2)

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

        return Array(output.suffix(2))
    }

    /// Pushes `frames` frames of a constant stereo `value` through the kernel into an output list
    /// of `bufferCount` interleaved stereo buffers, the way an aggregate hands over one buffer
    /// per sub-device stream, and returns the samples of each buffer.
    private func renderedBuffers(
        of hal      : FakeAudioHostHAL,
        bufferCount : Int,
        value       : Float,
        frames      : Int = 8
    ) throws -> [[Float]] {
        let render = try #require(hal.startedRender)

        let sampleCount = frames * 2
        let input       = UnsafeMutablePointer<Float>.allocate(capacity: sampleCount)
        let outputs     = (0 ..< bufferCount).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: sampleCount) }
        let inputList   = AudioBufferList.allocate(maximumBuffers: 1)
        let outputList  = AudioBufferList.allocate(maximumBuffers: bufferCount)
        defer {
            input.deallocate()
            outputs.forEach { $0.deallocate() }
            free(inputList.unsafeMutablePointer)
            free(outputList.unsafeMutablePointer)
        }

        input.initialize(repeating: value, count: sampleCount)
        inputList[0] = AudioBuffer(
            mNumberChannels : 2,
            mDataByteSize   : UInt32(sampleCount * MemoryLayout<Float>.size),
            mData           : input
        )
        for (index, output) in outputs.enumerated() {
            output.initialize(repeating: -1, count: sampleCount)
            outputList[index] = AudioBuffer(
                mNumberChannels : 2,
                mDataByteSize   : UInt32(sampleCount * MemoryLayout<Float>.size),
                mData           : output
            )
        }

        CascadeAudioRenderProcess(
            render,
            inputList.unsafePointer,
            outputList.unsafeMutablePointer,
            UInt32(frames)
        )

        return outputs.map { Array(UnsafeBufferPointer(start: $0, count: sampleCount)) }
    }

    // MARK: - Build

    @Test
    func buildCreatesTapAggregateRenderThenStarts() throws {
        let hal    = FakeAudioHostHAL()
        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn], streamTap: true),
            intent        : try intent()
        )

        #expect(result != nil)
        #expect(
            hal.calls == [
                .createTap(processObjectIDs: [10, 11], streamOfOutput: Self.builtIn),
                .createAggregate(tapUUID: FakeAudioHostHAL.tapUUID, outputUIDs: [Self.builtIn]),
                .streamFormat(ofOutput: Self.builtIn),
                .start(aggregate: FakeAudioHostHAL.aggregateID),
            ]
        )
    }

    @Test
    func seededGainIsTheLatest() throws {
        let hal    = FakeAudioHostHAL()
        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn], streamTap: true),
            intent        : try intent(gain: 0.25)
        )
        #expect(result != nil)

        // The kernel was created settled on the intent's gain, so even the very first frame
        // is already at it: there is no ramp from unity that could leak a loud first slice.
        let frame = try lastOutputFrame(of: hal, value: 1, frames: 1)

        #expect(frame == [0.25, 0.25])
    }

    @Test
    func seededMuteIsSilentFromTheFirstFrame() throws {
        let hal    = FakeAudioHostHAL()
        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn], streamTap: true),
            intent        : try intent(gain: 0.8, muted: true)
        )
        #expect(result != nil)

        let frame = try lastOutputFrame(of: hal, value: 1, frames: 1)

        #expect(frame == [0, 0])
    }

    @Test
    func singleOutputUsesAStreamTap() throws {
        let hal = FakeAudioHostHAL()
        _ = pipeline(
            hal,
            configuration : configuration([Self.usb], streamTap: true),
            intent        : try intent()
        )

        #expect(hal.calls.first == .createTap(processObjectIDs: [10, 11], streamOfOutput: Self.usb))
    }

    @Test
    func severalOutputsUseAMixdownTapAndAStackedAggregate() throws {
        let hal = FakeAudioHostHAL()
        _ = pipeline(
            hal,
            configuration : configuration([Self.builtIn, Self.usb], streamTap: false),
            intent        : try intent()
        )

        #expect(hal.calls.first == .createTap(processObjectIDs: [10, 11], streamOfOutput: nil))
        #expect(
            hal.calls.contains(
                .createAggregate(tapUUID: FakeAudioHostHAL.tapUUID, outputUIDs: [Self.builtIn, Self.usb])
            )
        )
        #expect(hal.calls.contains(.streamFormat(ofOutput: Self.builtIn)))
    }

    // MARK: - Stacked outputs

    @Test
    func twoSingleStreamOutputsRenderIntoBuffersZeroAndOne() throws {
        let hal = FakeAudioHostHAL()
        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn, Self.usb], streamTap: false),
            intent        : try intent(gain: 0.5)
        )
        #expect(result != nil)

        let buffers = try renderedBuffers(of: hal, bufferCount: 2, value: 1)

        #expect(buffers[0].allSatisfy { $0 == 0.5 })
        #expect(buffers[1].allSatisfy { $0 == 0.5 })
    }

    @Test
    func theSecondDeviceBeginsAfterTheStreamsOfTheFirst() throws {
        let hal = FakeAudioHostHAL()
        hal.streamCounts[Self.builtIn] = 2
        hal.streamCounts[Self.usb]     = 1

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn, Self.usb], streamTap: false),
            intent        : try intent(gain: 0.5)
        )
        #expect(result != nil)

        // Buffers 0 and 1 are the built-in's two streams, buffer 2 is the USB device's one.
        let buffers = try renderedBuffers(of: hal, bufferCount: 3, value: 1)

        #expect(buffers[0].allSatisfy { $0 == 0.5 })
        #expect(buffers[1].allSatisfy { $0 == 0 })
        #expect(buffers[2].allSatisfy { $0 == 0.5 })
    }

    @Test
    func anOutputWithoutAStreamCountFailsTheBuildBeforeTouchingAnything() throws {
        let hal = FakeAudioHostHAL()
        hal.streamCounts[Self.builtIn] = 1
        hal.defaultStreamCount         = nil

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn, Self.usb], streamTap: false),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(!hal.calls.contains { if case .createTap = $0 { true } else { false } })
        #expect(!hal.calls.contains { if case .createAggregate = $0 { true } else { false } })
    }

    @Test
    func anOutputWithNoStreamsFailsTheBuild() throws {
        let hal = FakeAudioHostHAL()
        hal.streamCounts[Self.usb] = 0

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn, Self.usb], streamTap: false),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(hal.startedRender == nil)
    }

    @Test
    func anOtherOutputWithoutAFormatTearsDownAggregateThenTap() throws {
        let hal = FakeAudioHostHAL()
        hal.outputsWithoutFormat = [Self.usb]

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn, Self.usb], streamTap: false),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(
            hal.calls.suffix(2) == [
                .destroyAggregate(FakeAudioHostHAL.aggregateID),
                .destroyTap(FakeAudioHostHAL.tapID),
            ]
        )
        #expect(!hal.calls.contains(.start(aggregate: FakeAudioHostHAL.aggregateID)))
    }

    @Test
    func anOutputWithAnotherSampleTypeTearsDownAggregateThenTap() throws {
        let hal = FakeAudioHostHAL()
        hal.formatOverrides[Self.usb] = CascadeAudioRenderFormat(
            sampleRate  : 48_000,
            channels    : 2,
            interleaved : true,
            float64     : true,
            maxFrames   : 4096
        )

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn, Self.usb], streamTap: false),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(
            hal.calls.suffix(2) == [
                .destroyAggregate(FakeAudioHostHAL.aggregateID),
                .destroyTap(FakeAudioHostHAL.tapID),
            ]
        )
    }

    // MARK: - Failures

    @Test
    func failedTapBuildsNothingElse() throws {
        let hal = FakeAudioHostHAL()
        hal.tapShouldFail = true

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn], streamTap: true),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(hal.calls == [.createTap(processObjectIDs: [10, 11], streamOfOutput: Self.builtIn)])
    }

    @Test
    func failedAggregateTearsDownTheTap() throws {
        let hal = FakeAudioHostHAL()
        hal.aggregateShouldFail = true

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn], streamTap: true),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(
            hal.calls == [
                .createTap(processObjectIDs: [10, 11], streamOfOutput: Self.builtIn),
                .createAggregate(tapUUID: FakeAudioHostHAL.tapUUID, outputUIDs: [Self.builtIn]),
                .destroyTap(FakeAudioHostHAL.tapID),
            ]
        )
    }

    @Test
    func missingOutputFormatTearsDownAggregateThenTap() throws {
        let hal = FakeAudioHostHAL()
        hal.outputFormat = nil

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn], streamTap: true),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(
            hal.calls.suffix(2) == [
                .destroyAggregate(FakeAudioHostHAL.aggregateID),
                .destroyTap(FakeAudioHostHAL.tapID),
            ]
        )
    }

    @Test
    func invalidFormatFailsTheRenderContextAndTearsDown() throws {
        let hal = FakeAudioHostHAL()
        hal.tapFormat = CascadeAudioRenderFormat(
            sampleRate  : 48_000,
            channels    : 0,
            interleaved : true,
            float64     : false,
            maxFrames   : 4096
        )

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn], streamTap: true),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(
            hal.calls.suffix(2) == [
                .destroyAggregate(FakeAudioHostHAL.aggregateID),
                .destroyTap(FakeAudioHostHAL.tapID),
            ]
        )
    }

    @Test
    func failedStartTearsDownAggregateThenTapWithoutStopping() throws {
        let hal = FakeAudioHostHAL()
        hal.startShouldFail = true

        let result = pipeline(
            hal,
            configuration : configuration([Self.builtIn], streamTap: true),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(
            hal.calls.suffix(3) == [
                .start(aggregate: FakeAudioHostHAL.aggregateID),
                .destroyAggregate(FakeAudioHostHAL.aggregateID),
                .destroyTap(FakeAudioHostHAL.tapID),
            ]
        )
        #expect(!hal.calls.contains(.stop(aggregate: FakeAudioHostHAL.aggregateID)))
    }

    @Test
    func emptyOutputListFailsBeforeTouchingTheHAL() throws {
        let hal    = FakeAudioHostHAL()
        let result = pipeline(
            hal,
            configuration : configuration([], streamTap: false),
            intent        : try intent()
        )

        #expect(result == nil)
        #expect(hal.calls.isEmpty)
    }

    // MARK: - Running

    @Test
    func updateReachesTheKernel() throws {
        let hal    = FakeAudioHostHAL()
        let result = try #require(
            pipeline(
                hal,
                configuration : configuration([Self.builtIn], streamTap: true),
                intent        : try intent(gain: 0.25)
            )
        )

        result.update(try intent(gain: 0.5))
        let louder = try lastOutputFrame(of: hal, value: 1)
        #expect(louder == [0.5, 0.5])

        result.update(try intent(gain: 0.5, muted: true))
        let silent = try lastOutputFrame(of: hal, value: 1)
        #expect(silent == [0, 0])

        #expect(result.callbackCount == 2)
    }

    @Test
    func crossfadingOutEndsSilentAndInEndsAtFullShare() throws {
        let hal    = FakeAudioHostHAL()
        let result = try #require(
            pipeline(
                hal,
                configuration : configuration([Self.builtIn], streamTap: true),
                intent        : try intent(gain: 1)
            )
        )

        result.beginCrossfade(fadingIn: false, frames: 0)
        let faded = try lastOutputFrame(of: hal, value: 1, frames: 16)
        #expect(faded == [0, 0])

        result.beginCrossfade(fadingIn: true, frames: 0)
        let restored = try lastOutputFrame(of: hal, value: 1, frames: 16)
        #expect(restored == [1, 1])
    }

    // MARK: - Teardown

    @Test
    func teardownOrderIsStopAggregateTapRender() throws {
        let hal = FakeAudioHostHAL()
        let result = try #require(
            pipeline(
                hal,
                configuration : configuration([Self.builtIn], streamTap: true),
                intent        : try intent()
            )
        )

        var renderWasAliveWhenTheTapWasDestroyed = false
        hal.onDestroyTap = { renderWasAliveWhenTheTapWasDestroyed = result.hasRenderContext }

        result.teardown()

        #expect(
            hal.calls.suffix(3) == [
                .stop(aggregate: FakeAudioHostHAL.aggregateID),
                .destroyAggregate(FakeAudioHostHAL.aggregateID),
                .destroyTap(FakeAudioHostHAL.tapID),
            ]
        )
        #expect(renderWasAliveWhenTheTapWasDestroyed)
        #expect(!result.hasRenderContext)
    }

    @Test
    func teardownTwiceTearsDownOnce() throws {
        let hal = FakeAudioHostHAL()
        let result = try #require(
            pipeline(
                hal,
                configuration : configuration([Self.builtIn], streamTap: true),
                intent        : try intent()
            )
        )

        result.teardown()
        let callsAfterFirst = hal.calls

        result.teardown()

        #expect(hal.calls == callsAfterFirst)
        #expect(result.callbackCount == 0)
    }

    @Test
    func droppingARunningPipelineTearsItDown() throws {
        let hal = FakeAudioHostHAL()
        do {
            let result = pipeline(
                hal,
                configuration : configuration([Self.builtIn], streamTap: true),
                intent        : try intent()
            )
            #expect(result != nil)
        }

        #expect(hal.calls.contains(.stop(aggregate: FakeAudioHostHAL.aggregateID)))
        #expect(hal.calls.last == .destroyTap(FakeAudioHostHAL.tapID))
    }
}
