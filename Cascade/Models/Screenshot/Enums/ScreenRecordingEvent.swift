//
//  ScreenRecordingEvent.swift
//  Cascade
//

import Foundation

/// ScreenRecordingEvent includes the destination so retired native callbacks
/// cannot stop a newer recording or publish its result as the current session.
nonisolated enum ScreenRecordingEvent: Sendable {

    case finished(URL)
    case failed(URL, String)
}
