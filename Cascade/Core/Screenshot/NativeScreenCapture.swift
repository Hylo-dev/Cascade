//
//  NativeScreenCapture.swift
//  Cascade
//

import CoreGraphics
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

/// NativeScreenCapture owns capture resources away from the UI actor. Apple's
/// stream handles capture and encoding; no frame is copied into observable UI
/// state. The application is excluded so its controls never appear in the file.
actor NativeScreenCapture: ScreenCapturing {

    nonisolated let events: AsyncStream<ScreenRecordingEvent>
    private let continuation: AsyncStream<ScreenRecordingEvent>.Continuation
    private var recording: (any ScreenRecording)?
    private var isPreparing = false
    private var options = ScreenCaptureOptions()

    init() {
        let channel = AsyncStream<ScreenRecordingEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        events = channel.stream
        continuation = channel.continuation
    }

    func configure(_ options: ScreenCaptureOptions) {
        self.options = options
    }

    func destination(for mode: ScreenshotMode) throws -> URL {
        let manager = FileManager.default
        let configured = options.directoryPath
            ?? UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let directory: URL
        if let configured, !configured.isEmpty {
            directory = URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
        } else {
            directory = try manager.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        }
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let name = mode == .capture ? "Screenshot" : "Screen Recording"
        return directory.appendingPathComponent("\(name) \(stamp) \(UUID().uuidString.prefix(8)).\(mode == .capture ? "png" : "mp4")")
    }

    func capture(displayID: CGDirectDisplayID, to url: URL) async throws {
        let (filter, configuration) = try await configuration(on: displayID)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = options.includesPointer
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ScreenCaptureFailure.native("The screenshot destination is unavailable.") }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureFailure.native("The screenshot could not be saved.")
        }
    }

    func startRecording(displayID: CGDirectDisplayID, to url: URL) async throws -> Date {
        guard recording == nil, !isPreparing else { throw ScreenCaptureFailure.alreadyRecording }

        isPreparing = true
        defer { isPreparing = false }
        let (filter, configuration) = try await configuration(on: displayID)
        let continuation = self.continuation
        let emit: @Sendable (ScreenRecordingEvent) -> Void = { continuation.yield($0) }
        let session: any ScreenRecording
        if #available(macOS 15, *) {
            session = try NativeRecordingSession(filter: filter, configuration: configuration, outputURL: url, emit: emit)
        } else {
            session = try LegacyRecordingSession(filter: filter, configuration: configuration, outputURL: url, emit: emit)
        }
        recording = session
        do {
            let date = try await session.start()
            try Task.checkCancellation()
            return date
        } catch {
            try? await session.stop()
            recording = nil
            throw error
        }
    }

    func stopRecording() async throws -> URL? {
        guard let recording else { return nil }

        defer { self.recording = nil }
        try await recording.stop()
        return recording.outputURL
    }

    private func configuration(on displayID: CGDirectDisplayID) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureFailure.displayUnavailable
        }
        let ownApplications = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.showsCursor = options.includesPointer
        configuration.capturesAudio = options.includesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = options.includesMicrophone
        configuration.showMouseClicks = options.showsMouseClicks
        configuration.ignoreShadowsSingleWindow = !options.includesWindowShadow
        return (filter, configuration)
    }
}
