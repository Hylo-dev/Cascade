//
//  NotchControllerTests.swift
//  CascadeKitTests
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct NotchControllerTests {

    @Test
    func softwareRestAndCompactActivityUseIndependentBoundsAndCenterGap() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        let display = fixture.resolver.display
        fixture.resolver.display = ActiveDisplay(
            displayID   : display.displayID,
            frame       : display.frame,
            backingScale: display.backingScale,
            notch       : .absent
        )
        fixture.controller.start()
        defer { fixture.controller.stop() }
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)

        #expect(shape.path?.boundingBoxOfPath.size == CGSize(width: 96, height: 8))
        #expect(fixture.controller.restingFrame == CGRect(x: 452, y: 792, width: 96, height: 8))

        let activity = ControllerActivityFixture(id: "software-compact")
        fixture.controller.present(activity)
        #expect(activity.compactLeadingContexts.last?.availableSize == CGSize(width: 50, height: 20))
        #expect(activity.compactTrailingContexts.last?.availableSize == CGSize(width: 50, height: 20))
        #expect(shape.path?.boundingBoxOfPath.height == 32)

        let hosts = fixture.hostView.subviews.flatMap(\.subviews)
            .compactMap { $0 as? NSHostingView<AnyView> }
            .filter { !$0.isHidden }
            .sorted { $0.frame.minX < $1.frame.minX }
        #expect(hosts.count == 2)
        #expect(hosts[1].frame.minX - hosts[0].frame.maxX == 24)
    }

    @Test
    func softwareExpandedActivityHasNoHardwareReservationAndMatchesBothStyles() throws {
        var bounds = [CGRect]()
        for style in [ExternalNotchStyle.notch, .dynamicIsland] {
            let fixture = ControllerFixture(reducesMotion: true, style: style)
            let display = fixture.resolver.display
            fixture.resolver.display = ActiveDisplay(
                displayID   : display.displayID,
                frame       : display.frame,
                backingScale: display.backingScale,
                notch       : .absent
            )
            let activity = ControllerActivityFixture(
                id                   : "software-live",
                expandedContentHeight: 40
            )
            fixture.controller.present(activity)
            fixture.controller.start()
            fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
            let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
            bounds.append(try #require(shape.path?.boundingBoxOfPath))
            #expect(activity.expandedContexts.last?.hardwareNotchWidth == 0)
            #expect(activity.expandedContexts.last?.availableSize.height == 40)
            fixture.controller.stop()
        }

        #expect(bounds[0] == bounds[1])
    }

    @Test(arguments: [ExternalNotchStyle.notch, .dynamicIsland])
    func noLiveExpansionUsesTheSelectedSoftwareShape(style: ExternalNotchStyle) throws {
        let fixture = ControllerFixture(reducesMotion: true, style: style)
        let display = fixture.resolver.display
        fixture.resolver.display = ActiveDisplay(
            displayID   : display.displayID,
            frame       : display.frame,
            backingScale: display.backingScale,
            notch       : .absent
        )
        fixture.controller.register(ControllerWidgetFixture())
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        let path = try #require(shape.path)

        #expect(path.boundingBoxOfPath.height == (style == .dynamicIsland ? 160 : 144))
        #expect(path.contains(fixture.point(x: 500, belowTop: 1)))
    }

    @Test
    func expandedFallbackUsesDropletWithoutPretendingItIsALiveSession() throws {
        let fixture = ControllerFixture(reducesMotion: true, style: .dynamicIsland)
        let display = fixture.resolver.display
        fixture.resolver.display = ActiveDisplay(
            displayID   : display.displayID,
            frame       : display.frame,
            backingScale: display.backingScale,
            notch       : .absent
        )
        let fallback = ControllerActivityFixture(id: "fallback")
        fixture.controller.setExpandedFallback(fallback)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)

        #expect(shape.path?.boundingBoxOfPath.height == 124)
        #expect(fallback.expandedContexts.last?.hardwareNotchWidth == 0)
        #expect(fallback.expandedContexts.last?.availableSize.height == 88)
    }

    @Test(arguments: [CGFloat(1), CGFloat(2)])
    func narrowSoftwareDisplayKeepsEveryAnimatedDropletFrameInsideTheCanvas(
        scale: CGFloat
    ) throws {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph, style: .dynamicIsland)
        fixture.resolver.display = ActiveDisplay(
            displayID   : 42,
            frame       : CGRect(x: -180, y: 100, width: 180, height: 500),
            backingScale: scale,
            notch       : .absent
        )
        fixture.controller.register(ControllerWidgetFixture())
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: -90, y: 599))
        while morph.isRunning {
            morph.tick()
            try assertSoftwarePathConsumersMatch(fixture)
        }
    }

    @Test
    func interruptedSoftwareOpeningAndClosingKeepOnePathForChromeMaskAndHitTesting() throws {
        let morph = RecordingMorphEngine()
        let fixture = softwareFixture(morph: morph, style: .dynamicIsland)
        fixture.controller.register(ControllerWidgetFixture())
        fixture.controller.start()
        defer { fixture.controller.stop() }

        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        for _ in 0..<8 {
            morph.tick()
            try assertSoftwarePathConsumersMatch(fixture)
        }
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 400))
        for _ in 0..<8 {
            morph.tick()
            try assertSoftwarePathConsumersMatch(fixture)
        }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        while morph.isRunning {
            morph.tick()
            try assertSoftwarePathConsumersMatch(fixture)
        }

        #expect(fixture.controller.state == .open)
    }

    @Test
    func styleEditClosesWithTheOldShapeBeforeApplyingTheLatestStyle() throws {
        let morph = RecordingMorphEngine()
        let fixture = softwareFixture(morph: morph, style: .notch)
        fixture.controller.register(ControllerWidgetFixture())
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        morph.settle()
        #expect(try softwareShape(in: fixture).boundingBoxOfPath.height == 144)

        fixture.controller.setStyle(.dynamicIsland)
        #expect(fixture.controller.state == .closed)
        #expect(try softwareShape(in: fixture).boundingBoxOfPath.height == 144)
        morph.tick()
        try assertSoftwarePathConsumersMatch(fixture)

        // The last preference wins even when it returns to the outgoing style.
        fixture.controller.setStyle(.notch)
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        morph.settle()
        #expect(try softwareShape(in: fixture).boundingBoxOfPath.height == 144)

        fixture.controller.setStyle(.dynamicIsland)
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        morph.settle()
        #expect(try softwareShape(in: fixture).boundingBoxOfPath.height == 160)
        try assertSoftwarePathConsumersMatch(fixture)
    }

    @Test
    func liveArrivalAndEndInvalidateSettledDropletWithoutDivergingContentAndMask() throws {
        let morph = RecordingMorphEngine()
        let fixture = softwareFixture(morph: morph, style: .dynamicIsland)
        fixture.controller.register(ControllerWidgetFixture())
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        morph.settle()
        #expect(try softwareShape(in: fixture).boundingBoxOfPath.height == 160)

        let activity = ControllerActivityFixture(id: "arrival", expandedContentHeight: 94)
        fixture.controller.present(activity)
        #expect(try softwareShape(in: fixture).boundingBoxOfPath.height == 144)
        let expandedHost = try #require(fixture.hostView.subviews.flatMap(\.subviews)
            .compactMap { $0 as? NSHostingView<AnyView> }
            .first { !$0.isHidden && $0.frame.height == 114 })
        #expect(expandedHost.frame.maxY == fixture.hostView.bounds.maxY)
        try assertSoftwarePathConsumersMatch(fixture)

        fixture.controller.endActivity(id: activity.id)
        let endingHeight = try softwareShape(in: fixture).boundingBoxOfPath.height
        #expect(endingHeight == 144)
        while morph.isRunning {
            morph.tick()
            try assertSoftwarePathConsumersMatch(fixture)
        }
        #expect(try softwareShape(in: fixture).boundingBoxOfPath.height == 160)
        #expect(fixture.controller.state == .open)
        let settingsButton = try #require(fixture.hostView.subviews.flatMap(\.subviews)
            .compactMap { $0 as? NSButton }
            .first)
        #expect(settingsButton.frame.maxY == fixture.hostView.bounds.maxY - 16)
    }

    @Test
    func retainedLiveOwnerClosesWithActivityGeometryAfterCompactRoutingMovesAway() throws {
        let morph = RecordingMorphEngine()
        let fixture = softwareFixture(morph: morph, style: .dynamicIsland)
        let activity = ControllerActivityFixture(id: "retained-owner", expandedContentHeight: 94)
        fixture.controller.present(activity)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 799))
        morph.settle()

        fixture.controller.simulateCompactRoutingMovedAwayWhileRetainingExpanded(activity)
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 400))
        #expect(fixture.controller.state == .closed)
        while morph.isRunning {
            morph.tick()
            let path = try softwareShape(in: fixture)
            #expect(path.boundingBoxOfPath.height <= 144)
            try assertSoftwarePathConsumersMatch(fixture)
        }
    }

    private func softwareFixture(
        morph: RecordingMorphEngine,
        style: ExternalNotchStyle
    ) -> ControllerFixture {
        let fixture = ControllerFixture(morphEngine: morph, style: style)
        let display = fixture.resolver.display
        fixture.resolver.display = ActiveDisplay(
            displayID   : display.displayID,
            frame       : display.frame,
            backingScale: display.backingScale,
            notch       : .absent
        )
        return fixture
    }

    private func softwareShape(in fixture: ControllerFixture) throws -> CGPath {
        let layer = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        return try #require(layer.path)
    }

    private func assertSoftwarePathConsumersMatch(_ fixture: ControllerFixture) throws {
        let path = try softwareShape(in: fixture)
        let mask = try #require(fixture.hostView.subviews.compactMap {
            $0.layer?.mask as? CAShapeLayer
        }.first?.path)
        #expect(mask == path)
        let bounds = path.boundingBoxOfPath
        #expect(bounds.minX >= fixture.hostView.bounds.minX)
        #expect(bounds.maxX <= fixture.hostView.bounds.maxX)
        #expect(bounds.minY >= fixture.hostView.bounds.minY)
        #expect(bounds.maxY <= fixture.hostView.bounds.maxY)
        let sample = CGPoint(x: bounds.midX, y: bounds.midY)
        #expect(fixture.hostView.containsInteractivePoint(sample) == path.contains(sample))
    }

    @Test(arguments: [NotchActivityPrivacy.standard, .sensitive])
    func activityBackgroundLetsExpandedGlassShowThrough(privacy: NotchActivityPrivacy) throws {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.present(ControllerActivityFixture(id: "music", privacy: privacy))
        fixture.controller.start()
        defer { fixture.controller.stop() }

        for isExpanded in [false, true] {
            if isExpanded { fixture.monitor.sendPointer(CGPoint(x: 500, y: 790)) }
            let hosts = fixture.hostView.subviews.flatMap(\.subviews)
                .compactMap { $0 as? NSHostingView<AnyView> }
                .filter { !$0.isHidden }
            #expect(!hosts.isEmpty)
            for host in hosts {
                // Render the actual root supplied by the controller, including
                // its shared wrapper or privacy placeholder. Sample an inset
                // corner away from the fixture's centered text and controls.
                let renderer = ImageRenderer(content: host.rootView.frame(
                    width: host.bounds.width, height: host.bounds.height
                ))
                let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                let alpha = try #require(bitmap.colorAt(x: 1, y: 1)).alphaComponent
                #expect(alpha == (isExpanded ? 0 : 1))
            }
        }
    }

    @Test(arguments: [0, 1, 2])
    func glassIsReservedForExpansion(activityCount: Int) throws {
        guard #available(macOS 26, *),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return }
        let fixture = ControllerFixture(reducesMotion: true)
        for index in 0..<activityCount {
            fixture.controller.present(ControllerActivityFixture(
                id      : "activity-\(index)",
                sourceID: "source-\(index)"
            ))
        }
        fixture.controller.start()
        defer { fixture.controller.stop() }
        let backing = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)

        #expect(fixture.controller.state == .closed)
        #expect(!backing.isHidden)

        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(fixture.controller.state == .open)
        #expect(backing.isHidden)

        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        #expect(fixture.controller.state == .closed)
        #expect(!backing.isHidden)
    }

    @Test(arguments: [false, true])
    func closureReboundsOutwardAfterTouchingHardware(hasActivity: Bool) throws {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        if hasActivity {
            fixture.controller.present(ControllerActivityFixture(id: "music"))
        }
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        fixture.controller.setSettingsFocused(true)
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 400))
        fixture.controller.setSettingsFocused(false)

        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        var touchedHardware = false
        var reboundHeight: CGFloat = 0
        for _ in 0..<240 where morph.isRunning {
            morph.tick()
            let bounds = try #require(shape.path?.boundingBoxOfPath)
            #expect(bounds.height >= 30)
            #expect(bounds.width >= 200)
            if bounds.height == 30 { touchedHardware = true }
            if touchedHardware { reboundHeight = max(reboundHeight, bounds.height - 30) }
        }

        #expect(touchedHardware)
        #expect(reboundHeight > 2)
        #expect(reboundHeight < 12)
        #expect(shape.path?.boundingBoxOfPath.height == 30)
        #expect(!morph.isRunning)
    }

    @Test
    func settingsGearWorksAboveExpandedActivitiesAndHidesWhenClosed() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        var requests = 0
        fixture.hostView.onSettingsRequested = { requests += 1 }
        fixture.controller.present(ControllerActivityFixture(id: "music"))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        let button = try #require(fixture.hostView.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }.first)
        #expect(button.isHidden)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(!button.isHidden)
        #expect(button.frame.minX >= 600)
        #expect(button.frame.maxY <= fixture.hostView.bounds.maxY)
        let buttonCenter = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        let hitPoint = button.convert(buttonCenter, to: fixture.hostView.superview)
        #expect(fixture.hostView.hitTest(hitPoint) === button)
        #expect(button.sendAction(button.action, to: button.target))
        #expect(requests == 1)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 400))
        #expect(button.isHidden)
    }

    @Test
    func settingsFocusKeepsNotchOpenUntilFocusLeavesWithPointerOutside() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.controller.setSettingsFocused(true)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 400))
        #expect(fixture.controller.state == .open)
        fixture.controller.setSettingsFocused(false)
        #expect(fixture.controller.state == .closed)
    }

    @Test
    func cancelledExternalSearchRestoresTheFocusedSettingsNotch() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.controller.setSettingsFocused(true)
        fixture.controller.setExternalSurfacePresented(true)
        #expect(fixture.controller.state == .closed)
        fixture.controller.setExternalSurfacePresented(false)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 400))
        #expect(fixture.controller.state == .open)
    }

    @Test
    func settingsFocusDoesNotCollapseChromeWhenTheActivityChanges() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.present(ControllerActivityFixture(id: "old"))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        fixture.controller.setSettingsFocused(true)
        morph.settle()
        fixture.controller.endActivity(id: "old")
        fixture.controller.present(ControllerActivityFixture(id: "new"))
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 400))
        #expect(fixture.controller.state == .open)
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 500, belowTop: 80)))
    }

    @Test
    func lockingClearsSettingsFocusBeforeUnlock() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.controller.setSettingsFocused(true)
        fixture.monitor.sendLock()
        #expect(fixture.controller.state == .closed)
        fixture.monitor.sendUnlock()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 400))
        #expect(fixture.controller.state == .closed)
    }

    @Test
    func settingsAnchorTracksExpandedActivityHeightAndDisplayOrigin() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.present(ControllerActivityFixture(id: "tall", expandedContentHeight: 94))
        fixture.resolver.display = ActiveDisplay(
            displayID   : 42,
            frame       : CGRect(x: -1_000, y: 200, width: 1_000, height: 800),
            backingScale: 2,
            notch       : HardwareNotch(isPresent: true, size: CGSize(width: 200, height: 30))
        )
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.controller.setSettingsFocused(true)
        let initial = try #require(fixture.controller.expandedFrame)
        #expect(initial.midX == -500)
        #expect(initial.minY == 856)
        fixture.controller.present(ControllerActivityFixture(id: "tall", contentRevision: 1, expandedContentHeight: 190))
        let expanded = try #require(fixture.controller.expandedFrame)
        #expect(expanded.minY == 760)
        fixture.monitor.sendLock()
        #expect(fixture.controller.expandedFrame == nil)
    }

    @Test
    func pendingHoverCancelsWhenPointerLeavesBeforeOwnershipIsGranted() throws {
        let fixture = ControllerFixture(reducesMotion: true, autoGrantExpansions: false)
        fixture.controller.start()
        defer { fixture.controller.stop() }

        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        let request = try #require(fixture.controller.expansionRequests.last)
        #expect(request.trigger == .hover)
        #expect(fixture.controller.state == .closed)

        fixture.monitor.sendPointer(CGPoint(x: 700, y: 500))

        #expect(fixture.controller.cancelledExpansionGenerations == [request.generation])
        #expect(fixture.controller.expansionRequests.count == 1)
        #expect(fixture.controller.state == .closed)
    }

    @Test
    func externalSearchKeepsHoverClosedUntilTheNativeSurfaceDismisses() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        morph.settle()
        #expect(fixture.controller.state == .open)
        fixture.controller.setExternalSurfacePresented(true)
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(fixture.controller.state == .closed)
        fixture.controller.setExternalSurfacePresented(false)
        fixture.monitor.sendPointer(CGPoint(x: 300, y: 500))
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(fixture.controller.state == .open)
    }

    @Test
    func screenLockClearsExternalSuppressionBeforeUnlock() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.controller.setExternalSurfacePresented(true)

        fixture.monitor.sendLock()
        fixture.monitor.sendUnlock()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))

        #expect(fixture.controller.state == .open)
    }

    @Test
    func hoverDuringReplacementSelectsTheNewestActivityAtReveal() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.present(ControllerActivityFixture(id: "old"))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        let intermediate = ControllerActivityFixture(id: "intermediate")
        fixture.controller.present(intermediate)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        let latest = ControllerActivityFixture(id: "latest")
        fixture.controller.present(latest)
        morph.settle()
        #expect(intermediate.expandedContexts.isEmpty)
        #expect(latest.expandedContexts.count == 1)
        #expect(fixture.controller.state == .open)
    }

    @Test
    func anEndedExpandedActivityCanRevealANewArrivalAfterClosure() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.present(ControllerActivityFixture(id: "old"))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        morph.settle()
        fixture.controller.endActivity(id: "old")
        let latest = ControllerActivityFixture(id: "latest")
        fixture.controller.present(latest)
        #expect(latest.expandedContexts.isEmpty)
        morph.settle()
        #expect(latest.expandedContexts.count == 1)
        #expect(!morph.isRunning)
    }

    @Test
    func redactingDuringAttachmentReleasesThePreviousSatelliteContent() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.setSensitiveContentVisible(true)
        fixture.controller.present(ControllerActivityFixture(id: "primary", sourceID: "music", relevanceScore: 1))
        fixture.controller.present(ControllerActivityFixture(id: "secondary", sourceID: "timer", privacy: .sensitive, relevanceScore: 0))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 625, y: 785))
        fixture.monitor.sendButton(isPressed: true)
        morph.tick()
        fixture.controller.setSensitiveContentVisible(false)
        let visibleHosts = fixture.hostView.subviews.flatMap(\.subviews)
            .compactMap { $0 as? NSHostingView<AnyView> }
            .filter { !$0.isHidden }
        #expect(visibleHosts.isEmpty)
    }

    @Test
    func enablingReducedMotionDuringAttachmentReleasesTheSatelliteHost() {
        let morph = RecordingMorphEngine()
        var reduceMotion = false
        let fixture = ControllerFixture(morphEngine: morph, motionPreference: { reduceMotion })
        fixture.controller.present(ControllerActivityFixture(id: "primary", sourceID: "music", relevanceScore: 1))
        fixture.controller.present(ControllerActivityFixture(id: "secondary", sourceID: "timer", relevanceScore: 0))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 625, y: 785))
        fixture.monitor.sendButton(isPressed: true)
        morph.tick()
        reduceMotion = true
        morph.tick()
        let visibleHosts = fixture.hostView.subviews.flatMap(\.subviews)
            .compactMap { $0 as? NSHostingView<AnyView> }
            .filter { !$0.isHidden }
        #expect(visibleHosts.count == 1)
        #expect(fixture.controller.state == .open)
        #expect(!morph.isRunning)
    }

    @Test
    func hoverDuringReplacementWaitsForTheBareNotch() throws {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.present(ControllerActivityFixture(id: "old"))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        let replacement = ControllerActivityFixture(id: "new")
        fixture.controller.present(replacement)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(replacement.expandedContexts.isEmpty)
        var reachedBase = false
        for _ in 0..<600 where morph.isRunning {
            morph.tick()
            let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
            if shape.path?.boundingBoxOfPath.size == CGSize(width: 200, height: 30) { reachedBase = true }
            if !reachedBase { #expect(replacement.expandedContexts.isEmpty) }
        }
        #expect(reachedBase)
        #expect(fixture.controller.state == .open)
        #expect(replacement.expandedContexts.count == 1)
    }

    @Test
    func mountedSameIDReplacementRetainsTheOldInstanceUntilItsRootLeaves() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        let old = ControllerActivityFixture(id: "music")
        fixture.controller.present(old)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()

        #expect(fixture.controller.surface.retainedActivityRoots.first === old)

        let replacement = ControllerActivityFixture(id: "music")
        fixture.controller.present(replacement)

        #expect(old.activations - old.suspensions == 1)
        #expect(replacement.activations - replacement.suspensions == 1)
        #expect(!replacement.factoryRanBeforeActivation)
        #expect(fixture.controller.surface.retainedActivityRoots.contains { $0 === old })

        morph.settle()

        #expect(old.suspensions == 1)
        #expect(replacement.suspensions == 0)
        #expect(!fixture.controller.surface.retainedActivityRoots.contains { $0 === old })
    }

    @Test
    func reducedMotionReplacementReleasesTheOldInstanceAfterApplyingTheNewRoot() {
        let fixture = ControllerFixture(reducesMotion: true)
        let old = ControllerActivityFixture(id: "music")
        fixture.controller.present(old)
        fixture.controller.start()
        defer { fixture.controller.stop() }

        let replacement = ControllerActivityFixture(id: "music")
        fixture.controller.present(replacement)

        #expect(old.suspensions == 1)
        #expect(replacement.activations - replacement.suspensions == 1)
        #expect(!replacement.factoryRanBeforeActivation)
        #expect(!fixture.controller.surface.retainedActivityRoots.contains { $0 === old })
    }

    @Test
    func replacingTheSecondaryWaitsForClosureBeforeBuildingItsIcon() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.present(ControllerActivityFixture(id: "primary", sourceID: "music", relevanceScore: 1))
        fixture.controller.present(ControllerActivityFixture(id: "old", sourceID: "timer", relevanceScore: 0))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        let replacement = ControllerActivityFixture(id: "new", sourceID: "timer", relevanceScore: 0)
        fixture.controller.present(replacement)
        #expect(replacement.compactLeadingContexts.isEmpty)
        morph.settle()
        #expect(replacement.compactLeadingContexts.count == 1)
        #expect(!morph.isRunning)
    }

    @Test
    func anArrivalDuringDismissalCannotReverseTheClosingPhase() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.present(ControllerActivityFixture(id: "old"))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        fixture.controller.endActivity(id: "old")
        morph.tick()
        let replacement = ControllerNoticeFixture(id: "new")
        fixture.controller.showNotice(replacement)
        #expect(replacement.compactLeadingContexts.isEmpty)
        morph.settle()
        #expect(replacement.compactLeadingContexts.count == 1)
        #expect(!morph.isRunning)
    }

    @Test
    func replacingANoticeClosesFullyBeforeBuildingTheLatestContent() throws {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.controller.showNotice(ControllerNoticeFixture(id: "first"))
        morph.settle()
        let second = ControllerNoticeFixture(id: "second")
        fixture.controller.showNotice(second)
        #expect(second.compactLeadingContexts.isEmpty)
        let latest = ControllerNoticeFixture(id: "latest")
        fixture.controller.showNotice(latest)
        #expect(latest.compactLeadingContexts.isEmpty)
        var sawBareNotch = false
        for _ in 0..<600 where morph.isRunning {
            morph.tick()
            let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
            if shape.path?.boundingBoxOfPath.size == CGSize(width: 200, height: 30) {
                sawBareNotch = true
            }
        }
        #expect(sawBareNotch)
        #expect(second.compactLeadingContexts.isEmpty)
        #expect(latest.compactLeadingContexts.count == 1)
        #expect(!morph.isRunning)
    }

    @Test
    func tallestActivityCanOvershootWithoutClippingTheCanvas() throws {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.present(ControllerActivityFixture(id: "tall", expandedContentHeight: 400))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        var peak: CGFloat = 0
        for _ in 0..<240 {
            morph.tick()
            let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
            let bounds = try #require(shape.path?.boundingBoxOfPath)
            peak = max(peak, bounds.height)
            #expect(bounds.minY >= 0)
        }
        #expect(peak > NotchConfiguration.default.maximumActivityExpandedHeight + 5)
        #expect(peak < NotchConfiguration.default.maximumActivityExpandedHeight + 40)
    }

    @Test
    func activityGlowCanUseAllFourInsetsWithoutEscapingItsSurface() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.present(ControllerGlowFixture())
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        let hosting = try #require(fixture.hostView.subviews
            .flatMap(\.subviews)
            .compactMap { $0 as? NSHostingView<AnyView> }
            .first { !$0.isHidden })
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / hosting.bounds.height
        func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
            try #require(bitmap.colorAt(x: Int(x * scaleX), y: Int(y * scaleY))?.usingColorSpace(.deviceRGB))
        }
        // The probe extends 8 pt into the 20 pt side / 4 pt top / 16 pt
        // bottom insets. Native chrome, rather than content bounds, clips it.
        #expect(try color(hosting.bounds.midX, hosting.bounds.midY).redComponent > 0.8)
        for point in [
            CGPoint(x: 16, y: hosting.bounds.midY),
            CGPoint(x: hosting.bounds.width - 16, y: hosting.bounds.midY),
            CGPoint(x: hosting.bounds.midX, y: 1),
            CGPoint(x: hosting.bounds.midX, y: hosting.bounds.height - 12)
        ] {
            #expect(try color(point.x, point.y).redComponent > 0.8)
        }
        #expect(try color(4, hosting.bounds.midY).redComponent < 0.05)
        #expect(try color(hosting.bounds.midX, hosting.bounds.height - 4).redComponent < 0.05)

        // Top light must survive above the expanded host's rectangular frame,
        // into the visible wing beside the physical cutout.
        let native = fixture.hostView
        native.layoutSubtreeIfNeeded()
        let surface = try #require(native.bitmapImageRepForCachingDisplay(in: native.bounds))
        native.cacheDisplay(in: native.bounds, to: surface)
        let pixelX = Int(350 * CGFloat(surface.pixelsWide) / native.bounds.width)
        let pixelY = Int(28 * CGFloat(surface.pixelsHigh) / native.bounds.height)
        let upperLight = try #require(surface.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB))
        #expect(upperLight.redComponent > 0.8)
    }

    @Test
    func calibrationGuidesTouchTheSidesWithoutChangingTheSaved187PointWidth() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.sizeStore.sizes[42] = CGSize(width: 187, height: 33)
        fixture.controller.start()
        fixture.controller.beginSizeCalibration()
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        let path = try #require(shape.path)
        let geometry = try #require(fixture.calibrationPresenter.geometry)
        let center = fixture.hostView.bounds.midX
        let middle = fixture.hostView.bounds.maxY - geometry.height / 2
        let left = center - geometry.leftExtent
        let right = center + geometry.rightExtent
        #expect(path.boundingBoxOfPath.size == CGSize(width: 187, height: 33))
        #expect(fixture.calibrationPresenter.size == CGSize(width: 187, height: 33))
        #expect(path.contains(CGPoint(x: left + 0.01, y: middle)))
        #expect(!path.contains(CGPoint(x: left - 0.01, y: middle)))
        #expect(path.contains(CGPoint(x: right - 0.01, y: middle)))
        #expect(!path.contains(CGPoint(x: right + 0.01, y: middle)))
        #expect(path.boundingBoxOfPath.minY == fixture.hostView.bounds.maxY - geometry.height)
        fixture.controller.stop()
    }

    @Test
    func softwareDisplaysRejectHardwareCalibrationAndKeepTheFixedBump() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        let display = fixture.resolver.display
        fixture.resolver.display = ActiveDisplay(
            displayID: display.displayID,
            frame: display.frame,
            backingScale: display.backingScale,
            notch: .absent
        )
        fixture.controller.start()
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        let initialSize = try #require(shape.path?.boundingBoxOfPath.size)
        fixture.controller.beginSizeCalibration()
        #expect(fixture.calibrationPresenter.size == nil)
        #expect(shape.path?.boundingBoxOfPath.size == initialSize)
        fixture.calibrationPresenter.onStep?(2, 1)
        #expect(shape.path?.boundingBoxOfPath.size == initialSize)
        #expect(fixture.calibrationPresenter.size == nil)
        fixture.calibrationPresenter.onFinish?(true)
        fixture.controller.stop()
        fixture.controller.start()
        #expect(shape.path?.boundingBoxOfPath.size == initialSize)
        fixture.controller.stop()
    }

    @Test
    func calibrationChangesTheRealContourAndBlocksHoverUntilFinished() throws {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.start()
        fixture.controller.beginSizeCalibration()
        fixture.calibrationPresenter.onStep?(-2, 1)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(fixture.controller.state == .closed)
        #expect(!morph.isRunning)
        #expect(fixture.panel.ignoresMouseEvents)
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        #expect(shape.path?.boundingBoxOfPath.size == CGSize(width: 198, height: 31))
        #expect(fixture.calibrationPresenter.size == shape.path?.boundingBoxOfPath.size)

        fixture.calibrationPresenter.onFinish?(true)
        fixture.controller.stop()
        fixture.controller.start()
        #expect(shape.path?.boundingBoxOfPath.size == CGSize(width: 198, height: 31))
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(fixture.controller.state == .open)
        fixture.controller.stop()
    }

    @Test
    func lockingDuringCalibrationHidesGuidesAndDiscardsTheDraft() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        fixture.controller.beginSizeCalibration()
        fixture.calibrationPresenter.onStep?(20, 10)
        fixture.monitor.sendLock()
        #expect(fixture.calibrationPresenter.hideCount == 1)
        #expect(fixture.sizeStore.sizes.isEmpty)
        fixture.monitor.sendUnlock()
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        #expect(shape.path?.boundingBoxOfPath.size == CGSize(width: 200, height: 30))
        fixture.controller.stop()
    }

    @Test
    func displayChangesCancelCalibrationAndDoNotApplyItsDraftToAnotherScreen() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        fixture.controller.beginSizeCalibration()
        fixture.calibrationPresenter.onStep?(20, 10)
        let previous = fixture.resolver.display
        fixture.resolver.display = ActiveDisplay(
            displayID   : 77,
            frame       : previous.frame.offsetBy(dx: 1_000, dy: 0),
            backingScale: 2,
            notch       : previous.notch
        )
        fixture.monitor.sendDisplayChange()
        #expect(fixture.calibrationPresenter.hideCount == 1)
        #expect(fixture.sizeStore.sizes.isEmpty)
        #expect(fixture.controller.activeDisplay?.displayID == 77)
        fixture.controller.stop()
    }

    @Test
    func closedNotchHidesTheBorderAndCompactNoticesKeepItFaint() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        let border = try #require(fixture.hostView.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView)
        #expect(border.isHidden)
        fixture.controller.setBorderAppearance(.connected)
        fixture.controller.showNotice(ControllerNoticeFixture(id: "headphones"))
        #expect(!border.isHidden)
        #expect(border.alphaValue > 0 && border.alphaValue <= 0.15)

        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(!border.isHidden)
        #expect(border.alphaValue == 1)

        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        #expect(border.isHidden)
        fixture.controller.stop()
    }

    @Test
    func noticeBorderOverridesTheNetworkUntilDismissal() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph, reducesMotion: true)
        fixture.controller.start()
        fixture.controller.setBorderAppearance(.connected)
        #expect(fixture.hostView.borderAppearance == .connected)

        let notice = ControllerNoticeFixture(id: "headphones", borderAppearance: .neutral)
        fixture.controller.showNotice(notice)
        #expect(fixture.hostView.borderAppearance == .neutral)

        fixture.controller.dismissActivities(from: notice.sourceID)
        #expect(fixture.hostView.borderAppearance == .connected)
        #expect(morph.startCount == 0)
        fixture.controller.stop()
    }

    @Test
    func networkChangesDuringANoticeAreRestoredWithoutStaleGreen() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        fixture.controller.setBorderAppearance(.connected)
        let notice = ControllerNoticeFixture(id: "headphones", borderAppearance: .neutral)
        fixture.controller.showNotice(notice)
        fixture.controller.setBorderAppearance(.neutral)
        fixture.controller.dismissActivities(from: notice.sourceID)
        #expect(fixture.hostView.borderAppearance == .neutral)

        fixture.controller.showNotice(notice)
        fixture.controller.setBorderAppearance(.connected)
        #expect(fixture.hostView.borderAppearance == .neutral)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(fixture.hostView.borderAppearance == .connected)
        fixture.controller.stop()
    }

    @Test
    func borderChangesDoNotRebuildContentOrStartTheMorph() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        let activity = ControllerActivityFixture(id: "music")
        fixture.controller.start()
        fixture.controller.present(activity)
        morph.settle()
        let builds = activity.contentFactoryCount
        let starts = morph.startCount
        fixture.controller.setBorderAppearance(.connected)
        fixture.controller.setBorderAppearance(.connected)
        #expect(fixture.hostView.borderAppearance == .connected)
        #expect(activity.contentFactoryCount == builds)
        #expect(morph.startCount == starts)
        #expect(!morph.isRunning)
        fixture.controller.stop()
    }

    @Test
    func expandedGlassHaloFitsInsideThePanelWithoutMovingTheNotch() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        let path = try #require(shape.path)
        let outline = fixture.hostView.convert(path.boundingBoxOfPath, to: nil)
        #expect(outline.minY >= 8)
        #expect(outline.maxY == fixture.panel.frame.height)
        #expect(!fixture.hostView.containsInteractivePoint(CGPoint(x: 500, y: -2)))
        fixture.controller.stop()
    }

    @Test
    func compactAndClosedChromeStayAnchoredToHardwareWithAHaloGutter() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        let screen = CGRect(x: 1_470, y: -200, width: 1_470, height: 956)
        let hardware = CGSize(width: 179, height: 32)
        fixture.resolver.display = ActiveDisplay(
            displayID   : 42,
            frame       : screen,
            backingScale: 2,
            notch       : HardwareNotch(isPresent: true, size: hardware)
        )
        fixture.controller.start()
        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)

        for compact in [false, true] {
            if compact { fixture.controller.showNotice(ControllerNoticeFixture(id: "alignment")) }
            let path = try #require(shape.path)
            let inWindow = fixture.hostView.convert(path.boundingBoxOfPath, to: nil)
            let onScreen = fixture.panel.convertToScreen(inWindow)
            #expect(onScreen.midX == screen.midX)
            #expect(onScreen.maxY == screen.maxY)
            #expect(onScreen.minY == screen.maxY - hardware.height)
            #expect(onScreen.width == hardware.width + (compact ? 128 : 0))
        }
        fixture.controller.stop()
    }

    @Test
    func noticesNeverBuildAnExpandedViewAndAreDiscardedDuringHover() {
        let fixture = ControllerFixture(reducesMotion: true)
        let notice = ControllerNoticeFixture(id: "device")
        let widget = ControllerWidgetFixture()
        fixture.controller.register(widget)
        fixture.controller.start()
        fixture.controller.showNotice(notice)
        fixture.monitor.sendPointer(CGPoint(x: 350, y: 790))
        #expect(notice.expandedFactoryCount == 0)
        #expect(widget.activations == 1)
        #expect(!widget.factoryRanBeforeActivation)
        let incoming = ControllerNoticeFixture(id: "volume")
        fixture.controller.showNotice(incoming)
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        #expect(incoming.activations == 0)
        fixture.controller.stop()
    }

    @Test
    func activeWidgetRefreshRebuildsTheGrantedOwnersContent() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        let widget = ControllerWidgetFixture()
        fixture.controller.register(widget)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        let initialFactories = widget.factoryCount
        #expect(initialFactories == 1)

        let context = try #require(widget.context)
        context.setNeedsContent()

        #expect(widget.factoryCount == initialFactories + 1)
    }

    @Test
    func liveActivityCollapseReachesBareNotchBeforeRevealingCompactContent() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        let activity = ControllerActivityFixture(id: "music")
        fixture.controller.present(activity)
        fixture.controller.start()
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        morph.settle()
        let compactBuilds = activity.compactLeadingContexts.count
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        #expect(activity.compactLeadingContexts.count == compactBuilds)
        #expect(activity.suspensions == 0)
        var sawBase = false
        for _ in 0..<360 {
            morph.tick()
            let bounds = (fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)?.path?.boundingBoxOfPath
            if let bounds, abs(bounds.width - 200) < 0.0001, abs(bounds.height - 30) < 0.0001 {
                sawBase = true
                break
            }
        }
        #expect(sawBase)
        #expect(!fixture.hostView.containsInteractivePoint(fixture.point(x: 350, belowTop: 15)))
        morph.settle()
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 350, belowTop: 15)))
        #expect(activity.compactLeadingContexts.count > compactBuilds)
        #expect(activity.activations == 1)
        #expect(!morph.isRunning)
        fixture.controller.stop()
    }

    @Test
    func noticeWidthIsBoundedAndDoesNotJumpBeforeTheMorphAdvances() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.start()
        let notice = ControllerNoticeFixture(id: "volume", compactPreferredSideWidth: 116)
        fixture.controller.showNotice(notice)
        #expect(notice.compactLeadingContexts.last?.availableSize.width == 102)
        #expect(!fixture.hostView.containsInteractivePoint(fixture.point(x: 700, belowTop: 15)))
        morph.settle()
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 700, belowTop: 15)))
        let invalid = ControllerNoticeFixture(id: "invalid", compactPreferredSideWidth: .infinity)
        fixture.controller.showNotice(invalid)
        #expect(invalid.compactLeadingContexts.isEmpty)
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 700, belowTop: 15)))
        morph.settle()
        #expect(invalid.compactLeadingContexts.last?.availableSize.width == 50)
        #expect(!fixture.hostView.containsInteractivePoint(fixture.point(x: 700, belowTop: 15)))
        fixture.controller.stop()
    }

    @Test
    func rehoverCancelsTheReturnToBaseWithoutADeferredCompactReveal() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        let activity = ControllerActivityFixture(id: "music")
        fixture.controller.present(activity)
        fixture.controller.start()
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        morph.settle()
        #expect(fixture.controller.state == .open)
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 500, belowTop: 100)))
        #expect(activity.expandedContexts.count >= 2)
        #expect(!morph.isRunning)
        fixture.controller.stop()
    }

    @Test
    func immediateCloseAndLockDuringCollapseCannotLeaveAHiddenSessionStuck() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        let activity = ControllerActivityFixture(id: "music")
        fixture.controller.start()
        fixture.controller.present(activity)
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        morph.settle()
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 350, belowTop: 15)))
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        morph.settle()
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        fixture.monitor.sendLock()
        #expect(!morph.isRunning)
        fixture.monitor.sendUnlock()
        morph.settle()
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 350, belowTop: 15)))
        #expect(!morph.isRunning)
        fixture.controller.stop()
    }

    @Test
    func lockDoesNotBrieflyActivateTheHiddenSecondaryProvider() {
        let fixture = ControllerFixture(reducesMotion: true)
        let primary = ControllerActivityFixture(id: "primary", sourceID: "music", relevanceScore: 1)
        let secondary = ControllerActivityFixture(id: "secondary", sourceID: "timer", relevanceScore: 0)
        fixture.controller.present(primary)
        fixture.controller.present(secondary)
        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        let activationsBeforeLock = secondary.activations
        #expect(activationsBeforeLock >= 1)
        fixture.monitor.sendLock()
        #expect(secondary.activations == activationsBeforeLock)
        fixture.monitor.sendUnlock()
        #expect(secondary.activations == activationsBeforeLock + 1)
        fixture.controller.stop()
    }

    @Test(arguments: [false, true])
    func displayChangeReconcilesCompactWidth(reduceMotion: Bool) {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph, reducesMotion: reduceMotion)
        fixture.controller.present(ControllerActivityFixture(id: "music"))
        fixture.controller.start()
        morph.settle()
        let original = fixture.resolver.display
        fixture.resolver.display = ActiveDisplay(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 280, height: 800),
            backingScale: 2,
            notch: original.notch
        )
        fixture.monitor.sendDisplayChange()
        let shape = fixture.hostView.layer?.sublayers?.first as? CAShapeLayer
        #expect((shape?.path?.boundingBoxOfPath.width ?? .infinity) <= 280)
        morph.settle()
        #expect(shape?.path?.boundingBoxOfPath.width == 280)
        fixture.resolver.display = original
        fixture.monitor.sendDisplayChange()
        morph.settle()
        #expect(shape?.path?.boundingBoxOfPath.width == 328)
        fixture.controller.stop()
    }

    @Test
    func acceptedHoverPerformsFeedbackBeforeStartingTheMorph() {
        var events: [String] = []
        let fixture = ControllerFixture(
            morphEngine: RecordingMorphEngine { events.append("morph") },
            performer  : RecordingHapticPerformer { events.append("haptic") }
        )

        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        fixture.monitor.sendPointer(CGPoint(x: 501, y: 790))

        #expect(events == ["haptic", "morph"])
        fixture.controller.stop()
    }

    @Test
    func automaticActivityPresentationDoesNotPerformHoverFeedback() {
        let performer = CountingHapticPerformer()
        let fixture = ControllerFixture(performer: performer)
        let activity = ControllerActivityFixture(id: "music")

        fixture.controller.start()
        fixture.controller.present(activity)

        #expect(performer.count == 0)
        #expect(activity.activations == 1)
        fixture.controller.stop()
        #expect(activity.suspensions == 1)
    }

    @Test
    func lockSuspendsActivityAndInhibitsPointerEventsUntilUnlock() {
        let performer = CountingHapticPerformer()
        let fixture = ControllerFixture(performer: performer)
        let activity = ControllerActivityFixture(id: "music")

        fixture.controller.start()
        fixture.controller.present(activity)
        fixture.monitor.sendLock()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))

        #expect(activity.suspensions == 1)
        #expect(performer.count == 0)

        fixture.monitor.sendUnlock()
        #expect(activity.activations == 2)
        fixture.controller.stop()
    }

    @Test
    func displayMetricsRefreshEvenWhenDisplayIdentityDoesNotChange() {
        let fixture = ControllerFixture()
        fixture.controller.start()
        #expect(fixture.panel.frame.width == 1_000)

        fixture.resolver.display = ActiveDisplay(
            displayID   : 42,
            frame       : CGRect(x: 0, y: 0, width: 1_440, height: 900),
            backingScale: 2,
            notch       : HardwareNotch(isPresent: true, size: CGSize(width: 210, height: 34))
        )
        fixture.monitor.sendDisplayChange()

        #expect(fixture.panel.frame.width == 1_440)
        #expect(fixture.hostView.frame.width == 1_440)
        fixture.controller.stop()
    }

    @Test
    func reduceMotionSnapsWithoutStartingDisplayLink() {
        let morphEngine = RecordingMorphEngine()
        let fixture = ControllerFixture(
            morphEngine : morphEngine,
            reducesMotion: true
        )

        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))

        #expect(fixture.controller.state == .open)
        #expect(morphEngine.startCount == 0)
        fixture.controller.stop()
    }

    @Test
    func contextualPageNeverExceedsTheStandardExpandedHeight() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        let page = ControllerContextualPage(contentHeight: 400)
        fixture.controller.start()
        defer { fixture.controller.stop() }

        fixture.controller.surface.applyPresentation(DisplayPresentation(
            primary: nil,
            secondary: nil,
            notice: nil,
            expanded: nil,
            expandedIsLiveActivity: false,
            showsWidgets: false,
            contextualPage: page,
            contextualPageIsSelected: true,
            widgetContentRevision: 0,
            style: .notch
        ))

        let shape = try #require(fixture.hostView.layer?.sublayers?.first as? CAShapeLayer)
        let bounds = try #require(shape.path?.boundingBoxOfPath)
        #expect(bounds.height == NotchConfiguration.default.expandedHeight)
        #expect(page.contexts.count == 1)
        #expect(page.contexts[0].availableSize.height < NotchConfiguration.default.expandedHeight)
    }

    @Test
    func contextualPageReceivesTheHardwareNotchAsALocalCenterObstruction() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        let page = ControllerContextualPage(contentHeight: 400)
        fixture.controller.start()
        defer { fixture.controller.stop() }

        fixture.controller.surface.applyPresentation(DisplayPresentation(
            primary: nil,
            secondary: nil,
            notice: nil,
            expanded: nil,
            expandedIsLiveActivity: false,
            showsWidgets: false,
            contextualPage: page,
            contextualPageIsSelected: true,
            widgetContentRevision: 0,
            style: .notch
        ))

        let context = try #require(page.contexts.last)
        #expect(context.centerObstructionFrame.width > 0)
        #expect(context.centerObstructionFrame.midX == context.availableSize.width / 2)
        #expect(context.centerObstructionFrame.minY == 0)
        #expect(context.centerObstructionFrame.maxY < context.availableSize.height)
    }

    @Test
    func replacingAContextualPageInstanceWithTheSameIDAndRevisionRendersTheReplacement() {
        let fixture = ControllerFixture(reducesMotion: true)
        let first = ControllerContextualPage(contentHeight: 120)
        let replacement = ControllerContextualPage(contentHeight: 120)
        fixture.controller.start()
        defer { fixture.controller.stop() }

        func presentation(_ page: ControllerContextualPage) -> DisplayPresentation {
            DisplayPresentation(
                primary: nil,
                secondary: nil,
                notice: nil,
                expanded: nil,
                expandedIsLiveActivity: false,
                showsWidgets: false,
                contextualPage: page,
                contextualPageIsSelected: true,
                widgetContentRevision: 0,
                style: .notch
            )
        }

        fixture.controller.surface.applyPresentation(presentation(first))
        fixture.controller.surface.applyPresentation(presentation(replacement))

        #expect(first.contexts.count == 1)
        #expect(replacement.contexts.count == 1)
    }

    @Test
    func selectedPersistentContextualPageIgnoresPointerExitUntilItsFlagClears() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        defer { fixture.controller.stop() }

        func presentation(_ page: ControllerContextualPage) -> DisplayPresentation {
            DisplayPresentation(
                primary: nil,
                secondary: nil,
                notice: nil,
                expanded: nil,
                expandedIsLiveActivity: false,
                showsWidgets: false,
                contextualPage: page,
                contextualPageIsSelected: true,
                widgetContentRevision: 0,
                style: .notch
            )
        }

        fixture.controller.surface.applyPresentation(presentation(
            ControllerContextualPage(contentHeight: 120, keepsExpanded: true)
        ))
        fixture.controller.surface.handlePointer(at: CGPoint(x: 50, y: 500))

        #expect(fixture.controller.state == .open)
        #expect(fixture.controller.collapseRequestCount == 0)

        fixture.controller.surface.applyPresentation(presentation(
            ControllerContextualPage(contentHeight: 120, keepsExpanded: false)
        ))
        fixture.controller.surface.handlePointer(at: CGPoint(x: 50, y: 500))

        #expect(fixture.controller.collapseRequestCount == 1)
    }

    @Test
    func recognizedFileDragRunsOneFiniteHeartbeatAndNearHoverRequestsDragExpansion() {
        let morph = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morph)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        morph.settle()

        fixture.controller.surface.setRecognizedFileDragActive(
            true,
            at: CGPoint(x: 100, y: 100)
        )
        let starts = morph.startCount
        fixture.controller.surface.setRecognizedFileDragActive(
            true,
            at: CGPoint(x: 100, y: 100)
        )
        #expect(morph.startCount == starts)
        morph.settle()
        #expect(!morph.isRunning)

        fixture.controller.surface.handlePointer(at: CGPoint(x: 500, y: 790))
        #expect(fixture.controller.state == .open)
        #expect(fixture.controller.expansionRequests.last?.trigger == .drag)
    }

    @Test
    func recognizedFileDragUsesAWideIntakeWithoutChangingOrdinaryHitTesting() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.present(ControllerActivityFixture(
            id: "tall",
            expandedContentHeight: 200
        ))
        fixture.controller.start()
        defer { fixture.controller.stop() }
        let intakePoint = CGPoint(x: 250, y: 650)

        fixture.controller.surface.handlePointer(at: intakePoint)
        #expect(fixture.controller.state == .closed)
        #expect(fixture.panel.ignoresMouseEvents)
        #expect(fixture.controller.surface.fileDropReceiverPanel.ignoresMouseEvents)

        fixture.controller.surface.setRecognizedFileDragActive(true, at: intakePoint)
        #expect(fixture.controller.state == .open)
        #expect(fixture.controller.expansionRequests.last?.trigger == .drag)
        #expect(fixture.panel.ignoresMouseEvents)
        #expect(fixture.controller.surface.fileDropReceiverPanel.ignoresMouseEvents == false)

        let expandedBottomPoint = CGPoint(x: 500, y: 580)
        fixture.controller.surface.handlePointer(at: expandedBottomPoint)
        #expect(fixture.controller.state == .open)
        #expect(fixture.panel.ignoresMouseEvents)
        #expect(fixture.controller.surface.fileDropReceiverPanel.ignoresMouseEvents == false)

        fixture.controller.surface.handlePointer(at: intakePoint)
        fixture.controller.surface.setRecognizedFileDragActive(false, at: intakePoint)
        #expect(fixture.panel.ignoresMouseEvents)
        #expect(fixture.controller.surface.fileDropReceiverPanel.ignoresMouseEvents)
    }

    @Test
    func recognizedFileDragActivatesTheReceiverBeforeCrossingItsBoundary() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        let approachPoint = CGPoint(
            x: fixture.panel.frame.midX,
            y: fixture.panel.frame.minY - 20
        )

        fixture.controller.surface.handlePointer(at: approachPoint)
        #expect(fixture.controller.state == .closed)
        #expect(fixture.panel.ignoresMouseEvents)

        fixture.controller.surface.setRecognizedFileDragActive(true, at: approachPoint)
        #expect(fixture.controller.state == .closed)
        #expect(fixture.panel.ignoresMouseEvents)
        #expect(fixture.controller.surface.fileDropReceiverPanel.ignoresMouseEvents == false)

        fixture.controller.surface.setRecognizedFileDragActive(false, at: approachPoint)
        #expect(fixture.panel.ignoresMouseEvents)
        #expect(fixture.controller.surface.fileDropReceiverPanel.ignoresMouseEvents)
    }

    @Test
    func validatedOfferHintArmsBeforeNativeHoverAndMouseUpBlocksLateRearm() {
        let edgeGuard = RecordingFileDragTopEdgeGuard()
        let fixture = ControllerFixture(
            reducesMotion: true,
            fileDragTopEdgeGuard: edgeGuard
        )
        fixture.controller.start()
        defer { fixture.controller.stop() }
        let intakePoint = CGPoint(x: 500, y: 790)

        fixture.controller.surface.setRecognizedFileDragActive(
            true,
            at: intakePoint,
            hasValidatedOfferHint: true
        )
        #expect(fixture.controller.state == .open)
        #expect(edgeGuard.startCount == 1)

        fixture.controller.surface.endRecognizedFileDragGesture()
        fixture.hostView.onFileDragHoverChanged?([
            URL(fileURLWithPath: "/tmp/late-drop.txt")
        ])

        #expect(edgeGuard.startCount == 1)
        #expect(edgeGuard.stopCount >= 1)
    }

    @Test
    func nativeExitCanRearmTheGuardDuringTheSamePhysicalGesture() {
        let edgeGuard = RecordingFileDragTopEdgeGuard()
        let fixture = ControllerFixture(
            reducesMotion: true,
            fileDragTopEdgeGuard: edgeGuard
        )
        fixture.controller.start()
        defer { fixture.controller.stop() }
        let intakePoint = CGPoint(x: 500, y: 790)
        fixture.controller.surface.setRecognizedFileDragActive(
            true,
            at: intakePoint,
            hasValidatedOfferHint: true
        )
        #expect(edgeGuard.startCount == 1)

        fixture.hostView.onFileDragHoverChanged?(nil)
        fixture.hostView.onFileDragHoverChanged?([
            URL(fileURLWithPath: "/tmp/reentered.txt")
        ])

        #expect(edgeGuard.startCount == 2)
    }

    @Test
    func nativeHoverWithoutGlobalHintArmsWhenItsPendingOpeningIsGranted() throws {
        let edgeGuard = RecordingFileDragTopEdgeGuard()
        let fixture = ControllerFixture(
            reducesMotion: true,
            autoGrantExpansions: false,
            fileDragTopEdgeGuard: edgeGuard
        )
        fixture.controller.start()
        defer { fixture.controller.stop() }
        let intakePoint = CGPoint(x: 500, y: 790)

        fixture.controller.surface.setRecognizedFileDragActive(
            true,
            at: intakePoint,
            hasValidatedOfferHint: false
        )
        #expect(fixture.controller.state == .closed)
        #expect(edgeGuard.startCount == 0)

        fixture.hostView.onFileDragHoverChanged?([
            URL(fileURLWithPath: "/tmp/native-offer.txt")
        ])
        #expect(edgeGuard.startCount == 0)

        try fixture.controller.grantPendingExpansion()

        #expect(fixture.controller.state == .open)
        #expect(edgeGuard.startCount == 1)
    }

    @Test
    func contextualPresentationRefreshesAnAlreadyArmedIntakeToItsStandardHeight() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        fixture.controller.surface.setRecognizedFileDragActive(
            true,
            at: CGPoint(x: 250, y: 650)
        )
        let page = ControllerContextualPage(contentHeight: 400)

        fixture.controller.surface.applyPresentation(DisplayPresentation(
            primary: nil,
            secondary: nil,
            notice: nil,
            expanded: nil,
            expandedIsLiveActivity: false,
            showsWidgets: false,
            contextualPage: page,
            contextualPageIsSelected: true,
            widgetContentRevision: 0,
            style: .notch
        ))

        let windowPoint = fixture.panel.convertPoint(
            fromScreen: CGPoint(x: 500, y: 670)
        )
        let hitPoint = fixture.hostView.superview.map {
            $0.convert(windowPoint, from: nil)
        } ?? fixture.hostView.convert(windowPoint, from: nil)
        #expect(fixture.hostView.hitTest(hitPoint) === fixture.hostView)
    }

    @Test
    func expandedActivityKeepsTheCoveredWidgetSurfaceSuspended() {
        let fixture = ControllerFixture(reducesMotion: true)
        let widget = ControllerWidgetFixture()
        fixture.controller.register(widget)
        fixture.controller.present(ControllerActivityFixture(id: "music"))

        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))

        #expect(fixture.controller.state == .open)
        #expect(widget.activations == 0)
        fixture.controller.endActivity(id: "music")
        #expect(widget.activations == 1)
        fixture.controller.stop()
        #expect(widget.suspensions == 1)
    }

    @Test
    func activityChangesWhileLockedDoNotRestartTheDisplayLink() {
        let morphEngine = RecordingMorphEngine()
        let fixture = ControllerFixture(morphEngine: morphEngine)

        fixture.controller.start()
        fixture.controller.present(ControllerActivityFixture(id: "first"))
        #expect(morphEngine.startCount == 1)
        fixture.monitor.sendLock()
        #expect(morphEngine.isRunning == false)

        let second = ControllerActivityFixture(id: "second")
        fixture.controller.present(second)

        #expect(morphEngine.startCount == 1)
        #expect(morphEngine.isRunning == false)
        #expect(second.contentFactoryCount == 0)
        fixture.controller.stop()
    }

    @Test
    func transientPresentedWhileLockedIsNotReplayedAfterUnlock() {
        let fixture = ControllerFixture(reducesMotion: true)
        let notice = ControllerNoticeFixture(id: "locked-notice")

        fixture.controller.start()
        fixture.monitor.sendLock()
        fixture.controller.showNotice(notice)
        fixture.monitor.sendUnlock()

        #expect(notice.activations == 0)
        fixture.controller.stop()
    }

    @Test
    func compactActivityWingAcceptsHoverEntry() {
        let performer = CountingHapticPerformer()
        let fixture = ControllerFixture(
            performer    : performer,
            reducesMotion: true
        )
        fixture.controller.present(ControllerActivityFixture(id: "music"))
        fixture.controller.start()

        fixture.monitor.sendPointer(CGPoint(x: 350, y: 790))

        #expect(fixture.controller.state == .open)
        #expect(performer.count == 1)
        fixture.controller.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func controlDragKeepsExpandedContentAliveUntilMouseUp() async {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        fixture.monitor.sendButton(isPressed: true)

        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))

        #expect(fixture.controller.state == .open)
        #expect(fixture.panel.ignoresMouseEvents == false)

        fixture.monitor.sendButton(isPressed: false)
        // Wait for the event, not a wall-clock deadline: the close is a real
        // 280 ms debounce whose resumption queues behind every other main-actor
        // test during the full parallel run. The time limit still fails a hang.
        while fixture.controller.state != .closed {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(fixture.controller.state == .closed)
        fixture.controller.stop()
    }

    @Test
    func restartDoesNotUseAPointerSegmentFromBeforeStop() {
        let performer = CountingHapticPerformer()
        let fixture = ControllerFixture(
            performer    : performer,
            reducesMotion: true
        )
        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 0, y: 790))
        fixture.controller.stop()

        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 1_000, y: 790))

        #expect(fixture.controller.state == .closed)
        #expect(performer.count == 0)
        fixture.controller.stop()
    }

    @Test
    func compactProviderCanKeepItsOuterMarginsWithoutAnOversizedWing() {
        let fixture = ControllerFixture(reducesMotion: true)
        let activity = ControllerNoticeFixture(
            id                       : "narrow-compact",
            compactPreferredSideWidth: 40
        )
        fixture.controller.showNotice(activity)
        fixture.controller.start()
        defer { fixture.controller.stop() }

        #expect(activity.compactLeadingContexts.last?.availableSize.width == 26)
        let shape = fixture.hostView.layer?.sublayers?.first as? CAShapeLayer
        #expect(shape?.path?.boundingBoxOfPath.width == 280)
    }

    @Test
    func expandedFallbackLeavesTheHardwareNotchBareUntilOpened() {
        let fixture = ControllerFixture(reducesMotion: true)
        let music = ControllerActivityFixture(id: "paused-music")
        fixture.controller.setExpandedFallback(music)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        #expect(music.activations == 0)
        #expect(music.compactLeadingContexts.isEmpty)
        #expect(!fixture.hostView.containsInteractivePoint(fixture.point(x: 350, belowTop: 15)))
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))
        #expect(fixture.controller.state == .open)
        #expect(music.expandedContexts.count == 1)
        #expect(music.activations == 1)
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 500))
        #expect(fixture.controller.state == .closed)
        #expect(music.compactLeadingContexts.isEmpty)
        #expect(music.suspensions == 1)
    }

    @Test
    func oneActivityUsesCompactFamiliesWithSafeAvailableBounds() {
        let fixture = ControllerFixture(reducesMotion: true)
        let activity = ControllerActivityFixture(id: "music")
        fixture.controller.present(activity)

        fixture.controller.start()

        #expect(activity.compactLeadingContexts.last == NotchActivityViewContext(
            presentation : .compactLeading,
            availableSize: CGSize(width: 50, height: 18)
        ))
        #expect(activity.compactTrailingContexts.last == NotchActivityViewContext(
            presentation : .compactTrailing,
            availableSize: CGSize(width: 50, height: 18)
        ))
        #expect(activity.minimalContexts.isEmpty)
        #expect(!activity.factoryRanBeforeActivation)
        fixture.controller.stop()
    }

    @Test
    func twoActivitiesUseADetachedCircleThatExpandsOnlyOnClick() throws {
        let fixture = ControllerFixture(reducesMotion: true)
        let primary = ControllerActivityFixture(id: "primary", sourceID: "music", relevanceScore: 0.9)
        let secondary = ControllerActivityFixture(id: "secondary", sourceID: "bluetooth", relevanceScore: 0.8)
        fixture.controller.present(primary)
        fixture.controller.present(secondary)
        fixture.controller.start()
        defer { fixture.controller.stop() }
        #expect(primary.compactLeadingContexts.last?.availableSize == CGSize(width: 50, height: 18))
        #expect(primary.compactTrailingContexts.isEmpty)
        #expect(secondary.compactLeadingContexts.last?.availableSize == CGSize(width: 18, height: 18))
        #expect(!fixture.hostView.containsInteractivePoint(fixture.point(x: 605, belowTop: 15)))
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 625, belowTop: 15)))
        #expect(!fixture.hostView.containsInteractivePoint(fixture.point(x: 611, belowTop: 1)))
        fixture.monitor.sendPointer(CGPoint(x: 625, y: 785))
        #expect(fixture.controller.state == .closed)
        fixture.monitor.sendButton(isPressed: true)
        #expect(fixture.controller.state == .open)
        #expect(secondary.expandedContexts.last?.presentation == .expanded)
        #expect(primary.expandedContexts.isEmpty)
    }

    @Test
    func hiddenSensitiveActivityBypassesProviderContentAndMetadata() {
        let fixture = ControllerFixture(reducesMotion: true)
        let activity = ControllerActivityFixture(
            id     : "private",
            privacy: .sensitive
        )
        fixture.controller.present(activity)
        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))

        #expect(activity.contentFactoryCount == 0)
        #expect(activity.accessibilityLabelReads == 0)
        #expect(activity.contentURLReads == 0)

        fixture.controller.setSensitiveContentVisible(true)

        #expect(activity.expandedContexts.last?.presentation == .expanded)
        #expect(activity.contentFactoryCount == 1)
        #expect(activity.accessibilityLabelReads == 1)
        #expect(activity.contentURLReads == 1)

        fixture.controller.setSensitiveContentVisible(false)

        #expect(activity.contentFactoryCount == 1)
        #expect(activity.accessibilityLabelReads == 1)
        #expect(activity.contentURLReads == 1)
        fixture.controller.stop()
    }

    @Test
    func expandedHeightAdaptsToDeclaredContentAndClampsAtTheConfiguredMaximum() {
        let fixture = ControllerFixture(reducesMotion: true)
        let compactActivity = ControllerActivityFixture(
            id                   : "compact-expanded",
            expandedContentHeight: 40
        )
        fixture.controller.present(compactActivity)
        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))

        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 500, belowTop: 89)))
        #expect(!fixture.hostView.containsInteractivePoint(fixture.point(x: 500, belowTop: 91)))
        #expect(compactActivity.expandedContexts.last?.availableSize.height == 40)
        #expect(compactActivity.expandedContexts.last?.hardwareNotchWidth == 200)

        let tallActivity = ControllerActivityFixture(
            id                   : "compact-expanded",
            contentRevision      : 1,
            relevanceScore       : 1,
            expandedContentHeight: 400
        )
        fixture.controller.present(tallActivity)

        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 500, belowTop: 219)))
        #expect(tallActivity.expandedContexts.last?.availableSize.height == NotchConfiguration.default.maximumActivityExpandedHeight - 50)
        fixture.controller.stop()
    }

    @Test
    func invalidProviderHeightCannotPoisonTheInteractiveGeometry() {
        let fixture = ControllerFixture(reducesMotion: true)
        let activity = ControllerActivityFixture(
            id                   : "invalid-height",
            expandedContentHeight: .nan
        )
        fixture.controller.present(activity)
        fixture.controller.start()
        fixture.monitor.sendPointer(CGPoint(x: 500, y: 790))

        #expect(activity.expandedContexts.last?.availableSize.height == 0)
        #expect(fixture.hostView.containsInteractivePoint(fixture.point(x: 500, belowTop: 49)))
        #expect(!fixture.hostView.containsInteractivePoint(fixture.point(x: 500, belowTop: 51)))
        fixture.controller.stop()
    }
}

