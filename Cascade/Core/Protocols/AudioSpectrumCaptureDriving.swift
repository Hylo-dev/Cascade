//
//  AudioSpectrumCaptureDriving.swift
//  Cascade
//

import Foundation
import Observation

/// AudioSpectrumCaptureDriving separates HAL side effects from the observable stream lifecycle.
nonisolated protocol AudioSpectrumCaptureDriving: Sendable {
    func start(
        sourceBundleIdentifier : String?,
        continuation           : AsyncStream<AudioSpectrumFrame>.Continuation,
        status                 : @escaping @Sendable (AudioSpectrumStatus) -> Void
    )
    func stop()
}
