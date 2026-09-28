//
//  CoreAudioSpectrumMonitor.swift
//  Cascade
//

import Foundation
import Observation

/// CoreAudioSpectrumMonitor owns one subscriber and invalidates obsolete callbacks synchronously.
/// HAL setup and teardown live on the driver's worker; MainActor only owns observation and streams.
@Observable
@MainActor
final class CoreAudioSpectrumMonitor: AudioSpectrumMonitoring {
    private(set) var status: AudioSpectrumStatus = .stopped

    @ObservationIgnored
    private let driver: any AudioSpectrumCaptureDriving

    @ObservationIgnored
    private var continuation: AsyncStream<AudioSpectrumFrame>.Continuation?

    @ObservationIgnored
    private var generation: UInt64 = 0

    init(driver: any AudioSpectrumCaptureDriving = CoreAudioSpectrumCaptureDriver()) {
        self.driver = driver
    }

    /// start replaces the previous subscription and returns only the newest unread measured frame.
    func start(sourceBundleIdentifier: String?) -> AsyncStream<AudioSpectrumFrame> {
        stop()
        let currentGeneration = generation
        let pair = AsyncStream<AudioSpectrumFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = pair.continuation
        pair.continuation.yield(.silence)
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.stop()
            }
        }
        driver.start(
            sourceBundleIdentifier: sourceBundleIdentifier,
            continuation: pair.continuation,
            status: { [weak self] updatedStatus in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.status = updatedStatus
                }
            }
        )
        return pair.stream
    }

    /// stop closes the stream immediately while HAL teardown completes on the driver's worker.
    func stop() {
        generation &+= 1
        continuation?.finish()
        continuation = nil
        status = .stopped
        driver.stop()
    }

    deinit {
        continuation?.finish()
        driver.stop()
    }
}
