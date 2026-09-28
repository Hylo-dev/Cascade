//
//  AudioSpectrumAnalyzer.swift
//  Cascade
//

import Accelerate
import Foundation

/// AudioSpectrumAnalyzer reduces a PCM window to six measured frequency bands on its owning worker.
nonisolated final class AudioSpectrumAnalyzer {
    static let windowSize = 2_048

    private let transform : FFTSetup?
    private let window    : UnsafeMutablePointer<Float>
    private let real      : UnsafeMutablePointer<Float>
    private let imaginary : UnsafeMutablePointer<Float>
    private let powers    : UnsafeMutablePointer<Float>
    private var smoothed  : [Float] = [0, 0, 0, 0, 0, 0]

    init() {
        transform = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))
        window = .allocate(capacity: Self.windowSize)
        real = .allocate(capacity: Self.windowSize)
        imaginary = .allocate(capacity: Self.windowSize)
        powers = .allocate(capacity: Self.windowSize / 2)
        window.initialize(repeating: 0, count: Self.windowSize)
        real.initialize(repeating: 0, count: Self.windowSize)
        imaginary.initialize(repeating: 0, count: Self.windowSize)
        powers.initialize(repeating: 0, count: Self.windowSize / 2)
        vDSP_hann_window(window, vDSP_Length(Self.windowSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let transform {
            vDSP_destroy_fftsetup(transform)
        }
        window.deallocate()
        real.deallocate()
        imaginary.deallocate()
        powers.deallocate()
    }

    /// analyze measures each stereo channel separately, then combines power so phase cannot cancel energy.
    func analyze(
        left       : UnsafeBufferPointer<Float>,
        right      : UnsafeBufferPointer<Float>?,
        sampleRate : Double
    ) -> AudioSpectrumFrame {
        guard let transform, sampleRate.isFinite, sampleRate > 0,
              left.count == Self.windowSize,
              right == nil || right?.count == Self.windowSize else {
            smoothed = AudioSpectrumFrame.silence.bands
            return .silence
        }

        powers.update(repeating: 0, count: Self.windowSize / 2)
        var peak: Float = 0
        let channelCount = right == nil ? 1 : 2

        for channel in 0..<channelCount {
            let samples = channel == 0 ? left : (right ?? left)
            for index in 0..<Self.windowSize {
                let sample = samples[index].isFinite ? samples[index] : 0
                peak = max(peak, abs(sample))
                real[index] = sample * window[index]
                imaginary[index] = 0
            }
            var split = DSPSplitComplex(realp: real, imagp: imaginary)
            vDSP_fft_zip(transform, &split, 1, 11, FFTDirection(FFT_FORWARD))
            for index in 1..<(Self.windowSize / 2) {
                powers[index] += real[index] * real[index] + imaginary[index] * imaginary[index]
            }
        }

        // A silent PCM window is evidence that playback is quiet. Clear the envelope
        // immediately; decaying bars after the last sample would invent activity.
        guard peak > 0.000_001 else {
            smoothed = AudioSpectrumFrame.silence.bands
            return .silence
        }

        let edges: [Double] = [40, 180, 500, 1_500, 4_000, 10_000, 24_000]
        let normalization = Float(4) / Float(Self.windowSize * Self.windowSize * channelCount)
        for band in 0..<6 {
            let first = max(1, Int(ceil(edges[band] * Double(Self.windowSize) / sampleRate)))
            let last = min(Self.windowSize / 2, Int(ceil(edges[band + 1] * Double(Self.windowSize) / sampleRate)))
            var energy: Float = 0
            if first < last {
                for index in first..<last {
                    energy += powers[index]
                }
            }
            let amplitude = sqrt(energy * normalization)
            let decibels = 20 * log10(max(amplitude, 0.000_001))
            let target = min(1, max(0, (decibels + 60) / 60))
            let blend: Float = target > smoothed[band] ? 0.72 : 0.3
            smoothed[band] += (target - smoothed[band]) * blend
        }
        return AudioSpectrumFrame(bands: smoothed)
    }
}
