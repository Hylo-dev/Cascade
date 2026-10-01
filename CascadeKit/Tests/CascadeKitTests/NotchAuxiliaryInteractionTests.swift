//
//  NotchAuxiliaryInteractionTests.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

@MainActor
struct NotchAuxiliaryInteractionTests {

    @Test
    func idleInteractionContainsNothing() {
        let interaction = NotchAuxiliaryInteraction()
        interaction.updatePointer(at: .zero)
        interaction.dismiss()
        #expect(!interaction.isActive)
        #expect(!interaction.contains(.zero))
    }

    @Test
    func openingRegistersBeforeContentIsReadyAndDismissalRejectsLateContent() async {
        let surface     = AuxiliaryPopoverFixture()
        let content     = AuxiliaryContentGate()
        let interaction = makeInteraction()
        interaction.present(using: surface) { await content.wait() }
        #expect(interaction.isActive)
        #expect(interaction.contains(CGPoint(x: 220, y: 135)))
        await content.waitUntilRequested()

        interaction.dismiss()
        content.resume()
        await content.waitUntilReturned()
        #expect(!interaction.isActive)
        #expect(surface.showCount == 0)
        #expect(surface.closeCount == 1)
        #expect(surface.content == nil)
    }

    @Test
    func popupAndNarrowBridgeDoNotIncludeTheirLargeBoundingUnion() async {
        let surface     = AuxiliaryPopoverFixture()
        let interaction = makeInteraction()
        interaction.present(using: surface) { NSViewController() }
        await surface.waitUntilShown()
        defer { interaction.dismiss() }

        #expect(interaction.contains(CGPoint(x: 20, y: 180)))  // Notch.
        #expect(interaction.contains(CGPoint(x: 320, y: 20)))  // Popup.
        #expect(interaction.contains(CGPoint(x: 220, y: 90)))  // 16 pt bridge.
        #expect(!interaction.contains(CGPoint(x: 250, y: 90)))
        #expect(!interaction.contains(CGPoint(x: 20, y: 20)))

        // AppKit can reposition a popover onto another edge. Query its current
        // frame, including negative screen origins, rather than a cached guess.
        surface.anchorFrame = CGRect(x: -240, y: 125, width: 20, height: 20)
        surface.frame       = CGRect(x: -460, y: 100, width: 180, height: 80)
        #expect(interaction.contains(CGPoint(x: -260, y: 135)))
        #expect(!interaction.contains(CGPoint(x: -260, y: 160)))
        #expect(!interaction.contains(CGPoint(x: 320, y: 20)))
    }

    @Test(.timeLimit(.minutes(1)))
    func stationaryExitExpiresOnceAndReleasesContent() async {
        let surface     = AuxiliaryPopoverFixture()
        let interaction = makeInteraction()
        var dismissals  = 0
        interaction.present(using: surface) { NSViewController() }
        await surface.waitUntilShown()
        let releasedContent = { [weak content = surface.content] in content }

        let outside = CGPoint(x: 600, y: 20)
        // The timer's callback is the event under test. Sleeping for a guessed
        // duration races the other suites sharing AppKit's main actor.
        await withCheckedContinuation { continuation in
            interaction.onDismiss = {
                dismissals += 1
                if dismissals == 1 { continuation.resume() }
            }
            interaction.updatePointer(at: outside)
            #expect(interaction.contains(outside))
            interaction.updatePointer(at: outside)
        }

        #expect(!interaction.isActive)
        #expect(!interaction.contains(outside))
        #expect(dismissals == 1)
        #expect(surface.closeCount == 1)
        #expect(releasedContent() == nil)
        interaction.dismiss()
        #expect(dismissals == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func reentryCancelsTheExitDeadline() async {
        let surface     = AuxiliaryPopoverFixture()
        let interaction = makeInteraction()
        interaction.present(using: surface) { NSViewController() }
        await surface.waitUntilShown()
        defer { interaction.dismiss() }

        interaction.updatePointer(at: CGPoint(x: 600, y: 20))
        interaction.updatePointer(at: CGPoint(x: 220, y: 90))
        #expect(interaction.isActive)
        #expect(!interaction.contains(CGPoint(x: 600, y: 20)))
        #expect(surface.closeCount == 0)

        // A later exit must still expire after the first deadline was revoked.
        // Await delivery rather than assuming when the main actor will run it.
        await withCheckedContinuation { continuation in
            interaction.onDismiss = {
                interaction.onDismiss = nil
                continuation.resume()
            }
            interaction.updatePointer(at: CGPoint(x: 600, y: 20))
        }
        #expect(!interaction.isActive)
        #expect(surface.closeCount == 1)
    }

    @Test
    func replacementCannotBeOverwrittenByAnOlderAsyncRequest() async {
        let previous    = AuxiliaryPopoverFixture()
        let replacement = AuxiliaryPopoverFixture()
        let content     = AuxiliaryContentGate()
        let interaction = makeInteraction()
        interaction.present(using: previous) { await content.wait() }
        await content.waitUntilRequested()

        interaction.present(using: replacement) { NSViewController() }
        await replacement.waitUntilShown()
        content.resume()
        await content.waitUntilReturned()
        defer { interaction.dismiss() }
        #expect(interaction.isActive)
        #expect(previous.showCount == 0)
        #expect(previous.closeCount == 1)
        #expect(replacement.showCount == 1)
        #expect(replacement.closeCount == 0)
    }

