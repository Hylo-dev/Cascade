//
//  LegacyRecordingSession.swift
//  Cascade
//

@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import QuartzCore

/// LegacyRecordingSession uses Apple's encoder on macOS 14, where
/// SCRecordingOutput is unavailable. Writer state belongs exclusively to the
/// sample queue; backpressure drops a frame instead of blocking the compositor.
nonisolated final class LegacyRecordingSession: NSObject, ScreenRecording, @unchecked Sendable {

    let outputURL: URL

    private let completion = RecordingCompletion()
    private let queue      = DispatchQueue(label: "cascade.screen-recording", qos: .utility)
    private let writer     : AVAssetWriter
    private let input      : AVAssetWriterInput
    private let emit       : @Sendable (ScreenRecordingEvent) -> Void
    private var stream     : SCStream?
    private var hasStarted = false
    private var hasFailed  = false
    private var lastSample: CMSampleBuffer?
    private var lastSampleHostTime: CFTimeInterval = 0
    private var isFinishing = false

    init(
        filter       : SCContentFilter,
        configuration: SCStreamConfiguration,
        outputURL    : URL,
        emit         : @escaping @Sendable (ScreenRecordingEvent) -> Void
    ) throws {
        self.outputURL = outputURL
        self.emit = emit
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        input = AVAssetWriterInput(
            mediaType     : .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: configuration.width,
                AVVideoHeightKey: configuration.height,
            ]
        )
        input.expectsMediaDataInRealTime = true
        super.init()
        guard writer.canAdd(input) else {
            throw ScreenCaptureFailure.native("The video encoder is unavailable.")
        }
        writer.add(input)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
    }

    func start() async throws -> Date {
        guard let stream else { throw ScreenCaptureFailure.displayUnavailable }

        try await stream.startCapture()
        return try await completion.waitForStart()
    }

    func stop() async throws {
        defer { stream = nil }
        if await completion.hasFinishedSuccessfully { return }
        do {
            if let stream { try await stream.stopCapture() }
        } catch {
            queue.async { [self] in
                lastSample = nil
                writer.cancelWriting()
            }
            await completion.fail(.native(error.localizedDescription))
            throw error
        }
        queue.async { [self] in
            guard hasStarted, !hasFailed else {
                writer.cancelWriting()
                Task { await completion.fail(.native("No video frames were received.")) }
                return
            }
            let elapsed = max(0, CACurrentMediaTime() - lastSampleHostTime)
            let lastTimestamp = lastSample?.presentationTimeStamp ?? .zero
            let end = lastTimestamp + CMTime(seconds: elapsed, preferredTimescale: 600)
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard input.isReadyForMoreMediaData, !isFinishing else { return }
                isFinishing = true
                if let lastSample {
                    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: end, decodeTimeStamp: .invalid)
                    var finalSample: CMSampleBuffer?
                    let result = CMSampleBufferCreateCopyWithNewTiming(
                        allocator: kCFAllocatorDefault,
                        sampleBuffer: lastSample,
                        sampleTimingEntryCount: 1,
                        sampleTimingArray: &timing,
                        sampleBufferOut: &finalSample
                    )
                    if result == noErr, let finalSample { _ = input.append(finalSample) }
                }
                self.lastSample = nil
                input.markAsFinished()
                writer.endSession(atSourceTime: end)
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        Task {
                            await completion.finished()
                            emit(.finished(outputURL))
                        }
                    } else {
                        report(writer.error ?? ScreenCaptureFailure.native("Video finalization failed."))
                    }
                }
            }
        }
        do { try await completion.waitForFinish() }
        catch {
            queue.async { [self] in
                lastSample = nil
                writer.cancelWriting()
            }
            throw error
        }
    }

    private func report(_ error: any Error) {
        let description = error.localizedDescription
        Task {
            await completion.fail(.native(description))
            emit(.failed(outputURL, description))
        }
    }
}

extension LegacyRecordingSession: SCStreamOutput, SCStreamDelegate {

    func stream(
        _ stream        : SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType   : SCStreamOutputType
    ) {
        guard outputType == .screen, !hasFailed, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue
        else { return }

        if !hasStarted {
            guard writer.startWriting() else {
                hasFailed = true
                report(writer.error ?? ScreenCaptureFailure.native("Video encoding failed."))
                return
            }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            hasStarted = true
            let date = Date.now
            Task { await completion.started(at: date) }
        }
        guard input.isReadyForMoreMediaData else { return }

        if !input.append(sampleBuffer) {
            hasFailed = true
            report(writer.error ?? ScreenCaptureFailure.native("Video encoding failed."))
        } else {
            lastSample = sampleBuffer
            lastSampleHostTime = CACurrentMediaTime()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) { report(error) }
}