@MainActor
private final class ControllerGlowFixture: NotchLiveActivity {
    let id = "glow-layout-probe"
    let sourceID = "controller-tests"
    let contentRevision: UInt64 = 0
    let privacy: NotchActivityPrivacy = .standard
    let lifetime = NotchActivityLifetime(duration: 60)
    let expandedContentHeight: CGFloat = 150
    let accessibilityLabel = "Glow layout probe"

    func activate(in context: LiveActivityContext) {}
    func suspend() {}
    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(Color.clear
            .frame(width: context.availableSize.width, height: context.availableSize.height)
            .background { Color.red.padding(-8) })
    }
}

@MainActor
private final class RecordingFileDragTopEdgeGuard: FileDragTopEdgeGuardOperating {
    private(set) var availability: FileDragTopEdgeGuard.Availability = .inactive
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(region: CGRect, screen: CGRect) -> Bool {
        startCount += 1
        availability = .active
        return true
    }

    func update(region: CGRect, screen: CGRect) {}

    func stop() {
        stopCount += 1
        if availability != .unavailable { availability = .inactive }
    }
}

@MainActor
private final class ControllerFixture {
    let resolver  : MutableDisplayResolver
    let monitor   : RecordingEventMonitor
    let panel     : NotchPanel
    let hostView  : NotchHostView
    let controller: ControllerTestDriver
    let calibrationPresenter = RecordingCalibrationPresenter()
    let sizeStore = RecordingNotchSizeStore()

