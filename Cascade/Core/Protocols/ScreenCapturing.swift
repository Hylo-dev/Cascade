//
//  ScreenCapturing.swift
//  Cascade
//

import CoreGraphics
import Foundation

/// ScreenCapturing keeps native capture and file I/O behind a background seam.
/// A visible activity does not own the recording's lifetime or encoder.
nonisolated protocol ScreenCapturing: Sendable {

    var events: AsyncStream<ScreenRecordingEvent> { get }

    func configure(_ options: ScreenCaptureOptions) async
    func destination(for mode: ScreenshotMode) async throws -> URL
    func capture(displayID: CGDirectDisplayID, to url: URL) async throws
    func startRecording(displayID: CGDirectDisplayID, to url: URL) async throws -> Date
    func stopRecording() async throws -> URL?
}

extension ScreenCapturing {

    func configure(_ options: ScreenCaptureOptions) async {}
}
