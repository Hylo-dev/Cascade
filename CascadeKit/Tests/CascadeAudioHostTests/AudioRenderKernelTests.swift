//
//  AudioRenderKernelTests.swift
//  CascadeKit
//

import CascadeAudioRender
import CoreAudio
import Foundation
import Testing

// MARK: - Synthetic buffers

/// SyntheticBufferList is an `AudioBufferList` whose storage the test owns.
///
/// Each buffer is described by its channel count (1 for a planar channel, N for
/// an interleaved stream) so a test can lay out the aggregate the way Core Audio
/// does: a device's own streams first, the tap last.
private final class SyntheticBufferList {

    let pointer        : UnsafeMutableAudioBufferListPointer
    let bytesPerSample : Int
    let frameCapacity  : Int
    private let storage: [UnsafeMutableRawPointer]
    private let channels: [Int]

    init(
        buffers  : [Int],
        frames   : Int,
        float64  : Bool,
        poison   : UInt8 = 0
    ) {
        bytesPerSample = float64 ? 8 : 4
        frameCapacity  = frames
        channels       = buffers
        // allocate traps on zero buffers, so an empty list is one slot whose count is then zeroed.
        pointer        = AudioBufferList.allocate(maximumBuffers: max(buffers.count, 1))
        pointer.count  = buffers.count
        var allocated  = [UnsafeMutableRawPointer]()
        for (index, channelCount) in buffers.enumerated() {
            let byteCount = frames * channelCount * bytesPerSample
            let memory    = UnsafeMutableRawPointer.allocate(byteCount: max(byteCount, 8), alignment: 16)
            memory.initializeMemory(as: UInt8.self, repeating: poison, count: max(byteCount, 8))
            allocated.append(memory)
            pointer[index] = AudioBuffer(
                mNumberChannels : UInt32(channelCount),
                mDataByteSize   : UInt32(byteCount),
                mData           : memory
            )
        }
        storage = allocated
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(pointer.unsafeMutablePointer)
    }

    /// Writes interleaved `values` (frame-major) into one buffer.
    func write(buffer: Int, _ values: [Double]) {
        let base = storage[buffer]
        for (index, value) in values.enumerated() {
            if bytesPerSample == 8 {
                base.storeBytes(of: value, toByteOffset: index * 8, as: Double.self)
            } else {
                base.storeBytes(of: Float(value), toByteOffset: index * 4, as: Float.self)
            }
        }
    }

    func read(buffer: Int) -> [Double] {
        let count = Int(pointer[buffer].mDataByteSize) / bytesPerSample
        let base  = storage[buffer]
        return (0 ..< count).map { index in
            bytesPerSample == 8
                ? base.load(fromByteOffset: index * 8, as: Double.self)
                : Double(base.load(fromByteOffset: index * 4, as: Float.self))
        }
    }

    func bitPatterns(buffer: Int) -> [UInt64] {
        let count = Int(pointer[buffer].mDataByteSize) / bytesPerSample
        let base  = storage[buffer]
        return (0 ..< count).map { index in
            bytesPerSample == 8
                ? base.load(fromByteOffset: index * 8, as: UInt64.self)
                : UInt64(base.load(fromByteOffset: index * 4, as: UInt32.self))
        }
    }

    func bytes(buffer: Int) -> [UInt8] {
        let count = Int(pointer[buffer].mDataByteSize)
        return Array(UnsafeRawBufferPointer(start: storage[buffer], count: count))
    }
}

private struct SideLayout {

    var channels    : Int
    var interleaved : Bool = true
    var float64     : Bool = false

    static func stereo(float64: Bool = false, interleaved: Bool = true) -> SideLayout {
        SideLayout(channels: 2, interleaved: interleaved, float64: float64)
    }

    func format(rate: Double, maxFrames: Int) -> CascadeAudioRenderFormat {
        CascadeAudioRenderFormat(
            sampleRate  : rate,
            channels    : UInt32(channels),
            interleaved : interleaved,
            float64     : float64,
            maxFrames   : UInt32(maxFrames)
        )
    }

