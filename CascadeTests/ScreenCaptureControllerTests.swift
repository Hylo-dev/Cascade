//
//  ScreenCaptureControllerTests.swift
//  Cascade
//

import CascadePluginEngine
import CascadePlugins
import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import Cascade

@MainActor
struct ScreenCaptureControllerTests {

    @Test
    func aRecordingCannotStartWithoutItsPluginControls() async {
        let capture = CaptureStub()
        let source = ScreenRecordingPluginSource()
        var failures = 0
        let controller = ScreenCaptureController(
            capture: capture,
            publish: { source.update($0) },
            close  : {},
            failed : { _ in failures += 1 }
        )

        await controller.perform(.recording, on: 123)

        #expect(await capture.starts == 0)
        #expect(!controller.isRecording)
        #expect(failures == 1)
        await controller.shutdown()
    }

    @Test
    func aReleasedPluginSourceCannotStartAnotherWriter() async {
        let capture = CaptureStub()
        let source = ScreenRecordingPluginSource()
        let channel = AsyncStream<PluginSourceEvent>.makeStream()
        source.start { channel.continuation.yield($0) }
        var events = channel.stream.makeAsyncIterator()
        _ = await events.next()
        var failures = 0
        let controller = ScreenCaptureController(
            capture  : capture,
            canRecord: { source.isAvailable },
            publish  : { source.update($0) },
            close    : {},
            failed   : { _ in failures += 1 }
        )
        await withCheckedContinuation { continuation in
            source.onReleased = { continuation.resume() }
            source.stop()
        }

        await controller.perform(.recording, on: 123)

        #expect(await capture.starts == 0)
        #expect(failures == 1)
        #expect(!controller.isRecording)
        channel.continuation.finish()
        await controller.shutdown()
    }

    @Test
    func stopBeforeDestinationResolutionCannotStartCapture() async {
        let capture = CaptureStub()
        var controller: ScreenCaptureController?
        var publications: [PluginScreenRecordingState] = []
        controller = ScreenCaptureController(
            capture: capture,
            canRecord: { true },
            publish: { publications = $0.session == nil ? [] : [$0] },
            close  : { controller?.requestStop() },
            failed : { Issue.record("Unexpected failure: \($0)") }
        )
        await controller?.perform(.recording, on: 123)
        #expect(await capture.starts == 0)
        #expect(publications.isEmpty)
        await controller?.shutdown()
        controller = nil
    }

    @Test
    func stopDuringNativeStartupCannotPublishAnUnattendedRecording() async {
        let capture = CaptureStub(holdStart: true)
        var publications: [PluginScreenRecordingState] = []
        let controller = ScreenCaptureController(
            capture: capture,
            canRecord: { true },
            publish: { publications = $0.session == nil ? [] : [$0] },
            close  : {},
            failed : { Issue.record("Unexpected failure: \($0)") }
        )
        let operation = Task { await controller.perform(.recording, on: 123) }
        await capture.waitUntilStartRequested()
        controller.requestStop()
        await capture.resumeStart()
        await operation.value
        #expect(publications.last?.session == nil)
        #expect(!controller.isRecording)
        #expect(await capture.stops == 1)
        await controller.shutdown()
    }

    @Test
    func terminalCallbackDuringStartupCannotPublishAFinishedRecording() async {
        let capture = CaptureStub(holdStart: true)
        var publications: [PluginScreenRecordingState] = []
        let controller = ScreenCaptureController(
            capture: capture,
            canRecord: { true },
            publish: { publications = $0.session == nil ? [] : [$0] },
            close  : {},
            failed : { Issue.record("Unexpected failure: \($0)") }
        )
        let operation = Task { await controller.perform(.recording, on: 123) }
        await capture.waitUntilStartRequested()
        controller.handleNativeEvent(.finished(URL(fileURLWithPath: "/tmp/capture-test.mp4")))
        await capture.resumeStart()
        await operation.value
        #expect(publications.isEmpty)
        #expect(await capture.stops == 1)
        await controller.shutdown()
    }

