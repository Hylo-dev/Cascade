//
//  ScreenRecording.swift
//  Cascade
//

import Foundation

/// ScreenRecording is the common native file-output adapter across the macOS
/// deployment floor. Finalization completes before its output is reported saved.
nonisolated protocol ScreenRecording: Sendable {

    var outputURL: URL { get }
    func start() async throws -> Date
    func stop() async throws
}
