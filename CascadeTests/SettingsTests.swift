//
//  SettingsTests.swift
//  Cascade
//

import AppKit
import CascadeKit
import Testing
@testable import Cascade

struct SettingsTests {
    @MainActor
    @Test
    func nativeSettingsPresentationKeepsItsInitialSizeAndAnchor() throws {
        let screen = try #require(NSScreen.main)
        let notch = CGRect(x: screen.frame.midX - 220, y: screen.frame.maxY - 144, width: 440, height: 144)
        var presentationChanges: [Bool] = []
        let presenter = CascadeSettingsWindowController(
            onFocusChanged       : { _ in },
            onPresentationChanged: { presentationChanges.append($0) }
        )
        let services = CascadeServices()
        presenter.show(services: services, notchFrame: notch)
        let window = try #require(presenter.window)
        #expect(window.frame.width == min(760, screen.visibleFrame.width))
        #expect(window.frame.height >= min(570, notch.minY - 8 - screen.visibleFrame.minY))
        #expect(abs(window.frame.midX - screen.frame.midX) < 1)
        #expect(window.frame.maxY <= notch.minY - 8)

        presenter.updateNotchFrame(nil)
        #expect(window.isVisible)
        presenter.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        #expect(presentationChanges == [true])
        presenter.close()
        #expect(presentationChanges == [true, false])
    }

    @MainActor
    @Test
    func spotlightPreviewUsesTheProvidedAnchorAndReleasesItsReservation() throws {
        let screen = try #require(NSScreen.main)
        let bounds = CGRect(x: screen.frame.midX - 48, y: screen.frame.maxY - 8, width: 96, height: 8)
        let droplet = RecordingSpotlightDroplet()
        var reservedAnchor: SpotlightDisplayAnchor?
        var ready: (() -> Void)?
        var releaseCount = 0
        let coordinator = SpotlightCoordinator(
            droplet: droplet,
            anchor : {
                SpotlightDisplayAnchor(
                    displayID    : screen.cascadeRuntimeDisplayID,
                    screen       : screen,
                    restingBounds: bounds
                )
            },
            reservePresentation: { anchor, completion in
                reservedAnchor = anchor
                ready = completion
            },
            releasePresentation: { releaseCount += 1 }
        )

        coordinator.preview()
        #expect(reservedAnchor?.restingBounds == bounds)
        #expect(droplet.previewAnchor == nil)
        ready?()
        #expect(droplet.previewAnchor?.restingBounds == bounds)
        #expect(releaseCount == 0)
        droplet.finishPreview()
        #expect(releaseCount == 1)
    }

    @MainActor
    @Test
    func nativeCloseIntentRetainsReservationUntilNativeClosure() async throws {
        let screen = try #require(NSScreen.main)
        let anchor = SpotlightDisplayAnchor(
            displayID    : screen.cascadeRuntimeDisplayID,
            screen       : screen,
            restingBounds: CGRect(x: screen.frame.midX - 48, y: screen.frame.maxY - 8, width: 96, height: 8)
        )
        let droplet = RecordingSpotlightDroplet()
        var releaseCount = 0
        let coordinator = SpotlightCoordinator(
            droplet            : droplet,
            anchor             : { anchor },
            reservePresentation: { _, ready in ready() },
            releasePresentation: { releaseCount += 1 }
        )
        coordinator.preview()

        coordinator.cancelFromShortcut(nativeClosing: true)
        await Task.yield()
        #expect(releaseCount == 0)

        coordinator.completeNativeClosure()
        #expect(releaseCount == 1)
    }

    @MainActor
    @Test
    func screenLockCancelsAPendingPreviewWithoutLateReplay() throws {
        let screen = try #require(NSScreen.main)
        let anchor = SpotlightDisplayAnchor(
            displayID    : screen.cascadeRuntimeDisplayID,
            screen       : screen,
            restingBounds: CGRect(x: screen.frame.midX - 48, y: screen.frame.maxY - 8, width: 96, height: 8)
        )
        let droplet = RecordingSpotlightDroplet()
        var ready: (() -> Void)?
        var releaseCount = 0
        let coordinator = SpotlightCoordinator(
            droplet            : droplet,
            anchor             : { anchor },
            reservePresentation: { _, completion in ready = completion },
            releasePresentation: { releaseCount += 1 }
        )
        coordinator.preview()

        coordinator.screenLocked()
        ready?()

        #expect(releaseCount == 1)
        #expect(droplet.previewAnchor == nil)
        #expect(droplet.cancelCount == 1)
    }

