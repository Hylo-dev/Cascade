//
//  AudioCapturePermissionRequester.swift
//  Cascade
//

/// AudioCapturePermissionRequester performs a short, independent capture attempt.
/// Core Audio has no public consent-only API: starting a private tap aggregate
/// asks macOS for system-audio access. This probe discards every sample and
/// releases the tap as soon as setup succeeds, fails or is cancelled. Startup
/// runs it once per installation, not per launch: it cannot detect a denial
/// (the tap then delivers silence), so repeating it would only cost HAL churn.
@MainActor
final class AudioCapturePermissionRequester {
    private let driver: any AudioSpectrumCaptureDriving

    init(driver: any AudioSpectrumCaptureDriving = CoreAudioSpectrumCaptureDriver()) {
        self.driver = driver
    }

    func requestAccess() async -> AudioSpectrumStatus {
        let status = AsyncStream<AudioSpectrumStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let samples = AsyncStream<AudioSpectrumFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let driver = driver
        defer {
            driver.stop()
            status.continuation.finish()
            samples.continuation.finish()
        }
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return .stopped }
            driver.start(
                sourceBundleIdentifier: nil,
                continuation          : samples.continuation,
                status                : { status.continuation.yield($0) }
            )
            for await update in status.stream {
                guard !Task.isCancelled else { return .stopped }
                return update
            }
            return .stopped
        } onCancel: {
            driver.stop()
            status.continuation.finish()
        }
    }
}
