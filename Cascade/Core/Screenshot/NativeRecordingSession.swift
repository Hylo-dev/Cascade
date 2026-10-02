//
//  NativeRecordingSession.swift
//  Cascade
//

import AVFoundation
@preconcurrency import ScreenCaptureKit

/// NativeRecordingSession gives ScreenCaptureKit ownership of encoding and
/// muxing on macOS 15+. The background service serializes start/stop; callbacks
/// touch only the completion actor and a Sendable event sink.
@available(macOS 15, *)
nonisolated final class NativeRecordingSession: NSObject, ScreenRecording, @unchecked Sendable {

    let outputURL: URL

    private let completion = RecordingCompletion()
    private let emit      : @Sendable (ScreenRecordingEvent) -> Void
    private var stream    : SCStream?
    private var output    : SCRecordingOutput?

    init(
        filter       : SCContentFilter,
        configuration: SCStreamConfiguration,
        outputURL    : URL,
        emit         : @escaping @Sendable (ScreenRecordingEvent) -> Void
    ) throws {
        self.outputURL = outputURL
        self.emit      = emit
        super.init()

        let file = SCRecordingOutputConfiguration()
        file.outputURL      = outputURL
        file.outputFileType = .mp4
        file.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: file, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(output)
        self.output = output
        self.stream = stream
    }

    func start() async throws -> Date {
        guard let stream else { throw ScreenCaptureFailure.displayUnavailable }

        try await stream.startCapture()
        return try await completion.waitForStart()
    }

    func stop() async throws {
        guard let stream else { return }
        defer {
            self.stream = nil
            output = nil
        }
        if await completion.hasFinishedSuccessfully {
            try await completion.waitForFinish()
            return
        }

        do {
            try await stream.stopCapture()
            try await completion.waitForFinish()
        } catch {
            await completion.fail(.native(error.localizedDescription))
            throw error
        }
    }
}

@available(macOS 15, *)
extension NativeRecordingSession: SCRecordingOutputDelegate, SCStreamDelegate {

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let date = Date.now
        Task { await completion.started(at: date) }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task {
            await completion.finished()
            emit(.finished(outputURL))
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        report(error)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) { report(error) }

    private func report(_ error: any Error) {
        let description = error.localizedDescription
        Task {
            await completion.fail(.native(description))
            emit(.failed(outputURL, description))
        }
    }
}