    @MainActor
    @Test
    func globalAndSettingsCommandsResolveDifferentInvocationDisplays() {
        #expect(AuxiliaryInvocationOrigin.global.resolve(
            settingsDisplayID: 20,
            activeDisplayID  : 10
        ) == 10)
        #expect(AuxiliaryInvocationOrigin.settings.resolve(
            settingsDisplayID: 20,
            activeDisplayID  : 10
        ) == 20)
        #expect(AuxiliaryInvocationOrigin.settings.resolve(
            settingsDisplayID: nil,
            activeDisplayID  : 10
        ) == 10)
    }

    @MainActor
    @Test
    func realOpeningPreemptsADevPreviewWithoutReleasingItsReservation() async throws {
        let fixture = try SpotlightCoordinatorFixture()
        fixture.coordinator.preview()
        #expect(fixture.droplet.previewCount == 1)

        fixture.coordinator.open()
        await Task.yield()

        #expect(fixture.droplet.cancelCount == 1)
        #expect(fixture.droplet.playCount == 1)
        #expect(fixture.releaseCount == 0)
        fixture.droplet.finishPreview()
        #expect(fixture.releaseCount == 0)
    }

    @MainActor
    @Test
    func openingWithoutAShortcutLeavesTheDevPreviewCompletable() throws {
        let fixture = try SpotlightCoordinatorFixture(
            hasShortcut     : false,
            initiallyEnabled: true
        )

        verifyIneligibleOpeningKeepsPreview(fixture)
    }

    @MainActor
    @Test
    func openingWhileDisabledLeavesTheDevPreviewCompletable() throws {
        let fixture = try SpotlightCoordinatorFixture(initiallyEnabled: false)

        verifyIneligibleOpeningKeepsPreview(fixture)
    }

    @MainActor
    @Test
    func shortcutCancellationRecoversWhenNativeOpeningNeverAppears() async throws {
        let fixture = try SpotlightCoordinatorFixture(handoffTimeout: .milliseconds(10))

        #expect(fixture.coordinator.handle(type: .keyDown, event: fixture.shortcutEvent()))
        await Task.yield()
        fixture.droplet.finishPlay()
        fixture.coordinator.receive(SpotlightWindowSnapshot(
            generation: 1,
            processID: fixture.processID,
            isVisible: false,
            isFocused: false,
            isSettled: false,
            isReady: false,
            frame: nil
        ))
        #expect(fixture.tap.nativeInvocationCount == 1)

        #expect(fixture.coordinator.handle(type: .keyDown, event: fixture.shortcutEvent()))
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.releaseCount == 1)

        #expect(fixture.coordinator.handle(type: .keyDown, event: fixture.shortcutEvent()))
        await Task.yield()
        #expect(fixture.droplet.playCount == 2)
    }

    @MainActor
    @Test
    func cancellationKeepsAnObservedNativeWindowReservedUntilHidden() async throws {
        let fixture = try SpotlightCoordinatorFixture(handoffTimeout: .milliseconds(10))

        #expect(fixture.coordinator.handle(type: .keyDown, event: fixture.shortcutEvent()))
        await Task.yield()
        fixture.droplet.finishPlay()
        fixture.coordinator.receive(SpotlightWindowSnapshot(
            generation: 1,
            processID: fixture.processID,
            isVisible: false,
            isFocused: false,
            isSettled: false,
            isReady: false,
            frame: nil
        ))
        #expect(fixture.coordinator.handle(type: .keyDown, event: fixture.shortcutEvent()))
        fixture.coordinator.receive(SpotlightWindowSnapshot(
            generation: 2,
            processID: fixture.processID,
            isVisible: true,
            isFocused: false,
            isSettled: false,
            isReady: false,
            frame: nil
        ))

        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.releaseCount == 0)

        fixture.coordinator.receive(SpotlightWindowSnapshot(
            generation: 2,
            processID: fixture.processID,
            isVisible: false,
            isFocused: false,
            isSettled: false,
            isReady: false,
            frame: nil
        ))
        #expect(fixture.releaseCount == 1)
    }

    @MainActor
    @Test
    func openingWatchdogKeepsAnObservedNativeWindowReservedUntilHidden() async throws {
        let fixture = try SpotlightCoordinatorFixture(handoffTimeout: .milliseconds(10))

        #expect(fixture.coordinator.handle(type: .keyDown, event: fixture.shortcutEvent()))
        await Task.yield()
        fixture.droplet.finishPlay()
        fixture.coordinator.receive(SpotlightWindowSnapshot(
            generation: 1,
            processID: fixture.processID,
            isVisible: false,
            isFocused: false,
            isSettled: false,
            isReady: false,
            frame: nil
        ))
        fixture.coordinator.receive(SpotlightWindowSnapshot(
            generation: 1,
            processID: fixture.processID,
            isVisible: true,
            isFocused: false,
            isSettled: false,
            isReady: false,
            frame: nil
        ))

        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.releaseCount == 0)

        fixture.coordinator.receive(SpotlightWindowSnapshot(
            generation: 1,
            processID: fixture.processID,
            isVisible: false,
            isFocused: false,
            isSettled: false,
            isReady: false,
            frame: nil
        ))
        #expect(fixture.releaseCount == 1)
    }

    @MainActor
    private func verifyIneligibleOpeningKeepsPreview(_ fixture: SpotlightCoordinatorFixture) {
        fixture.coordinator.preview()
        #expect(fixture.droplet.previewCount == 1)

        fixture.coordinator.open()

        #expect(fixture.droplet.cancelCount == 0)
        #expect(fixture.droplet.playCount == 0)
        fixture.droplet.finishPreview()
        #expect(fixture.releaseCount == 1)

        fixture.coordinator.preview()
        #expect(fixture.droplet.previewCount == 2)
        fixture.droplet.finishPreview()
        #expect(fixture.releaseCount == 2)
    }

    @Test
    func draggingOrZoomingCannotCoverTheExpandedNotch() {
        let frame = SettingsWindowPlacement.constrain(
            CGRect(x: -200, y: 0, width: 1_500, height: 1_000),
            below : CGRect(x: 280, y: 656, width: 440, height: 144),
            within: CGRect(x: 0, y: 40, width: 1_000, height: 730)
        )
        #expect(frame == CGRect(x: 0, y: 40, width: 1_000, height: 608))
    }

    @Test
    func aWindowBelowTheNotchKeepsItsChosenPosition() {
        let proposed = CGRect(x: 100, y: 70, width: 760, height: 500)
        let frame = SettingsWindowPlacement.constrain(
            proposed,
            below : CGRect(x: 280, y: 656, width: 440, height: 144),
            within: CGRect(x: 0, y: 40, width: 1_000, height: 730)
        )
        #expect(frame == proposed)
    }

    @Test
    func movingToAnotherDisplayUsesThatDisplaysCoordinates() {
        let frame = SettingsWindowPlacement.constrain(
            CGRect(x: 100, y: 800, width: 760, height: 500),
            below : CGRect(x: -720, y: 856, width: 440, height: 144),
            within: CGRect(x: -1_000, y: 240, width: 1_000, height: 730)
        )
        #expect(frame == CGRect(x: -760, y: 348, width: 760, height: 500))
    }

    @MainActor
    @Test
    func searchFindsControlsByDescriptionAndPageAcrossWhitespace() {
        #expect(CascadeSetting.music.matches(" spotify "))
        #expect(CascadeSetting.bluetoothPreview.matches("Dev earbuds"))
        #expect(!CascadeSetting.bluetooth.matches("Dev earbuds"))
        #expect(CascadeSetting.haptics.matches("trackpad\nfeedback"))
        #expect(CascadeSetting.displayStyle.matches("screen notch"))
        #expect(CascadeSetting.displayStyle.matches("display Dynamic Island"))
        #expect(CascadeSetting.displayStyle.matches("style"))
        #expect(CascadeSetting.activityDisplays.matches("activities displays"))
        #expect(CascadeSetting.activityDisplays.matches("activity"))
        #expect(!CascadeSetting.music.matches("nonexistent"))
    }

    @MainActor
    @Test
    func displayPreferencesPersistAsTheSingleServiceValue() throws {
        let suite = "Cascade.SettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let display = DisplayIdentity(rawValue: "offline-display")
        let expected = DisplayPresentationPreferences(
            activityMode: .fixedDisplay(display),
            styles      : [display: .dynamicIsland]
        )

        let services = CascadeServices(preferences: defaults)
        services.displayPreferences = expected

        let restored = CascadeServices(preferences: defaults)
        #expect(restored.displayPreferences == expected)
    }

    @Test
    func fixedOfflineDisplayAndDuplicateNamesRemainDistinct() {
        let first = DisplayIdentity(rawValue: "first-uuid")
        let second = DisplayIdentity(rawValue: "second-uuid")
        let offline = DisplayIdentity(rawValue: "offline-uuid")
        let choices = DisplaySettingsModel.activityDisplayChoices(
            displays: [
                NotchDisplayDescriptor(
                    runtimeID      : 10,
                    identity       : first,
                    name           : "Studio Display",
                    hasHardwareNotch: false
                ),
                NotchDisplayDescriptor(
                    runtimeID      : 20,
                    identity       : second,
                    name           : "Studio Display",
                    hasHardwareNotch: false
                ),
            ],
            selected: offline
        )

        #expect(choices.map(\.identity) == [first, second, offline])
        #expect(choices.map(\.accessibilityLabel).uniqueCount == 3)
        #expect(choices.last?.isConnected == false)
    }
}

private extension Collection where Element: Hashable {
    var uniqueCount: Int { Set(self).count }
}