    /// The buffer layout of one side, `deviceFirst` extra interleaved stereo streams ahead of it.
    var bufferShape: [Int] {
        interleaved ? [channels] : Array(repeating: 1, count: channels)
    }
}

private func makeRenderer(
    rate   : Double     = 48_000,
    input  : SideLayout = .stereo(),
    output : SideLayout = .stereo(),
    gain   : Double     = 1,
    muted  : Bool       = false
) throws -> OpaquePointer {
    try #require(
        CascadeAudioRenderCreate(
            input.format(rate: rate, maxFrames: 4096),
            output.format(rate: rate, maxFrames: 4096),
            gain,
            muted
        )
    )
}

private func process(
    _ renderer : OpaquePointer,
    _ input    : SyntheticBufferList?,
    _ output   : SyntheticBufferList,
    frames     : Int
) {
    CascadeAudioRenderProcess(
        renderer,
        input?.pointer.unsafePointer,
        output.pointer.unsafeMutablePointer,
        UInt32(frames)
    )
}

/// Planar buffers hold one channel each; this splits frame-major interleaved values apart.
private func fill(_ list: SyntheticBufferList, layout: SideLayout, firstBuffer: Int = 0, interleavedValues values: [Double]) {
    if layout.interleaved {
        list.write(buffer: firstBuffer, values)
        return
    }
    for channel in 0 ..< layout.channels {
        let column = stride(from: channel, to: values.count, by: layout.channels).map { values[$0] }
        list.write(buffer: firstBuffer + channel, column)
    }
}

private func gather(_ list: SyntheticBufferList, layout: SideLayout, firstBuffer: Int = 0, frames: Int) -> [Double] {
    if layout.interleaved {
        return Array(list.read(buffer: firstBuffer).prefix(frames * layout.channels))
    }
    var result = [Double]()
    let columns = (0 ..< layout.channels).map { list.read(buffer: firstBuffer + $0) }
    for frame in 0 ..< frames {
        for column in columns {
            result.append(column[frame])
        }
    }
    return result
}

private func signal(frames: Int, channels: Int, amplitude: Double = 0.8) -> [Double] {
    (0 ..< frames * channels).map { index in
        amplitude * sin(Double(index) * 0.137 + Double(index % channels))
    }
}

private func rampLength(rate: Double) -> Int {
    Int((rate * 0.005).rounded())
}

// MARK: - Suite

@Suite
struct AudioRenderKernelTests {

    @Test(arguments: [false, true])
    func unityIsBitExactWhenSettled(float64: Bool) throws {
        let layout   = SideLayout.stereo(float64: float64)
        let renderer = try makeRenderer(input: layout, output: layout, gain: 1)
        defer { CascadeAudioRenderDestroy(renderer) }

        var values = signal(frames: 256, channels: 2, amplitude: 1)
        values.append(contentsOf: [-0.0, 0.0, 3.5, -2.0, 1e-30, Double(Float.leastNonzeroMagnitude), 1.0, -1.0])
        let frames = values.count / 2

        let input  = SyntheticBufferList(buffers: [2], frames: frames, float64: float64)
        let output = SyntheticBufferList(buffers: [2], frames: frames, float64: float64, poison: 0xAB)
        input.write(buffer: 0, values)

        process(renderer, input, output, frames: frames)

        #expect(output.bitPatterns(buffer: 0) == input.bitPatterns(buffer: 0))
    }

    @Test(arguments: [44_100.0, 48_000, 96_000, 192_000], [false, true])
    func quarterGainMatchesScalarWithinOneULP(rate: Double, float64: Bool) throws {
        let layout   = SideLayout.stereo(float64: float64)
        let renderer = try makeRenderer(rate: rate, input: layout, output: layout, gain: 0.25)
        defer { CascadeAudioRenderDestroy(renderer) }

        let frames = 1_000
        let values = signal(frames: frames, channels: 2)
        let input  = SyntheticBufferList(buffers: [2], frames: frames, float64: float64)
        let output = SyntheticBufferList(buffers: [2], frames: frames, float64: float64)
        input.write(buffer: 0, values)

        process(renderer, input, output, frames: frames)

        let stored = input.read(buffer: 0)
        for (index, actual) in output.read(buffer: 0).enumerated() {
            let expected = stored[index] * 0.25
            let ulp      = float64 ? expected.ulp : Double(Float(expected).ulp)
            #expect(abs(actual - expected) <= ulp)
        }
    }

