//
//  ScreenshotPageTests.swift
//  Cascade
//

import Testing
import Foundation
@testable import Cascade

@MainActor
struct ScreenshotPageTests {

    /// The session must not restart when a repeated shortcut arrives, and it
    /// must release its persistent presentation when the user closes it.
    @Test
    func repeatedShortcutPreservesTheChoiceUntilDismissal() {
        let page = ScreenshotPage()
        var presentations: [Bool] = []
        page.onPresentationChanged = { presentations.append(page.isPresented) }

        page.present()
        page.select(.recording)
        page.present()
        #expect(page.mode == .recording)
        #expect(page.keepsExpandedPresentation)
        #expect(presentations == [true])

        page.dismiss()
        page.dismiss()
        #expect(!page.isPresented)
        #expect(!page.keepsExpandedPresentation)
        #expect(presentations == [true, false])

        page.present()
        #expect(page.mode == .recording)
        #expect(presentations == [true, false, true])
    }

    @Test
    func targetAndDestinationSurviveClosingAndRecreatingThePage() throws {
        let name = "cascade.screenshot.tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let page = ScreenshotPage(preferences: defaults)
        page.present()
        page.options.target = .window
        page.options.directoryPath = "/tmp/screenshot-output"
        page.options.delaySeconds = 5
        page.dismiss()
        page.present()
        #expect(page.options.target == .window)
        let restored = ScreenshotPage(preferences: defaults)
        #expect(restored.options == page.options)
    }

    @Test
    func timerScrollAndClickShareTheSameDelay() {
        var options = ScreenCaptureOptions()
        options.cycleDelay()
        #expect(options.delaySeconds == 3)
        options.adjustDelay(by: 1)
        #expect(options.delaySeconds == 4)
        options.cycleDelay()
        #expect(options.delaySeconds == 5)
        options.cycleDelay()
        #expect(options.delaySeconds == 10)
        options.cycleDelay()
        #expect(options.delaySeconds == 0)
        options.adjustDelay(by: -1)
        #expect(options.delaySeconds == 0)
    }

    @Test
    func anUnimplementedTargetCannotCaptureTheWholeDisplay() throws {
        let name = "cascade.screenshot.tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let page = ScreenshotPage(preferences: defaults)
        page.present()
        page.options.target = .region
        var captures = 0
        page.onAction = { _ in captures += 1 }
        page.perform(.capture)
        #expect(captures == 0)
        #expect(page.isPresented)
    }
}
