//
//  FocusedDisplayResolverTests.swift
//  CascadeKitTests
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

nonisolated struct FocusedDisplayResolverTests {

    private let frames: [CGDirectDisplayID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 1_000, height: 800),
        2: CGRect(x: -1_000, y: 0, width: 1_000, height: 800),
        3: CGRect(x: 0, y: 800, width: 1_000, height: 800),
    ]

    @Test
    func focusedWindowWinsOverPointer() {
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: -900, y: 100, width: 600, height: 500),
            pointer : CGPoint(x: 500, y: 400),
            frames  : frames,
            previous: 1,
            main    : 1
        ) == 2)
        #expect(FocusedDisplayResolver.resolve(
            window  : nil,
            pointer : CGPoint(x: 500, y: 400),
            frames  : frames,
            previous: 2,
            main    : 1
        ) == 1)
    }

    @Test
    func largestIntersectionWinsAndPreviousBreaksAnAreaTie() {
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: -300, y: 100, width: 800, height: 400),
            pointer : CGPoint(x: -500, y: 400),
            frames  : frames,
            previous: 2,
            main    : 1
        ) == 1)
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: -500, y: 100, width: 1_000, height: 400),
            pointer : CGPoint(x: 500, y: 400),
            frames  : frames,
            previous: 2,
            main    : 1
        ) == 2)
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: -500, y: 100, width: 1_000, height: 400),
            pointer : CGPoint(x: 500, y: 400),
            frames  : frames,
            previous: nil,
            main    : 1
        ) == 1)
    }

    @Test
    func invalidGeometryFallsBackWithoutKeepingAStaleWindowDisplay() {
        let invalidFrames: [CGDirectDisplayID: CGRect] = [
            7: CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100),
            8: .null,
            9: CGRect(x: 2_000, y: 0, width: 0, height: 100),
            4: CGRect(x: 0, y: 0, width: 100, height: 100),
        ]

        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: 500, y: 500, width: 100, height: 100),
            pointer : CGPoint(x: 10, y: 10),
            frames  : invalidFrames,
            previous: 7,
            main    : 7
        ) == 4)
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
            pointer : CGPoint(x: CGFloat.nan, y: 10),
            frames  : invalidFrames,
            previous: 4,
            main    : 7
        ) == 4)
        #expect(FocusedDisplayResolver.resolve(
            window  : nil,
            pointer : CGPoint(x: CGFloat.nan, y: CGFloat.nan),
            frames  : [:],
            previous: 4,
            main    : 7
        ) == nil)
    }

    @Test
    func accessibilityFramesNormalizeAcrossTheWholeDesktop() {
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
            desktopTop : 900
        ) == CGRect(x: 100, y: 500, width: 400, height: 300))
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: 50, y: -700, width: 400, height: 400),
            desktopTop : 900
        ) == CGRect(x: 50, y: 1_200, width: 400, height: 400))
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: 50, y: 1_000, width: 400, height: 300),
            desktopTop : 900
        ) == CGRect(x: 50, y: -400, width: 400, height: 300))
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: -900, y: 200, width: 500, height: 300),
            desktopTop : 900
        ) == CGRect(x: -900, y: 400, width: 500, height: 300))
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: 0, y: 0, width: 0, height: 300),
            desktopTop : 900
        ) == nil)
    }
}

@MainActor
struct FocusedWindowMonitorTests {

    @Test
    func focusedWindowChangeWithinTheSameApplicationPublishesTheNewFrame() async {
        let application = FocusedApplication(processID: 400, bundleIdentifier: "example.editor")
        let applications = FakeFocusedApplicationMonitor(application: application)
        let transport = RecordingFocusedWindowTransport()
        let monitor = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay    : 0
        )
        var frames: [CGRect?] = []
        monitor.onChange = { frames.append($0) }

        monitor.start()
        await waitUntil { transport.requestCount == 1 }
        transport.completeRequest(
            at    : 0,
            result: .frameInAXCoordinates(CGRect(x: 50, y: 100, width: 500, height: 400))
        )
        await waitUntil { frames.count == 1 }

        transport.sendObservedChange()
        await waitUntil { transport.requestCount == 2 }
        transport.completeRequest(
            at    : 1,
            result: .frameInAXCoordinates(CGRect(x: -900, y: 200, width: 600, height: 500))
        )
        await waitUntil { frames.count == 2 }