    @Test(arguments: [44_100.0, 48_000, 96_000, 192_000])
    func rampTakesFiveMilliseconds(rate: Double) throws {
        let layout   = SideLayout.stereo(float64: true)
        let renderer = try makeRenderer(rate: rate, input: layout, output: layout, gain: 1)
        defer { CascadeAudioRenderDestroy(renderer) }

        let length = rampLength(rate: rate)
        let frames = length + 300
        let input  = SyntheticBufferList(buffers: [2], frames: frames, float64: true)
        input.write(buffer: 0, Array(repeating: 1, count: frames * 2))
        let output = SyntheticBufferList(buffers: [2], frames: frames, float64: true)

        CascadeAudioRenderSetCommand(renderer, 0.25, false)

        // Two slices, so the ramp must survive a callback boundary.
        let firstSlice = 100
        let firstInput  = SyntheticBufferList(buffers: [2], frames: firstSlice, float64: true)
        firstInput.write(buffer: 0, Array(repeating: 1, count: firstSlice * 2))
        let firstOutput = SyntheticBufferList(buffers: [2], frames: firstSlice, float64: true)
        let restInput   = SyntheticBufferList(buffers: [2], frames: frames - firstSlice, float64: true)
        restInput.write(buffer: 0, Array(repeating: 1, count: (frames - firstSlice) * 2))
        let restOutput  = SyntheticBufferList(buffers: [2], frames: frames - firstSlice, float64: true)

        process(renderer, firstInput, firstOutput, frames: firstSlice)
        process(renderer, restInput, restOutput, frames: frames - firstSlice)
        _ = (input, output)

        let rendered = firstOutput.read(buffer: 0) + restOutput.read(buffer: 0)
        for frame in 0 ..< frames {
            let expected = frame < length ? 1 + (0.25 - 1) * Double(frame + 1) / Double(length) : 0.25
            #expect(abs(rendered[frame * 2]     - expected) < 1e-12)
            #expect(rendered[frame * 2] == rendered[frame * 2 + 1])
        }
        #expect(rendered[(length - 1) * 2] == 0.25)
        #expect(rendered[(length - 2) * 2] != 0.25)
    }

    @Test
    func muteWritesExactZerosAfterRamp() throws {
        let layout   = SideLayout.stereo(float64: true)
        let renderer = try makeRenderer(input: layout, output: layout, gain: 0.5)
        defer { CascadeAudioRenderDestroy(renderer) }

        let length = rampLength(rate: 48_000)
        let frames = length + 100
        let input  = SyntheticBufferList(buffers: [2], frames: frames, float64: true)
        input.write(buffer: 0, Array(repeating: -0.7, count: frames * 2))
        let output = SyntheticBufferList(buffers: [2], frames: frames, float64: true)

        CascadeAudioRenderSetCommand(renderer, 0.5, true)
        process(renderer, input, output, frames: frames)

        let bits = output.bitPatterns(buffer: 0)
        let rendered = output.read(buffer: 0)
        #expect(rendered[(length - 2) * 2] < 0)
        for index in ((length - 1) * 2) ..< bits.count {
            #expect(bits[index] == 0)
        }

        // Unmuting ramps back up to the stored gain instead of jumping.
        CascadeAudioRenderSetCommand(renderer, 0.5, false)
        process(renderer, input, output, frames: frames)
        let restored = output.read(buffer: 0)
        for frame in 0 ..< frames {
            let expected = frame < length ? -0.7 * 0.5 * Double(frame + 1) / Double(length) : -0.35
            #expect(abs(restored[frame * 2] - expected) < 1e-12)
        }
    }

