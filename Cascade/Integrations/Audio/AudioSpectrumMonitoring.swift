//
//  AudioSpectrumMonitoring.swift
//  Cascade
//

/// AudioSpectrumFrame contains measured low-to-high frequency energy, normalized to six bars.
nonisolated struct AudioSpectrumFrame: Equatable, Sendable {
    let bands: [Float]

    static let silence = AudioSpectrumFrame(bands: [0, 0, 0, 0, 0, 0])
}

/// AudioSpectrumStatus distinguishes unavailable capture from measured silence.
nonisolated enum AudioSpectrumStatus: Equatable, Sendable {
    case stopped
    case capturing
    case permissionRequired
    case unsupported
    case unavailable(String)
}

/// AudioSpectrumMonitoring measures playback only while an interested presentation is active.
@MainActor
protocol AudioSpectrumMonitoring: AnyObject {
    var status: AudioSpectrumStatus { get }

    func start(sourceBundleIdentifier: String?) -> AsyncStream<AudioSpectrumFrame>
    func stop()
}