        #expect(frames == [
            CGRect(x: 50, y: 400, width: 500, height: 400),
            CGRect(x: -900, y: 200, width: 600, height: 500),
        ])
        #expect(transport.requestedProcessIDs == [400, 400])
        monitor.stop()
    }

    @Test
    func windowMovementPublishesWithoutAnyPointerEvent() async {
        let applications = FakeFocusedApplicationMonitor(
            application: FocusedApplication(processID: 450, bundleIdentifier: "example.editor")
        )
        let transport = RecordingFocusedWindowTransport()
        let monitor = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay    : 0
        )
        var frames: [CGRect?] = []
        monitor.onChange = { frames.append($0) }

        monitor.start()
        await waitUntil { transport.requestCount == 1 }
        transport.completeRequest(
            at    : 0,
            result: .frameInAXCoordinates(CGRect(x: 100, y: 100, width: 500, height: 300))
        )
        await waitUntil { frames.count == 1 }

        transport.sendObservedChange()
        await waitUntil { transport.requestCount == 2 }
        transport.completeRequest(
            at    : 1,
            result: .frameInAXCoordinates(CGRect(x: -700, y: -400, width: 500, height: 300))
        )
        await waitUntil { frames.count == 2 }

        #expect(frames == [
            CGRect(x: 100, y: 500, width: 500, height: 300),
            CGRect(x: -700, y: 1_000, width: 500, height: 300),
        ])
        monitor.stop()
    }

    @Test
    func minimizedOrDestroyedWindowClearsThePublishedFrame() async {
        let applications = FakeFocusedApplicationMonitor(
            application: FocusedApplication(processID: 475, bundleIdentifier: "example.editor")
        )
        let transport = RecordingFocusedWindowTransport()
        let monitor = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay    : 0
        )
        var frames: [CGRect?] = []
        monitor.onChange = { frames.append($0) }

        monitor.start()
        await waitUntil { transport.requestCount == 1 }
        transport.completeRequest(
            at    : 0,
            result: .frameInAXCoordinates(CGRect(x: 100, y: 100, width: 500, height: 300))
        )
        await waitUntil { frames.count == 1 }

        transport.sendObservedChange()
        await waitUntil { transport.requestCount == 2 }
        transport.completeRequest(at: 1, result: .unavailable)
        await waitUntil { frames.count == 2 }

        #expect(frames[1] == nil)
        monitor.stop()
    }

    @Test
    func staleCompletionFromAnEarlierGenerationIsDiscarded() async {
        let applications = FakeFocusedApplicationMonitor(
            application: FocusedApplication(processID: 500, bundleIdentifier: "example.editor")
        )
        let transport = RecordingFocusedWindowTransport()
        let monitor = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay    : 0
        )
        var frames: [CGRect?] = []
        monitor.onChange = { frames.append($0) }

        monitor.start()
        await waitUntil { transport.requestCount == 1 }
        transport.sendObservedChange()
        await waitUntil { transport.requestCount == 2 }

        transport.completeRequest(
            at    : 1,
            result: .frameInAXCoordinates(CGRect(x: 600, y: 100, width: 200, height: 200))
        )
        transport.completeRequest(
            at    : 0,
            result: .frameInAXCoordinates(CGRect(x: -800, y: 100, width: 200, height: 200))
        )
        await waitUntil { frames.count == 1 }

        #expect(frames == [CGRect(x: 600, y: 600, width: 200, height: 200)])
        monitor.stop()
    }

    @Test
    func revokedPermissionClearsTheFocusedWindow() async {
        let applications = FakeFocusedApplicationMonitor(
            application: FocusedApplication(processID: 600, bundleIdentifier: "example.editor")
        )
        let transport = RecordingFocusedWindowTransport()
        let monitor = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay    : 0
        )
        var frames: [CGRect?] = []
        monitor.onChange = { frames.append($0) }

        monitor.start()
        await waitUntil { transport.requestCount == 1 }
        transport.completeRequest(
            at    : 0,
            result: .frameInAXCoordinates(CGRect(x: 100, y: 100, width: 300, height: 200))
        )
        await waitUntil { frames.count == 1 }

        monitor.refresh()
        await waitUntil { transport.requestCount == 2 }
        transport.completeRequest(at: 1, result: .permissionDenied)
        await waitUntil { frames.count == 2 }

        #expect(frames[0] == CGRect(x: 100, y: 600, width: 300, height: 200))
        #expect(frames[1] == nil)
        monitor.stop()
    }

    @Test
    func ownApplicationNeverBecomesTheFocusedWindowSource() async {
        let applications = FakeFocusedApplicationMonitor(
            application: FocusedApplication(
                processID      : ProcessInfo.processInfo.processIdentifier,
                bundleIdentifier: Bundle.main.bundleIdentifier
            )
        )
        let transport = RecordingFocusedWindowTransport()
        let monitor = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay    : 0
        )
        var frames: [CGRect?] = []
        monitor.onChange = { frames.append($0) }

        monitor.start()
        await waitUntil { transport.requestCount == 1 }
        #expect(transport.requestedProcessIDs == [nil])
        transport.completeRequest(at: 0, result: .unavailable)
        await waitUntil { frames.count == 1 }
        #expect(frames[0] == nil)
        monitor.stop()
    }

    @Test
    func stopInvalidatesOldWorkAndRestartRepublishesCurrentState() async {
        let applications = FakeFocusedApplicationMonitor(
            application: FocusedApplication(processID: 700, bundleIdentifier: "example.editor")
        )
        let transport = RecordingFocusedWindowTransport()
        let monitor = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay    : 0
        )
        let rawFrame = CGRect(x: 100, y: 100, width: 300, height: 200)
        var frames: [CGRect?] = []
        monitor.onChange = { frames.append($0) }

        monitor.start()
        await waitUntil { transport.requestCount == 1 }
        monitor.stop()
        transport.completeRequest(at: 0, result: .frameInAXCoordinates(rawFrame))
        try? await Task.sleep(for: .milliseconds(10))
        #expect(frames.isEmpty)

        monitor.start()
        await waitUntil { transport.requestCount == 2 }
        transport.completeRequest(at: 1, result: .frameInAXCoordinates(rawFrame))
        await waitUntil { frames.count == 1 }

        monitor.stop()
        monitor.start()
        await waitUntil { transport.requestCount == 3 }
        transport.completeRequest(at: 2, result: .frameInAXCoordinates(rawFrame))
        await waitUntil { frames.count == 2 }
        #expect(frames == [
            CGRect(x: 100, y: 600, width: 300, height: 200),
            CGRect(x: 100, y: 600, width: 300, height: 200),
        ])
        monitor.stop()
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for asynchronous monitor work")
    }
}