    @Test
    func rightOnlySignalKeepsBothChannels() throws {
        let layout   = SideLayout.stereo(float64: true)
        let renderer = try makeRenderer(input: layout, output: layout, gain: 0.5)
        defer { CascadeAudioRenderDestroy(renderer) }

        let frames = 64
        let values = (0 ..< frames * 2).map { $0 % 2 == 0 ? 0.0 : 0.5 }
        let input  = SyntheticBufferList(buffers: [2], frames: frames, float64: true)
        input.write(buffer: 0, values)
        let output = SyntheticBufferList(buffers: [2], frames: frames, float64: true)

        process(renderer, input, output, frames: frames)

        let rendered = output.read(buffer: 0)
        for frame in 0 ..< frames {
            #expect(rendered[frame * 2]     == 0)
            #expect(rendered[frame * 2 + 1] == 0.25)
        }
    }

    @Test
    func nearSilenceIsNotGated() throws {
        let renderer = try makeRenderer(gain: 0.5)
        defer { CascadeAudioRenderDestroy(renderer) }

        let frames = 32
        let input  = SyntheticBufferList(buffers: [2], frames: frames, float64: false)
        input.write(buffer: 0, Array(repeating: 1e-7, count: frames * 2))
        let output = SyntheticBufferList(buffers: [2], frames: frames, float64: false)

        process(renderer, input, output, frames: frames)

        let expected = Double(Float(Double(Float(1e-7)) * 0.5))
        for sample in output.read(buffer: 0) {
            #expect(sample == expected)
        }
    }

    @Test
    func fullScalePeaksAreNotLimited() throws {
        let layout   = SideLayout.stereo(float64: true)
        let unity    = try makeRenderer(input: layout, output: layout, gain: 1)
        let half     = try makeRenderer(input: layout, output: layout, gain: 0.5)
        defer {
            CascadeAudioRenderDestroy(unity)
            CascadeAudioRenderDestroy(half)
        }

        let peaks  = [1.0, -1.0, 1.0, -1.0, 2.5, -3.0, 1.0, 1.0]
        let frames = peaks.count / 2
        let input  = SyntheticBufferList(buffers: [2], frames: frames, float64: true)
        input.write(buffer: 0, peaks)
        let unityOutput = SyntheticBufferList(buffers: [2], frames: frames, float64: true)
        let halfOutput  = SyntheticBufferList(buffers: [2], frames: frames, float64: true)

        process(unity, input, unityOutput, frames: frames)
        process(half,  input, halfOutput,  frames: frames)

        #expect(unityOutput.read(buffer: 0) == peaks)
        #expect(halfOutput.read(buffer: 0)  == peaks.map { $0 * 0.5 })
    }

    @Test
    func monoToStereoAndStereoToMono() throws {
        let frames = 64

        let monoToStereo = try makeRenderer(input: SideLayout(channels: 1), output: .stereo(), gain: 1)
        defer { CascadeAudioRenderDestroy(monoToStereo) }
        let monoValues = signal(frames: frames, channels: 1)
        let monoInput  = SyntheticBufferList(buffers: [1], frames: frames, float64: false)
        monoInput.write(buffer: 0, monoValues)
        let stereoOutput = SyntheticBufferList(buffers: [2], frames: frames, float64: false)
        process(monoToStereo, monoInput, stereoOutput, frames: frames)
        let duplicated = stereoOutput.read(buffer: 0)
        let narrowed   = monoInput.read(buffer: 0)
        for frame in 0 ..< frames {
            #expect(duplicated[frame * 2]     == narrowed[frame])
            #expect(duplicated[frame * 2 + 1] == narrowed[frame])
        }

        let stereoToMono = try makeRenderer(input: .stereo(float64: true), output: SideLayout(channels: 1, float64: true), gain: 1)
        defer { CascadeAudioRenderDestroy(stereoToMono) }
        let stereoValues = signal(frames: frames, channels: 2)
        let stereoInput  = SyntheticBufferList(buffers: [2], frames: frames, float64: true)
        stereoInput.write(buffer: 0, stereoValues)
        let monoOutput = SyntheticBufferList(buffers: [1], frames: frames, float64: true)
        process(stereoToMono, stereoInput, monoOutput, frames: frames)
        let averaged = monoOutput.read(buffer: 0)
        for frame in 0 ..< frames {
            let expected = (stereoValues[frame * 2] + stereoValues[frame * 2 + 1]) / 2
            #expect(abs(averaged[frame] - expected) < 1e-15)
        }
    }