    /// point samples the same position below the notch's top across size presets.
    func point(x: CGFloat, belowTop depth: CGFloat) -> CGPoint {
        CGPoint(x: x, y: hostView.bounds.maxY - depth)
    }

    init(
        morphEngine : RecordingMorphEngine? = nil,
        performer   : (any HapticFeedbackPerforming)? = nil,
        reducesMotion: Bool = false,
        motionPreference: (() -> Bool)? = nil,
        style        : ExternalNotchStyle = .notch,
        autoGrantExpansions: Bool = true,
        fileDragTopEdgeGuard: (any FileDragTopEdgeGuardOperating)? = nil
    ) {
        let morphEngine = morphEngine ?? RecordingMorphEngine()
        let performer   = performer ?? CountingHapticPerformer()
        let display = ActiveDisplay(
            displayID   : 42,
            frame       : CGRect(x: 0, y: 0, width: 1_000, height: 800),
            backingScale: 2,
            notch       : HardwareNotch(isPresent: true, size: CGSize(width: 200, height: 30))
        )
        let resolver = MutableDisplayResolver(display: display)
        let monitor  = RecordingEventMonitor()
        let hostView = NotchHostView(frame: .zero)
        let panel    = NotchPanel(contentView: hostView)

        self.resolver = resolver
        self.monitor  = monitor
        self.hostView = hostView
        self.panel    = panel
        let activityHost = LiveActivityHost()
        let widgetHost   = WidgetHost()
        let surface = NotchController(
            configuration : .default,
            display       : display,
            morphEngine   : morphEngine,
            panel         : panel,
            hostView      : hostView,
            windowPinner  : NoOpWindowPinner(),
            hoverFeedback : HoverFeedback(performer: performer),
            sizeCalibration: NotchSizeCalibration(presenter: calibrationPresenter, store: sizeStore),
            activityHost  : activityHost,
            widgetHost    : widgetHost,
            fileDragTopEdgeGuard: fileDragTopEdgeGuard,
            reducesMotion: { motionPreference?() ?? reducesMotion }
        )
        self.controller = ControllerTestDriver(
            surface     : surface,
            activityHost: activityHost,
            widgetHost  : widgetHost,
            resolver    : resolver,
            monitor     : monitor,
            style       : style,
            autoGrantExpansions: autoGrantExpansions
        )
    }
}

