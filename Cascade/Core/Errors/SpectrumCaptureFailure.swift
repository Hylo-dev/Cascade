//
//  SpectrumCaptureFailure.swift
//  Cascade
//

import CoreAudio
import Foundation

/// SpectrumCaptureFailure keeps HAL diagnostics without treating unknown errors as permission denial.
nonisolated struct SpectrumCaptureFailure: Error {

    let status: AudioSpectrumStatus

    init(
        _ operation: String,
        result     : OSStatus
    ) {
        status = result == kAudioDevicePermissionsError
            ? .permissionRequired
            : .unavailable("\(operation): Core Audio \(result)")
    }

    init(_ reason: String) {
        status = .unavailable(reason)
    }
}