    @Test
    func channelsMapByIndexAndExtraOutputsAreZero() throws {
        let frames = 16
        let values = signal(frames: frames, channels: 2)

        let twoToFour = try makeRenderer(input: .stereo(float64: true), output: SideLayout(channels: 4, float64: true), gain: 1)
        defer { CascadeAudioRenderDestroy(twoToFour) }
        let input  = SyntheticBufferList(buffers: [2], frames: frames, float64: true)
        input.write(buffer: 0, values)
        let output = SyntheticBufferList(buffers: [4], frames: frames, float64: true, poison: 0xAB)
        process(twoToFour, input, output, frames: frames)
        let widened = output.read(buffer: 0)
        for frame in 0 ..< frames {
            #expect(widened[frame * 4]     == values[frame * 2])
            #expect(widened[frame * 4 + 1] == values[frame * 2 + 1])
            #expect(widened[frame * 4 + 2].bitPattern == 0)
            #expect(widened[frame * 4 + 3].bitPattern == 0)
        }

        let fourToTwo = try makeRenderer(input: SideLayout(channels: 4, float64: true), output: .stereo(float64: true), gain: 1)
        defer { CascadeAudioRenderDestroy(fourToTwo) }
        let wideValues = signal(frames: frames, channels: 4)
        let wideInput  = SyntheticBufferList(buffers: [4], frames: frames, float64: true)
        wideInput.write(buffer: 0, wideValues)
        let narrowOutput = SyntheticBufferList(buffers: [2], frames: frames, float64: true)
        process(fourToTwo, wideInput, narrowOutput, frames: frames)
        let narrowed = narrowOutput.read(buffer: 0)
        for frame in 0 ..< frames {
            #expect(narrowed[frame * 2]     == wideValues[frame * 4])
            #expect(narrowed[frame * 2 + 1] == wideValues[frame * 4 + 1])
        }
    }

    @Test(arguments: [true, false], [true, false])
    func planarAndInterleaved(inputInterleaved: Bool, outputInterleaved: Bool) throws {
        let inputLayout  = SideLayout.stereo(float64: true, interleaved: inputInterleaved)
        let outputLayout = SideLayout.stereo(float64: true, interleaved: outputInterleaved)
        let renderer     = try makeRenderer(input: inputLayout, output: outputLayout, gain: 0.5)
        defer { CascadeAudioRenderDestroy(renderer) }

        let frames = 100
        let values = signal(frames: frames, channels: 2)
        let input  = SyntheticBufferList(buffers: inputLayout.bufferShape, frames: frames, float64: true)
        fill(input, layout: inputLayout, interleavedValues: values)
        let output = SyntheticBufferList(buffers: outputLayout.bufferShape, frames: frames, float64: true)

        process(renderer, input, output, frames: frames)

        let rendered = gather(output, layout: outputLayout, frames: frames)
        #expect(rendered == values.map { $0 * 0.5 })
    }

    @Test(arguments: [true, false])
    func tapIsTheLastInputBuffer(interleaved: Bool) throws {
        let layout   = SideLayout.stereo(float64: true, interleaved: interleaved)
        let renderer = try makeRenderer(input: layout, output: layout, gain: 1)
        defer { CascadeAudioRenderDestroy(renderer) }

        let frames    = 32
        let deviceIn  = Array(repeating: 0.9, count: frames * 2)
        let tapValues = signal(frames: frames, channels: 2, amplitude: 0.1)

        // The aggregate lists the device's own input streams first, the tap last.
        let input = SyntheticBufferList(buffers: layout.bufferShape + layout.bufferShape, frames: frames, float64: true)
        fill(input, layout: layout, firstBuffer: 0, interleavedValues: deviceIn)
        fill(input, layout: layout, firstBuffer: layout.bufferShape.count, interleavedValues: tapValues)
        let output = SyntheticBufferList(buffers: layout.bufferShape, frames: frames, float64: true)

        process(renderer, input, output, frames: frames)

        #expect(gather(output, layout: layout, frames: frames) == tapValues)
    }