/// ControllerTestDriver supplies the shared coordinator behavior around the
/// same fixed-display renderer used by production. It keeps legacy test call
/// sites readable without restoring global service ownership to the controller.
@MainActor
private final class ControllerTestDriver {
    let surface     : NotchController
    let activityHost: LiveActivityHost
    let widgetHost  : WidgetHost
    let resolver    : MutableDisplayResolver
    let monitor     : RecordingEventMonitor
    private var isExpanded = false
    private var expansionActivityID: String?
    private var isVisible  = true
    private var closeGeneration: UInt64 = 0
    private var isReconciling = false
    private var needsReconciliation = false
    private var widgetContentRevision: UInt64 = 0
    private let autoGrantExpansions: Bool
    private var style: ExternalNotchStyle
    private(set) var expansionRequests: [DisplayExpansionRequest] = []
    private(set) var cancelledExpansionGenerations: [UInt64] = []
    private(set) var collapseRequestCount = 0

    var state: NotchState { surface.state }
    var activeDisplay: ActiveDisplay? { surface.activeDisplay }
    var expandedFrame: CGRect? { surface.expandedFrame }
    var restingFrame: CGRect? { surface.restingFrame }
    var onExpandedFrameChanged: ((CGRect?) -> Void)? {
        get { surface.onExpandedFrameChanged }
        set { surface.onExpandedFrameChanged = newValue }
    }

