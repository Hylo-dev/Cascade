//
//  CoreAudioSpectrumCaptureDriver.swift
//  Cascade
//

import Dispatch
import Foundation
import os

/// CoreAudioSpectrumCaptureDriver serializes every HAL lifetime operation off the main actor.
/// Its request lock is never used by an audio callback; cancellation prevents queued starts
/// and partially completed setups from becoming a live capture after their subscriber stops.
nonisolated final class CoreAudioSpectrumCaptureDriver: AudioSpectrumCaptureDriving, @unchecked Sendable {

    private let queue   = DispatchQueue(label: "app.cascade.audio-spectrum", qos: .utility)
    private let request = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    private var session: CoreAudioSpectrumCaptureSession?

    func start(
        sourceBundleIdentifier: String?,
        continuation          : AsyncStream<AudioSpectrumFrame>.Continuation,
        status                : @escaping @Sendable (AudioSpectrumStatus) -> Void
    ) {
        let generation = request.withLock { value in
            value &+= 1
            return value
        }

        queue.async { [self] in
            beginCapture(
                sourceBundleIdentifier: sourceBundleIdentifier,
                continuation          : continuation,
                status                : status,
                generation            : generation
            )
        }
    }

    func stop() {
        request.withLock { $0 &+= 1 }
        queue.async { [self] in
            session?.stop()
            session = nil
        }
    }

    private func beginCapture(
        sourceBundleIdentifier: String?,
        continuation          : AsyncStream<AudioSpectrumFrame>.Continuation,
        status                : @escaping @Sendable (AudioSpectrumStatus) -> Void,
        generation            : UInt64
    ) {
        guard request.withLock({ $0 == generation }) else { return }

        session?.stop()
        session = nil

        let capture = CoreAudioSpectrumCaptureSession(
            queue       : queue,
            continuation: continuation,
            isCurrent   : { [request] in request.withLock { $0 == generation } },
            invalidate  : { [weak self] in
                guard let self else { return }
                self.queue.async { [self] in
                    beginCapture(
                        sourceBundleIdentifier: sourceBundleIdentifier,
                        continuation          : continuation,
                        status                : status,
                        generation            : generation
                    )
                }
            }
        )

        do {
            try capture.start(sourceBundleIdentifier: sourceBundleIdentifier)
            guard request.withLock({ $0 == generation }) else {
                capture.stop()
                return
            }

            session = capture
            status(.capturing)
        } catch {
            capture.stop()
            guard request.withLock({ $0 == generation }) else { return }

            let failure = error as? SpectrumCaptureFailure
            status(failure?.status ?? .unavailable(error.localizedDescription))
            continuation.yield(.silence)
            // Keep the stream alive so its terminal status remains observable. Its owner
            // retries on a real activation or permission-change event, never on a timer.
        }
    }
}