    @Test
    func nanInputIsCountedNotPropagated() throws {
        let layout   = SideLayout.stereo(float64: true)
        let renderer = try makeRenderer(input: layout, output: layout, gain: 0.5)
        defer { CascadeAudioRenderDestroy(renderer) }

        var values = Array(repeating: 0.4, count: 16)
        values[1]  = .nan
        values[6]  = .infinity
        values[9]  = -.infinity
        let input  = SyntheticBufferList(buffers: [2], frames: 8, float64: true)
        input.write(buffer: 0, values)
        let output = SyntheticBufferList(buffers: [2], frames: 8, float64: true)

        process(renderer, input, output, frames: 8)

        let rendered = output.read(buffer: 0)
        for (index, sample) in rendered.enumerated() {
            let isInvalid = [1, 6, 9].contains(index)
            #expect(sample == (isInvalid ? 0 : 0.2))
        }
        #expect(CascadeAudioRenderInvalidSampleCount(renderer) == 3)
    }

    @Test(arguments: [0.0, 0.5])
    func crossfadeIsEqualPower(gain: Double) throws {
        let layout  = SideLayout(channels: 1, float64: true)
        let rising  = try makeRenderer(input: layout, output: layout, gain: gain == 0 ? 1 : gain)
        let falling = try makeRenderer(input: layout, output: layout, gain: gain == 0 ? 1 : gain)
        defer {
            CascadeAudioRenderDestroy(rising)
            CascadeAudioRenderDestroy(falling)
        }
        let effectiveGain = gain == 0 ? 1.0 : gain

        let fadeFrames = 480
        let frames     = 1_000
        CascadeAudioRenderSetCrossfade(rising,  0, 1, UInt32(fadeFrames))
        CascadeAudioRenderSetCrossfade(falling, 1, 0, UInt32(fadeFrames))

        let input = SyntheticBufferList(buffers: [1], frames: frames, float64: true)
        input.write(buffer: 0, Array(repeating: 1, count: frames))
        let risingOutput  = SyntheticBufferList(buffers: [1], frames: frames, float64: true)
        let fallingOutput = SyntheticBufferList(buffers: [1], frames: frames, float64: true)

        process(rising,  input, risingOutput,  frames: frames)
        process(falling, input, fallingOutput, frames: frames)

        let up   = risingOutput.read(buffer: 0)
        let down = fallingOutput.read(buffer: 0)
        for frame in 0 ..< frames {
            #expect(abs(up[frame] * up[frame] + down[frame] * down[frame] - effectiveGain * effectiveGain) < 1e-9)
        }
        #expect(abs(up[0] - effectiveGain * sin(.pi / 2 / Double(fadeFrames))) < 1e-12)
        #expect(up[fadeFrames - 1]   == effectiveGain)
        #expect(down[fadeFrames - 1] == 0)
        #expect(up[frames - 1]       == effectiveGain)
        #expect(down[frames - 1]     == 0)
    }

    @Test
    func callbackCountIncrements() throws {
        let renderer = try makeRenderer()
        defer { CascadeAudioRenderDestroy(renderer) }
        let input  = SyntheticBufferList(buffers: [2], frames: 8, float64: false)
        let output = SyntheticBufferList(buffers: [2], frames: 8, float64: false)

        #expect(CascadeAudioRenderCallbackCount(renderer) == 0)
        process(renderer, input, output, frames: 8)
        process(renderer, input, output, frames: 8)
        process(renderer, nil, output, frames: 8)
        #expect(CascadeAudioRenderCallbackCount(renderer) == 3)
    }