    init(
        surface     : NotchController,
        activityHost: LiveActivityHost,
        widgetHost  : WidgetHost,
        resolver    : MutableDisplayResolver,
        monitor     : RecordingEventMonitor,
        style       : ExternalNotchStyle,
        autoGrantExpansions: Bool
    ) {
        self.surface      = surface
        self.activityHost = activityHost
        self.widgetHost   = widgetHost
        self.resolver     = resolver
        self.monitor      = monitor
        self.style        = style
        self.autoGrantExpansions = autoGrantExpansions

        activityHost.onChange = { [weak self] in self?.reconcile() }
        activityHost.onValidityChange = { [weak self] in self?.reconcile() }
        widgetHost.onContentChanged = { [weak self] in
            guard let self else { return }
            self.widgetContentRevision &+= 1
            self.reconcile()
        }
        surface.onExpansionRequested = { [weak self] request in
            guard let self else { return }
            self.expansionRequests.append(request)
            if self.autoGrantExpansions {
                self.expand(activityID: request.activityID)
            }
        }
        surface.onExpansionCancelled = { [weak self] generation in
            self?.cancelledExpansionGenerations.append(generation)
        }
        surface.onCollapseRequested = { [weak self] in
            self?.collapseRequestCount += 1
            self?.collapse()
        }
        surface.onCollapseFinished = { [weak self] _ in
            self?.isExpanded = false
            self?.expansionActivityID = nil
            self?.activityHost.setExpansion(.none)
            self?.reconcile()
        }
        surface.onRetainedActivityRootsChanged = { [weak self] in self?.reconcile() }
        monitor.onPointerMoved = { [weak surface] in surface?.handlePointer(at: $0) }
        monitor.onPointerButtonChanged = { [weak surface] in
            surface?.handlePointerButton(isPressed: $0)
        }
        monitor.onActiveDisplayMayHaveChanged = { [weak self] in
            guard let self else { return }
            self.surface.updateDisplay(self.resolver.display)
        }
        monitor.onSpaceChanged = { [weak surface] in surface?.handleSpaceChange() }
        monitor.onScreenLocked = { [weak self] in self?.setVisible(false) }
        monitor.onScreenUnlocked = { [weak self] in self?.setVisible(true) }
    }

