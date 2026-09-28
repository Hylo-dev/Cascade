//
//  AudioSpectrumFrame.swift
//  Cascade
//



/// AudioSpectrumFrame contains measured low-to-high frequency energy, normalized to six bars.
nonisolated struct AudioSpectrumFrame: Equatable, Sendable {
    let bands: [Float]

    static let silence = AudioSpectrumFrame(bands: [0, 0, 0, 0, 0, 0])
}
