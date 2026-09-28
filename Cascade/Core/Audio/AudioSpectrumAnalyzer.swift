//
//  AudioSpectrumAnalyzer.swift
//  Cascade
//

import Accelerate
import Foundation

/// AudioSpectrumAnalyzer reduces a PCM window to six measured frequency bands on its owning worker.
///
/// Every per-sample step is a vDSP call: windowing, a real FFT, magnitudes and band sums. As
/// Swift loops they cost ~1.4 % of a core in a debug build (generic range iteration is not
/// specialized there) and forced the same work through the optimizer in release; vDSP is
/// already optimized either way. The real FFT (`fft_zrip`) is half the complex transform's
/// work and scales its output by 2, which the normalization absorbs, so the bands match the
/// former complex FFT.
nonisolated final class AudioSpectrumAnalyzer {

    static let windowSize = 2_048

    private static let half  = windowSize / 2
    private static let log2n = vDSP_Length(11)
    private static let edges: [Double] = [40, 180, 500, 1_500, 4_000, 10_000, 24_000]

    private let transform : FFTSetup?
    private let window    : UnsafeMutablePointer<Float>
    private let windowed  : UnsafeMutablePointer<Float>
    private let real      : UnsafeMutablePointer<Float>
    private let imaginary : UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>
    private let powers    : UnsafeMutablePointer<Float>

    private var smoothed: [Float] = [0, 0, 0, 0, 0, 0]
    private var bins    : [(first: Int, count: Int)] = []
    private var binsRate = 0.0

    init() {
        transform  = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))
        window     = .allocate(capacity: Self.windowSize)
        windowed   = .allocate(capacity: Self.windowSize)
        real       = .allocate(capacity: Self.half)
        imaginary  = .allocate(capacity: Self.half)
        magnitudes = .allocate(capacity: Self.half)
        powers     = .allocate(capacity: Self.half)

        windowed.initialize(repeating: 0, count: Self.windowSize)
        real.initialize(repeating: 0, count: Self.half)
        imaginary.initialize(repeating: 0, count: Self.half)
        magnitudes.initialize(repeating: 0, count: Self.half)
        powers.initialize(repeating: 0, count: Self.half)

        vDSP_hann_window(window, vDSP_Length(Self.windowSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let transform {
            vDSP_destroy_fftsetup(transform)
        }

        window.deallocate()
        windowed.deallocate()
        real.deallocate()
        imaginary.deallocate()
        magnitudes.deallocate()
        powers.deallocate()
    }

    /// analyze measures each stereo channel separately, then combines power so phase cannot cancel energy.
    func analyze(
        left      : UnsafeBufferPointer<Float>,
        right     : UnsafeBufferPointer<Float>?,
        sampleRate: Double
    ) -> AudioSpectrumFrame {
        guard let transform,
              sampleRate.isFinite,
              sampleRate > 0,
              let leftBase = left.baseAddress,
              left.count == Self.windowSize,
              right == nil || right?.count == Self.windowSize
        else {
            smoothed = AudioSpectrumFrame.silence.bands
            return .silence
        }

        let length = vDSP_Length(Self.windowSize)
        let half   = vDSP_Length(Self.half)
        vDSP_vclr(powers, 1, half)

        var peak: Float = 0
        let rightBase    = right?.baseAddress
        let channelCount = rightBase == nil ? 1 : 2
        for channel in 0..<channelCount {
            let samples = channel == 0 ? leftBase : rightBase ?? leftBase

            // A non-finite sample makes the sum non-finite; only then is the window
            // cleaned sample by sample, with the former loop's semantics.
            var sum: Float = 0
            vDSP_sve(samples, 1, &sum, length)
            var source = samples
            if !sum.isFinite {
                for index in 0..<Self.windowSize {
                    windowed[index] = samples[index].isFinite ? samples[index] : 0
                }
                source = UnsafePointer(windowed)
            }

            var channelPeak: Float = 0
            vDSP_maxmgv(source, 1, &channelPeak, length)
            peak = max(peak, channelPeak)

            vDSP_vmul(source, 1, window, 1, windowed, 1, length)
            var split = DSPSplitComplex(realp: real, imagp: imaginary)
            windowed.withMemoryRebound(to: DSPComplex.self, capacity: Self.half) {
                vDSP_ctoz($0, 2, &split, 1, half)
            }
            vDSP_fft_zrip(transform, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
            vDSP_zvmags(&split, 1, magnitudes, 1, half)
            vDSP_vadd(powers, 1, magnitudes, 1, powers, 1, half)
        }

        // A silent PCM window is evidence that playback is quiet. Clear the envelope
        // immediately; decaying bars after the last sample would invent activity.
        guard peak > 0.000_001 else {
            smoothed = AudioSpectrumFrame.silence.bands
            return .silence
        }

        if binsRate != sampleRate {
            binsRate = sampleRate
            bins = (0..<6).map { band in
                // Bin 0 packs DC and Nyquist in the real FFT; bands start at bin 1.
                let first = max(1, Int(ceil(Self.edges[band] * Double(Self.windowSize) / sampleRate)))
                let last  = min(
                    Self.half,
                    Int(ceil(Self.edges[band + 1] * Double(Self.windowSize) / sampleRate))
                )
                return (first, max(0, last - first))
            }
        }

        // fft_zrip doubles each coefficient, so its power is four times the complex FFT's.
        let normalization = Float(1) / Float(Self.windowSize * Self.windowSize * channelCount)
        for (band, range) in bins.enumerated() {
            var energy: Float = 0
            if range.count > 0 {
                vDSP_sve(powers + range.first, 1, &energy, vDSP_Length(range.count))
            }

            let amplitude = sqrt(energy * normalization)
            let decibels  = 20 * log10(max(amplitude, 0.000_001))
            let target    = min(1, max(0, (decibels + 60) / 60))
            let blend: Float = target > smoothed[band] ? 0.72 : 0.3
            smoothed[band] += (target - smoothed[band]) * blend
        }

        return AudioSpectrumFrame(bands: smoothed)
    }
}