    func start() {
        isVisible = true
        activityHost.setVisible(true)
        surface.updateDisplay(resolver.display)
        surface.start()
        reconcile()
    }

    func stop() {
        isVisible = false
        surface.stop()
        widgetHost.update(state: .closed)
        activityHost.stop()
    }

    func present(_ activity: any NotchLiveActivity) { activityHost.present(activity) }
    func showNotice(_ notice: any NotchTransientNotice) {
        guard isVisible else { return }
        activityHost.showNotice(notice)
    }
    func updateNotice(_ notice: any NotchTransientNotice) { activityHost.updateNotice(notice) }
    func setExpandedFallback(_ activity: (any NotchLiveActivity)?) {
        activityHost.setExpandedFallback(activity)
    }
    func endActivity(id: String) { activityHost.end(id: id) }
    func dismissActivity(id: String) { activityHost.dismiss(id: id) }
    func dismissActivities(from sourceID: String) { activityHost.dismissActivities(from: sourceID) }
    func register(_ widget: NotchWidget) {
        widgetHost.register(widget)
        widgetContentRevision &+= 1
        reconcile()
    }
    func unregisterWidget(id: WidgetIdentifier) { widgetHost.unregister(id: id); reconcile() }
    func beginSizeCalibration() { _ = surface.beginSizeCalibration() }
    func setSettingsFocused(_ isFocused: Bool) { surface.setSettingsFocused(isFocused) }
    func setExternalSurfacePresented(_ isPresented: Bool) {
        surface.setExternalSurfacePresented(isPresented)
    }
    func setHapticsEnabled(_ isEnabled: Bool) { surface.setHapticsEnabled(isEnabled) }
    func setBorderAppearance(_ appearance: NotchBorderAppearance) {
        surface.setBorderAppearance(appearance)
    }
    func setStyle(_ style: ExternalNotchStyle) {
        self.style = style
        reconcile()
    }
    func simulateCompactRoutingMovedAwayWhileRetainingExpanded(
        _ activity: any NotchLiveActivity
    ) {
        surface.applyPresentation(DisplayPresentation(
            primary: nil,
            secondary: nil,
            notice: nil,
            expanded: activity,
            expandedIsLiveActivity: true,
            showsWidgets: false,
            widgetContentRevision: widgetContentRevision,
            style: style
        ))
    }
    func setSensitiveContentVisible(_ isVisible: Bool) {
        surface.setSensitiveContentVisible(isVisible)
    }