    @Test
    func activityCallbackSpansReplacementAndEndsOnDismissal() {
        let interaction = makeInteraction()
        let first = AuxiliaryPopoverFixture()
        let replacement = AuxiliaryPopoverFixture()
        var changes: [Bool] = []
        interaction.onActiveChanged = { changes.append($0) }

        interaction.present(using: first) { nil }
        interaction.present(using: replacement) { nil }
        #expect(changes == [true])

        interaction.dismiss()
        #expect(changes == [true, false])
    }

    @Test
    func detachedAnchorCannotPresentLateContent() async {
        let surface     = AuxiliaryPopoverFixture()
        let content     = AuxiliaryContentGate()
        let interaction = makeInteraction()
        interaction.present(using: surface) { await content.wait() }
        await content.waitUntilRequested()
        surface.anchorFrame = nil
        content.resume()
        await content.waitUntilReturned()
        #expect(!interaction.isActive)
        #expect(surface.showCount == 0)
        #expect(surface.closeCount == 1)
    }

    @Test
    func failedPresentationEndsTheSession() async {
        let surface     = AuxiliaryPopoverFixture()
        let interaction = makeInteraction()
        surface.canShow = false
        interaction.present(using: surface) { NSViewController() }
        await surface.waitUntilShown()
        #expect(!interaction.isActive)
        #expect(surface.closeCount == 1)
    }

    @Test(
        .serialized,
        .timeLimit(.minutes(1)),
        arguments: ["MacBook Pro", "Studio output with a considerably longer device name"]
    )
    func nativePopoverPreservesFittingSizeAndOwnsItsWindow(deviceName: String) async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let frame = CGRect(
            x     : screen.visibleFrame.midX - 300,
            y     : screen.visibleFrame.midY,
            width : 600,
            height: 220
        )
        let window = NSPanel(
            contentRect: frame,
            styleMask  : [.borderless, .nonactivatingPanel],
            backing    : .buffered,
            defer      : false
        )
        window.isReleasedWhenClosed = false
        let host = NotchHostView(frame: CGRect(origin: .zero, size: frame.size))
        window.contentView = host
        host.apply(
            geometry: NotchGeometry(
                leftExtent        : 180,
                rightExtent       : 180,
                height            : 120,
                bottomCornerRadius: 18,
                topCornerRadius   : 6
            ),
            centerX        : 300,
            topY           : 220,
            isChromeVisible: true
        )
        let anchor = NSButton(frame: CGRect(x: 390, y: 115, width: 24, height: 24))
        host.addSubview(anchor)
        window.orderFrontRegardless()

        let presenter = NotchPopoverPresenter()
        defer {
            presenter.dismiss()
            window.close()
        }
        let stack = NSStackView(views: [
            NSTextField(labelWithString: "Mac audio output"),
            NSTextField(labelWithString: deviceName)
        ])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 4
        stack.edgeInsets  = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        let content = NSViewController()
        content.view = stack
        stack.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        #expect(fitting.width > 0)
        #expect(fitting.height > 0)

        let shown = await showNativePopover(
            presenter  : presenter,
            anchor     : anchor,
            content    : content,
            interaction: host.auxiliaryInteraction
        )
        let popover = try #require(shown)
        let popupWindow = try #require(content.view.window)
        #expect(popupWindow !== window)
        #expect(popover.isShown)
        #expect(abs(popover.contentSize.width - fitting.width) < 1)
        #expect(abs(popover.contentSize.height - fitting.height) < 1)

        // Use only the window reached through this content controller. Keeping
        // the popup's center cancels any opening grace before exclusion checks.
        let popupPoint = CGPoint(x: popupWindow.frame.midX, y: popupWindow.frame.midY)
        host.auxiliaryInteraction.updatePointer(at: popupPoint)
        #expect(host.auxiliaryInteraction.contains(popupPoint))
        #expect(host.auxiliaryInteraction.isActive)
        let unusedCanvas = window.convertPoint(toScreen: CGPoint(x: 5, y: 5))
        #expect(!host.auxiliaryInteraction.contains(unusedCanvas))

        presenter.dismiss()
        #expect(!popover.isShown)
        #expect(popover.contentViewController == nil)
        #expect(!host.auxiliaryInteraction.isActive)
        #expect(!presenter.isPresented)
    }

    /// showNativePopover awaits AppKit's actual did-show notification, filtered
    /// to the supplied content. Failure also resumes the waiter via onDismiss.
    private func showNativePopover(
        presenter  : NotchPopoverPresenter,
        anchor     : NSView,
        content    : NSViewController,
        interaction: NotchAuxiliaryInteraction
    ) async -> NSPopover? {
        var observer: NSObjectProtocol?
        defer {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            interaction.onDismiss = nil
        }
        return await withCheckedContinuation { continuation in
            var didFinish = false
            observer = NotificationCenter.default.addObserver(
                forName: NSPopover.didShowNotification,
                object : nil,
                queue  : .main
            ) { notification in
                MainActor.assumeIsolated {
                    guard !didFinish,
                          let popover = notification.object as? NSPopover,
                          popover.contentViewController === content else { return }
                    didFinish = true
                    continuation.resume(returning: popover)
                }
            }
            interaction.onDismiss = {
                guard !didFinish else { return }
                didFinish = true
                continuation.resume(returning: nil)
            }
            let started = presenter.present(from: anchor) { content }
            if !started, !didFinish {
                didFinish = true
                continuation.resume(returning: nil)
            }
            if let window = anchor.window {
                let center = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
                interaction.updatePointer(at: window.convertPoint(toScreen: anchor.convert(center, to: nil)))
            }
        }
    }

    private func makeInteraction() -> NotchAuxiliaryInteraction {
        NotchAuxiliaryInteraction(
            leaveGrace     : .milliseconds(30),
            pointerLocation: { CGPoint(x: 220, y: 135) }
        )
    }
}