    @Test
    func screenshotClosesControlsAndUsesNativeCaptureWithoutAnActivity() async {
        let capture = CaptureStub()
        var publications: [PluginScreenRecordingState] = []
        var closed = false
        let controller = ScreenCaptureController(
            capture: capture,
            canRecord: { true },
            publish: { publications = $0.session == nil ? [] : [$0] },
            close  : { closed = true },
            failed : { Issue.record("Unexpected failure: \($0)") }
        )
        await controller.perform(.capture, on: 123)
        #expect(closed)
        #expect(await capture.capturedDisplay == 123)
        #expect(publications.isEmpty)
        await controller.shutdown()
    }

    @Test
    func anAuthorizedStopIsBoundToTheNativeRecordingSession() async throws {
        let capture = CaptureStub()
        var publications: [PluginScreenRecordingState] = []
        let controller = ScreenCaptureController(
            capture: capture,
            canRecord: { true },
            publish: { publications = $0.session == nil ? [] : [$0] },
            close  : {},
            failed : { Issue.record("Unexpected failure: \($0)") }
        )
        await controller.perform(.recording, on: 123)
        let state = try #require(publications.last)
        let session = try #require(state.session)
        let owner = try #require(PluginID(rawValue: "com.cascade.screen-recording"))
        let key = PluginPublicationKey(plugin: owner, feature: "recording", surface: .activity)
        #expect(state.startedAt == CaptureStub.startedAt)
        controller.handleAction(PluginActionRequest(key: key, node: PluginNodeID(rawValue: "#stop." + UUID().uuidString + ":button"), revision: 1))
        #expect(await capture.stops == 0)
        let accepted = PluginActionRequest(key: key, node: PluginNodeID(rawValue: "#stop." + session.uuidString + ":button"), revision: 1)
        controller.handleAction(accepted)
        controller.handleAction(accepted)
        await controller.shutdown()
        #expect(await capture.starts == 1)
        #expect(await capture.stops == 1)
        #expect(publications.last?.session == nil)
        #expect(!controller.isRecording)
    }

    @Test
    func screenshotFailureCannotHideAnOngoingRecording() async {
        let capture = CaptureStub()
        var publications: [PluginScreenRecordingState] = []
        var failures: [String] = []
        let controller = ScreenCaptureController(
            capture: capture,
            canRecord: { true },
            publish: { publications = $0.session == nil ? [] : [$0] },
            close  : {},
            failed : { failures.append($0) }
        )
        await controller.perform(.recording, on: 123)
        await capture.failNextCapture()
        await controller.perform(.capture, on: 123)
        #expect(controller.isRecording)
        #expect(publications.count == 1)
        #expect(failures.count == 1)
        #expect(await capture.stops == 0)
        await controller.shutdown()
    }
}

/// CaptureStub records requests at the real asynchronous framework seam.
private actor CaptureStub: ScreenCapturing {

    nonisolated static let startedAt = Date.now
    nonisolated let events: AsyncStream<ScreenRecordingEvent> = AsyncStream { _ in }
    private(set) var capturedDisplay: CGDirectDisplayID?
    private(set) var starts = 0
    private(set) var stops = 0
    private var shouldFailCapture = false
    private let holdStart: Bool
    private var startWaiter: CheckedContinuation<Date, Never>?
    private var requestedWaiter: CheckedContinuation<Void, Never>?

    init(holdStart: Bool = false) { self.holdStart = holdStart }

    func waitUntilStartRequested() async {
        if starts > 0 { return }
        await withCheckedContinuation { requestedWaiter = $0 }
    }

    func resumeStart() {
        startWaiter?.resume(returning: Self.startedAt)
        startWaiter = nil
    }

    func destination(for mode: ScreenshotMode) -> URL { URL(fileURLWithPath: "/tmp/capture-test.\(mode == .capture ? "png" : "mp4")") }
    func capture(displayID: CGDirectDisplayID, to url: URL) throws {
        if shouldFailCapture { throw ScreenCaptureFailure.native("Disk full") }
        capturedDisplay = displayID
    }
    func startRecording(displayID: CGDirectDisplayID, to url: URL) async -> Date {
        starts += 1
        requestedWaiter?.resume()
        requestedWaiter = nil
        if holdStart { return await withCheckedContinuation { startWaiter = $0 } }
        return Self.startedAt
    }
    func stopRecording() -> URL? { stops += 1; return nil }
    func failNextCapture() { shouldFailCapture = true }
}
