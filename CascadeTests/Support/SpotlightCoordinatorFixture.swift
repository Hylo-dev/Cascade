//
//  SpotlightCoordinatorFixture.swift
//  Cascade
//

import AppKit
import CascadeKit
import Testing
@testable import Cascade

@MainActor
final class SpotlightCoordinatorFixture {

    let processID  : pid_t = 42
    let droplet     = RecordingSpotlightDroplet()
    let tap         = RecordingSpotlightTap()
    let coordinator: SpotlightCoordinator

    private let shortcut      : SpotlightShortcut
    private let releaseCounter: SpotlightCounter

    var releaseCount: Int { releaseCounter.value }

    init(
        handoffTimeout  : Duration = .seconds(1.8),
        hasShortcut     : Bool = true,
        initiallyEnabled: Bool = true
    ) throws {
        let screen   = try #require(NSScreen.main)
        let shortcut = try #require(SpotlightShortcut(preference: [
            "enabled": true,
            "value"  : ["parameters": [32, 49, 1 << 20]],
        ]))
        let anchor = SpotlightDisplayAnchor(
            displayID    : screen.cascadeRuntimeDisplayID,
            screen       : screen,
            restingBounds: CGRect(x: screen.frame.midX - 48, y: screen.frame.maxY - 8, width: 96, height: 8)
        )
        self.shortcut = shortcut

        let releaseCounter  = SpotlightCounter()
        self.releaseCounter = releaseCounter

        coordinator = SpotlightCoordinator(
            droplet            : droplet,
            tap                : tap,
            anchor             : { anchor },
            reservePresentation: { _, ready in ready() },
            releasePresentation: { releaseCounter.value += 1 },
            initialShortcut    : hasShortcut ? shortcut : nil,
            initialProcessID   : processID,
            initiallyEnabled   : initiallyEnabled,
            handoffTimeout     : handoffTimeout
        )
    }

    /// waitForReleases waits until the coordinator has released the presentation `count` times,
    /// so a handoff timeout that fires late on a loaded machine still counts. It gives up after
    /// two seconds and leaves the caller's expectation to fail.
    func waitForReleases(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while releaseCount < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func shortcutEvent() -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey         : shortcut.keyCode,
            keyDown            : true
        )!
        event.flags = shortcut.flags

        return event
    }
}
