//
//  ScreenCaptureFailure.swift
//  Cascade
//

import Foundation

nonisolated enum ScreenCaptureFailure: Error, LocalizedError, Sendable {

    case displayUnavailable
    case alreadyRecording
    case timedOut
    case native(String)

    var errorDescription: String? {
        switch self {
            case .displayUnavailable: String(localized: "The capture display is no longer available.")
            case .alreadyRecording: String(localized: "A screen recording is already running.")
            case .timedOut: String(localized: "Screen recording did not respond in time.")
            case .native(let description): description
        }
    }
}