    func grantPendingExpansion() throws {
        let request = try #require(expansionRequests.last)
        expand(activityID: request.activityID)
    }

    private func expand(activityID: String?) {
        isExpanded = true
        expansionActivityID = activityID
        surface.cancelClose()
        if let activityID {
            activityHost.setExpansion(.activity(activityID))
        } else if let primary = activityHost.selection.primary {
            activityHost.setExpansion(.activity(primary.id))
        } else {
            activityHost.setExpansion(.fallback)
        }
        reconcile()
    }

    private func collapse() {
        guard isExpanded else { return }
        closeGeneration &+= 1
        surface.close(animated: true, generation: closeGeneration)
    }

    private func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible {
            isExpanded = false
            expansionActivityID = nil
            surface.setVisible(false)
        }
        activityHost.setVisible(visible)
        if visible {
            surface.setVisible(true)
        }
        reconcile()
    }

    private func reconcile() {
        guard !isReconciling else {
            needsReconciliation = true
            return
        }
        isReconciling = true
        repeat {
            needsReconciliation = false
            if isExpanded, expansionActivityID == nil {
                let expansion = activityHost.selection.primary.map {
                    ActivityExpansionSelection.activity($0.id)
                } ?? .fallback
                if activityHost.expansionSelection != expansion {
                    activityHost.setExpansion(expansion)
                    needsReconciliation = true
                    continue
                }
            }
            let selection = activityHost.selection
            let presentation = DisplayPresentation(
                primary     : selection.primary,
                secondary   : selection.secondary,
                notice      : selection.notice,
                expanded    : isExpanded ? selection.expanded : nil,
                expandedIsLiveActivity: isExpanded && {
                    if case .activity = activityHost.expansionSelection { return true }
                    return false
                }(),
                showsWidgets: isExpanded && selection.expanded == nil,
                widgetContentRevision: widgetContentRevision,
                style       : style
            )
            let roots = presentation.visibleActivityRoots + surface.retainedActivityRoots
            let projected = activityHost.setVisibleActivities(roots)
            let accepted = Set(projected.accepted.map(ObjectIdentifier.init))
            if presentation.showsWidgets && isVisible {
                widgetHost.update(state: .open)
            }
            surface.applyPresentation(presentation.removingInvalidRoots(
                accepted: accepted,
                host    : activityHost
            ))
            _ = activityHost.setVisibleActivities(
                presentation.visibleActivityRoots + surface.retainedActivityRoots
            )
            if !presentation.showsWidgets || !isVisible {
                widgetHost.update(state: .closed)
            }
        } while needsReconciliation
        isReconciling = false
    }
}