    @Test
    func everyOutputByteIsWritten() throws {
        let renderer = try makeRenderer(gain: 1)
        defer { CascadeAudioRenderDestroy(renderer) }

        // Output asks for 8 frames of a 16-frame buffer and has a second, unused stream.
        let input  = SyntheticBufferList(buffers: [2], frames: 8, float64: false)
        input.write(buffer: 0, Array(repeating: 0.5, count: 16))
        let output = SyntheticBufferList(buffers: [2, 2], frames: 16, float64: false, poison: 0xAB)

        process(renderer, input, output, frames: 8)

        let firstBytes = output.bytes(buffer: 0)
        #expect(firstBytes.suffix(firstBytes.count - 8 * 2 * 4).allSatisfy { $0 == 0 })
        #expect(output.bytes(buffer: 1).allSatisfy { $0 == 0 })

        // No input at all still produces defined silence.
        process(renderer, nil, output, frames: 8)
        #expect(output.bytes(buffer: 0).allSatisfy { $0 == 0 })
    }

    @Test
    func shortBuffersAreNeverOverrun() throws {
        let renderer = try makeRenderer(gain: 1)
        defer { CascadeAudioRenderDestroy(renderer) }

        let input  = SyntheticBufferList(buffers: [2], frames: 5, float64: false)
        input.write(buffer: 0, Array(repeating: 0.5, count: 10))
        let output = SyntheticBufferList(buffers: [2], frames: 10, float64: false)

        process(renderer, input, output, frames: 4096)

        let rendered = output.read(buffer: 0)
        #expect(rendered.prefix(10).allSatisfy { $0 == 0.5 })
        #expect(rendered.suffix(10).allSatisfy { $0 == 0 })
    }

    @Test
    func invalidFormatsAreRejected() {
        let good = SideLayout.stereo().format(rate: 48_000, maxFrames: 512)
        var badRate = good
        badRate.sampleRate = 0
        var noChannels = good
        noChannels.channels = 0
        var tooWide = good
        tooWide.channels = 33

        #expect(CascadeAudioRenderCreate(badRate, good, 1, false) == nil)
        #expect(CascadeAudioRenderCreate(good, noChannels, 1, false) == nil)
        #expect(CascadeAudioRenderCreate(tooWide, good, 1, false) == nil)
    }

    // MARK: - IOProc trampoline

    @Test
    func theIOProcTrampolineRendersThroughTheKernelAndReturnsNoErr() throws {
        let renderer = try makeRenderer(gain: 0.5)
        defer { CascadeAudioRenderDestroy(renderer) }

        // Compiles only if the trampoline has exactly the signature Core Audio registers.
        let registered: AudioDeviceIOProc = CascadeAudioRenderIOProc
        _ = registered

        // The input is longer than the output: the frame count comes from the output buffer.
        let input  = SyntheticBufferList(buffers: [2], frames: 100, float64: false)
        input.write(buffer: 0, Array(repeating: 0.8, count: 200))
        let output = SyntheticBufferList(buffers: [2], frames: 64, float64: false, poison: 0xFF)

        var timestamp = AudioTimeStamp()
        let status    = CascadeAudioRenderIOProc(
            42,
            &timestamp,
            input.pointer.unsafePointer,
            &timestamp,
            output.pointer.unsafeMutablePointer,
            &timestamp,
            UnsafeMutableRawPointer(renderer)
        )

        #expect(status == noErr)
        #expect(CascadeAudioRenderCallbackCount(renderer) == 1)

        let rendered = output.read(buffer: 0)
        #expect(rendered.count == 128)
        #expect(rendered.allSatisfy { abs($0 - 0.4) < 1e-6 })
    }

    @Test
    func theIOProcTrampolineSurvivesAnEmptyOutputList() throws {
        let renderer = try makeRenderer(gain: 1)
        defer { CascadeAudioRenderDestroy(renderer) }

        let input  = SyntheticBufferList(buffers: [2], frames: 32, float64: false)
        let output = SyntheticBufferList(buffers: [], frames: 0, float64: false)

        var timestamp = AudioTimeStamp()
        let status    = CascadeAudioRenderIOProc(
            42,
            &timestamp,
            input.pointer.unsafePointer,
            &timestamp,
            output.pointer.unsafeMutablePointer,
            &timestamp,
            UnsafeMutableRawPointer(renderer)
        )

        #expect(status == noErr)
        #expect(CascadeAudioRenderCallbackCount(renderer) == 1)
    }
}
