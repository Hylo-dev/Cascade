//
//  AudioSpectrumMonitoring.swift
//  Cascade
//



/// AudioSpectrumMonitoring measures playback only while an interested presentation is active.
@MainActor
protocol AudioSpectrumMonitoring: AnyObject {
    var status: AudioSpectrumStatus { get }

    func start(sourceBundleIdentifier: String?) -> AsyncStream<AudioSpectrumFrame>
    func stop()
}
