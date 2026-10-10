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