@MainActor
private final class MutableDisplayResolver: ActiveDisplayResolving {
    var display: ActiveDisplay

    init(display: ActiveDisplay) {
        self.display = display
    }

    func resolveActiveDisplay() -> ActiveDisplay? {
        display
    }
}

@MainActor
private final class RecordingEventMonitor: EventMonitoring {
    var onPointerMoved               : ((CGPoint) -> Void)?
    var onPointerButtonChanged       : ((Bool) -> Void)?
    var onActiveDisplayMayHaveChanged: (() -> Void)?
    var onSpaceChanged               : (() -> Void)?
    var onScreenLocked               : (() -> Void)?
    var onScreenUnlocked             : (() -> Void)?

    func start() {}
    func stop() {}
    func sendPointer(_ point: CGPoint) { onPointerMoved?(point) }
    func sendButton(isPressed: Bool) { onPointerButtonChanged?(isPressed) }
    func sendDisplayChange() { onActiveDisplayMayHaveChanged?() }
    func sendLock() { onScreenLocked?() }
    func sendUnlock() { onScreenUnlocked?() }
}

@MainActor
private final class RecordingMorphEngine: MorphEngineDriving {
    private(set) var isRunning = false
    private(set) var startCount = 0
    private let onStart: () -> Void
    private var onFrame: ((CFTimeInterval) -> Void)?

    init(onStart: @escaping () -> Void = {}) {
        self.onStart = onStart
    }

    func start(onFrame: @escaping (CFTimeInterval) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.onFrame = onFrame
        startCount += 1
        onStart()
    }

    func stop() {
        isRunning = false
        onFrame = nil
    }

    func tick() { onFrame?(1.0 / 120.0) }
    func settle() { for _ in 0..<600 where isRunning { tick() } }
}

@MainActor
private struct NoOpWindowPinner: WindowPinning {
    func pin(_ window: NSWindow) {}
}

@MainActor
private final class CountingHapticPerformer: HapticFeedbackPerforming {
    private(set) var count = 0
    func performHoverFeedback() { count += 1 }
}

@MainActor
private struct RecordingHapticPerformer: HapticFeedbackPerforming {
    let onPerform: () -> Void
    func performHoverFeedback() { onPerform() }
}

@MainActor
private final class ControllerActivityFixture: NotchLiveActivity {
    let id                   : String
    let sourceID             : String
    let contentRevision      : UInt64
    let privacy              : NotchActivityPrivacy
    let lifetime             : NotchActivityLifetime
    let relevanceScore       : Double
    let expandedContentHeight: CGFloat

    private(set) var activations = 0

    private(set) var suspensions = 0
    private(set) var factoryRanBeforeActivation = false
    private(set) var accessibilityLabelReads = 0
    private(set) var contentURLReads          = 0
    private(set) var compactLeadingContexts : [NotchActivityViewContext] = []
    private(set) var compactTrailingContexts: [NotchActivityViewContext] = []
    private(set) var minimalContexts        : [NotchActivityViewContext] = []
    private(set) var expandedContexts       : [NotchActivityViewContext] = []

    var contentFactoryCount: Int {
        compactLeadingContexts.count
            + compactTrailingContexts.count
            + minimalContexts.count
            + expandedContexts.count
    }

    var accessibilityLabel: String {
        accessibilityLabelReads += 1
        return "Activity \(id)"
    }

    var contentURL: URL? {
        contentURLReads += 1
        return URL(string: "cascade://activity/\(id)")
    }

    init(
        id                   : String,
        sourceID             : String = "controller-tests",
        contentRevision      : UInt64 = 0,
        privacy              : NotchActivityPrivacy = .standard,
        lifetime             : NotchActivityLifetime = NotchActivityLifetime(duration: 60),
        relevanceScore       : Double = 0.5,
        expandedContentHeight: CGFloat = 88
    ) {
        self.id                    = id
        self.sourceID              = sourceID
        self.contentRevision       = contentRevision
        self.privacy               = privacy
        self.lifetime              = lifetime
        self.relevanceScore        = relevanceScore
        self.expandedContentHeight = expandedContentHeight
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        recordFactoryActivationOrder()
        compactLeadingContexts.append(context)
        return AnyView(Text(id))
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        recordFactoryActivationOrder()
        compactTrailingContexts.append(context)
        return AnyView(Text(id))
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        recordFactoryActivationOrder()
        minimalContexts.append(context)
        return AnyView(Text(id))
    }

    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView {
        recordFactoryActivationOrder()
        expandedContexts.append(context)
        return AnyView(Text(id))
    }

    func activate(in context: LiveActivityContext) { activations += 1 }
    func suspend() { suspensions += 1 }

    private func recordFactoryActivationOrder() {
        if activations <= suspensions { factoryRanBeforeActivation = true }
    }
}

@MainActor
private final class ControllerContextualPage: NotchContextualPage {
    let id = "shelf"
    let contentRevision: UInt64 = 1
    let contentHeight: CGFloat
    let keepsExpandedPresentation: Bool
    let accessibilityLabel = "Ripiano"
    private(set) var contexts: [NotchContextualPageContext] = []

    init(contentHeight: CGFloat, keepsExpanded: Bool = false) {
        self.contentHeight = contentHeight
        self.keepsExpandedPresentation = keepsExpanded
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        contexts.append(context)
        return AnyView(Text("Shelf"))
    }
}

@MainActor
private final class ControllerNoticeFixture: NotchTransientNotice {
    let id             : String
    let sourceID       : String
    let contentRevision: UInt64 = 0
    let privacy        : NotchActivityPrivacy = .standard
    let displayDuration: TimeInterval
    let borderAppearance: NotchBorderAppearance?
    let compactPreferredSideWidth: CGFloat?
    private(set) var activations = 0
    private(set) var expandedFactoryCount = 0
    private(set) var compactLeadingContexts: [NotchActivityViewContext] = []

    var accessibilityLabel: String { "Notice \(id)" }

    init(
        id             : String,
        sourceID       : String = "controller-tests",
        displayDuration: TimeInterval = 4,
        borderAppearance: NotchBorderAppearance? = nil,
        compactPreferredSideWidth: CGFloat? = nil
    ) {
        self.id              = id
        self.sourceID        = sourceID
        self.displayDuration = displayDuration
        self.borderAppearance = borderAppearance
        self.compactPreferredSideWidth = compactPreferredSideWidth
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        compactLeadingContexts.append(context)
        return AnyView(Text(id))
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(Text(id))
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(Text(id))
    }

    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView {
        expandedFactoryCount += 1
        return AnyView(Text(id))
    }

    func activate(in context: LiveActivityContext) { activations += 1 }
}

@MainActor
private final class ControllerWidgetFixture: NotchWidget {
    static let kind = WidgetKind("controller-test")

    let id = WidgetIdentifier("controller-test")
    let size = GridSpan.small
    private(set) var activations = 0
    private(set) var suspensions = 0
    private(set) var factoryCount = 0
    private(set) var factoryRanBeforeActivation = false
    private(set) var context: WidgetContext?

    func makeContentView() -> AnyView {
        factoryCount += 1
        if activations <= suspensions { factoryRanBeforeActivation = true }
        return AnyView(Text("Widget"))
    }
    func activate(in context: WidgetContext) {
        self.context = context
        activations += 1
    }
    func suspend() {
        context = nil
        suspensions += 1
    }
}
