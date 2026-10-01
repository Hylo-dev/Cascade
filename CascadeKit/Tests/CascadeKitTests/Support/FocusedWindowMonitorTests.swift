//
//  FocusedWindowMonitorTests.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

@MainActor
struct FocusedWindowMonitorTests {

    @Test
    func focusedWindowChangeWithinTheSameApplicationPublishesTheNewFrame() async {
        let application  = FocusedApplication(processID: 400, bundleIdentifier: "example.editor")
        let applications = FakeFocusedApplicationMonitor(application: application)
        let transport    = RecordingFocusedWindowTransport()
        let monitor      = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay   : 0
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
        let monitor   = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay   : 0
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
        let monitor   = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay   : 0
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
        let monitor   = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay   : 0
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
        let monitor   = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay   : 0
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
                processID       : ProcessInfo.processInfo.processIdentifier,
                bundleIdentifier: Bundle.main.bundleIdentifier
            )
        )
        let transport = RecordingFocusedWindowTransport()
        let monitor   = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay   : 0
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
        let monitor   = FocusedWindowMonitor(
            applicationMonitor: applications,
            transport         : transport,
            desktopTop        : { 900 },
            coalescingDelay   : 0
        )
        let rawFrame = CGRect(x: 100, y: 100, width: 300, height: 200)
        var frames  : [CGRect?] = []

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

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for asynchronous monitor work")
    }
}