@MainActor
private final class FakeFocusedApplicationMonitor: FocusedApplicationMonitoring {
    var onChange: (() -> Void)?
    var application: FocusedApplication?

    init(application: FocusedApplication?) {
        self.application = application
    }

    var frontmostApplication: FocusedApplication? {
        application
    }

    func start() {}
    func stop() {}
}

nonisolated private final class RecordingFocusedWindowTransport: FocusedWindowTransport, @unchecked Sendable {
    private typealias Completion = @Sendable (FocusedWindowTransportResult) -> Void

    private let lock = NSLock()
    private var changeHandler: (@Sendable () -> Void)?
    private var completions: [Completion?] = []
    private var processIDs: [pid_t?] = []

    var requestCount: Int {
        lock.withLock { completions.count }
    }

    var requestedProcessIDs: [pid_t?] {
        lock.withLock { processIDs }
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        lock.withLock { changeHandler = onChange }
    }

    func requestSnapshot(
        processID: pid_t?,
        completion: @escaping @Sendable (FocusedWindowTransportResult) -> Void
    ) {
        lock.withLock {
            processIDs.append(processID)
            completions.append(completion)
        }
    }

    func stop() {
        lock.withLock { changeHandler = nil }
    }

    func sendObservedChange() {
        let handler = lock.withLock { changeHandler }
        handler?()
    }

    func completeRequest(
        at index: Int,
        result: FocusedWindowTransportResult
    ) {
        let completion = lock.withLock { () -> Completion? in
            guard completions.indices.contains(index) else {
                return nil
            }
            let completion = completions[index]
            completions[index] = nil
            return completion
        }
        completion?(result)
    }
}
