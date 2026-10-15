//
//  NotchOptionsNavigationTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct NotchOptionsNavigationTests {

    @Test
    func backKeepsContextualSlotAndRejectsDelayedOpening() throws {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10])
        let source   = optionsWidgetID()
        fixture.coordinator.register(try optionsWidget(source))
        let shelf = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        #expect(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 2)
                == nil
        )
        let origin = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
        )
        let leaseID    = UUID()
        var dismissals = 0
        #expect(
            fixture.coordinator.presentOptions(
                page     : CoordinatorContextualPage(id: "detail", contentRevision: 1),
                leaseID  : leaseID,
                origin   : origin,
                onDismiss: { dismissals += 1 }
            )
        )
        let projection = try #require(fixture.surfaces[10]?.presentations.last)
        #expect(projection.optionsPage?.id == "detail")
        #expect(projection.contextualPage === shelf)
        fixture.coordinator.dismissOptions(leaseID: leaseID)
        #expect(!origin.isValid)
        #expect(dismissals == 1)
        #expect(fixture.surfaces[10]?.presentations.last?.showsWidgets == true)
        #expect(
            !fixture.coordinator.presentOptions(
                page     : shelf,
                leaseID  : leaseID,
                origin   : origin,
                onDismiss: {}
            )
        )
        fixture.coordinator.stop()
    }

    @Test
    func latestPendingVisibleClickWinsAndBackRejectsBothDelayedReplies() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 11])
        let sourceA = optionsWidgetID()
        let sourceB = optionsWidgetID()
        fixture.coordinator.register(try optionsWidget(sourceA))
        fixture.coordinator.register(try optionsWidget(sourceB))
        let shelf = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let original = try #require(fixture.surfaces[10]?.presentations.last)
        #expect(original.showsWidgets)
        #expect(!original.contextualPageIsSelected)
        let originA = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: sourceA, observedRevision: 1)
        )
        let originB = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: sourceB, observedRevision: 1)
        )
        #expect(!originA.isValid)
        #expect(originB.isValid)
        let leaseA = UUID()
        let leaseB = UUID()
        let pageA  = CoordinatorContextualPage(id: "detail-A", contentRevision: 1)
        let pageB  = CoordinatorContextualPage(id: "detail-B", contentRevision: 1)
        #expect(
            !fixture.coordinator.presentOptions(
                page     : pageA,
                leaseID  : leaseA,
                origin   : originA,
                onDismiss: {}
            )
        )
        #expect(fixture.surfaces[10]?.presentations.last?.showsWidgets == true)
        #expect(
            fixture.coordinator.presentOptions(
                page     : pageB,
                leaseID  : leaseB,
                origin   : originB,
                onDismiss: {}
            )
        )
        #expect(fixture.surfaces[10]?.presentations.last?.optionsPage === pageB)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[11]?.presentations.last?.optionsPage == nil)
        fixture.coordinator.dismissOptions(leaseID: leaseB)
        #expect(!originA.isValid)
        #expect(!originB.isValid)
        for (page, lease, origin) in [(pageA, leaseA, originA), (pageB, leaseB, originB)] {
            #expect(
                !fixture.coordinator.presentOptions(
                    page     : page,
                    leaseID  : lease,
                    origin   : origin,
                    onDismiss: {}
                )
            )
        }
        let restored = try #require(fixture.surfaces[10]?.presentations.last)
        #expect(restored.showsWidgets == original.showsWidgets)
        #expect(restored.contextualPageIsSelected == original.contextualPageIsSelected)
        #expect(restored.contextualPage === shelf)
        #expect(restored.optionsPage == nil)
        #expect(fixture.coordinator.expandedDisplayID == 10)
        fixture.coordinator.stop()
    }

    @Test
    func selectionSwitchCloseAndDisplayRemovalInvalidatePendingOrigins() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 11])
        let source  = optionsWidgetID()
        fixture.coordinator.register(try optionsWidget(source))
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let first = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
        )
        fixture.coordinator.setContextualPage(
            CoordinatorContextualPage(id: "shelf", contentRevision: 1),
            prefersDefault: false
        )
        fixture.coordinator.showContextualPage(on: 10)
        #expect(!first.isValid)
        #expect(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
                == nil
        )
        fixture.coordinator.showOrdinaryPage(on: 10)
        let second = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
        )
        fixture.surfaces[10]?.onCollapseRequested?()
        #expect(!second.isValid)
        let closing = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.onCollapseFinished?(closing)
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let third = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
        )
        fixture.inventory.entries = [fixture.entry(displayID: 11)]
        fixture.inventory.sendChange()
        #expect(!third.isValid)
        fixture.coordinator.stop()
    }

    @Test
    func widgetAndDisplayReplacementRevokePendingOrigins() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let source  = optionsWidgetID()
        fixture.coordinator.register(try optionsWidget(source))
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let first = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
        )
        fixture.coordinator.register(try optionsWidget(source))
        #expect(!first.isValid)
        let second = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
        )
        let entry                 = fixture.entry(displayID: 10)
        fixture.inventory.entries = [
            DisplayInventoryEntry(
                snapshot: entry.snapshot,
                identity: DisplayIdentity(rawValue: "replacement-display"),
                name    : entry.name
            )
        ]
        fixture.inventory.sendChange()
        #expect(!second.isValid)
        fixture.coordinator.stop()
    }

    @Test
    func activityTakingOverTheGridRevokesAPendingOrigin() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let source  = optionsWidgetID()
        fixture.coordinator.register(try optionsWidget(source))
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let origin = try #require(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
        )
        fixture.activityHost.present(CoordinatorActivityFixture(id: "music"))
        #expect(!origin.isValid)
        #expect(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
                == nil
        )
        #expect(
            !fixture.coordinator.presentOptions(
                page     : CoordinatorContextualPage(id: "detail", contentRevision: 1),
                leaseID  : UUID(),
                origin   : origin,
                onDismiss: {}
            )
        )
        fixture.coordinator.stop()
    }

    @Test
    func aWidgetWithoutAnOptionsPageCannotCaptureAnOrigin() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let source  = optionsWidgetID()
        fixture.coordinator.register(try optionsWidget(source, offersOptions: false))
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        #expect(
            fixture.coordinator.captureOptionsOrigin(widgetID: source, observedRevision: 1)
                == nil
        )
        fixture.coordinator.stop()
    }

    @Test
    func detailUsesAnExplicitNonactivatingKeyboardTarget() throws {
        let host                = NotchHostView(frame: CGRect(x: 0, y: 0, width: 640, height: 260))
        let panel               = NotchPanel(contentView: host)
        host.onOptionsDismissed = {}
        host.setBackButton(frame: CGRect(x: 12, y: 220, width: 28, height: 28), isVisible: true)
        host.setOptionsContent(
            AnyView(Text("Detail")),
            identity     : UUID(),
            frame        : CGRect(x: 20, y: 20, width: 600, height: 180),
            reducesMotion: true
        )
        #expect(panel.firstResponder is any NotchKeyboardFocusTarget)
        #expect(!(panel.firstResponder is NSView))
        let buttons = host.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }
        #expect(buttons.count == 2)
        for button in buttons {
            #expect(!button.acceptsFirstResponder)
            #expect(button.refusesFirstResponder)
            #expect(button.focusRingType == .none)
        }
        #expect(panel.canBecomeKey)
        host.clearOptionsContent()
        #expect(!(panel.firstResponder is any NotchKeyboardFocusTarget))
        #expect(!panel.canBecomeKey)
        panel.close()
    }

    @Test
    func escapeOnTheKeyboardTargetGoesBackAndOtherKeysAreSwallowed() throws {
        let host  = NotchHostView(frame: CGRect(x: 0, y: 0, width: 640, height: 260))
        let panel = NotchPanel(contentView: host)
        defer { panel.close() }
        var dismissals          = 0
        host.onOptionsDismissed = { dismissals += 1 }
        host.setOptionsContent(
            AnyView(Text("Detail")),
            identity     : UUID(),
            frame        : CGRect(x: 20, y: 20, width: 600, height: 180),
            reducesMotion: true
        )
        let target = try #require(panel.firstResponder)
        func key(_ code: UInt16) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with                       : .keyDown,
                location                   : .zero,
                modifierFlags              : [],
                timestamp                  : 0,
                windowNumber               : panel.windowNumber,
                context                    : nil,
                characters                 : "",
                charactersIgnoringModifiers: "",
                isARepeat                  : false,
                keyCode                    : code
            ))
        }
        target.keyDown(with: try key(0))
        #expect(dismissals == 0)
        target.keyDown(with: try key(53))
        #expect(dismissals == 1)
        host.clearOptionsContent()
        target.keyDown(with: try key(53))
        #expect(dismissals == 1)
    }

    @Test
    func aNewRevisionOfTheSamePageKeepsItsRoot() throws {
        let host     = NotchHostView(frame: CGRect(x: 0, y: 0, width: 640, height: 260))
        let panel    = NotchPanel(contentView: host)
        defer { panel.close() }
        let frame    = CGRect(x: 20, y: 20, width: 600, height: 180)
        let identity = UUID()
        weak var first : RootProbe?
        weak var second: RootProbe?
        do {
            let probe = RootProbe()
            first = probe
            host.setOptionsContent(AnyView(RootProbeView(probe: probe)), identity: identity, frame: frame, reducesMotion: true)
        }
        do {
            let probe = RootProbe()
            second = probe
            host.setOptionsContent(AnyView(RootProbeView(probe: probe)), identity: identity, frame: frame, reducesMotion: true)
        }
        // The page's nodes update through its store; the same page never swaps its root.
        #expect(first != nil)
        #expect(second == nil)
        #expect(host.visibleOptionsHostCount == 1)
        host.clearOptionsContent()
    }

    @Test(arguments: [false, true])
    func stoppingAControllerImmediatelyClearsOptionsRoots(reducesMotion: Bool) throws {
        let fixture = ControllerFixture(reducesMotion: reducesMotion)
        fixture.controller.start()
        fixture.controller.surface.setOptionsDismissHandler({})
        weak var outgoingAssets: OptionsLifetimeAssets?
        weak var documentAssets: OptionsLifetimeAssets?
        for id in ["outgoing", "incoming"] {
            let assets = OptionsLifetimeAssets()
            if id == "outgoing" { outgoingAssets = assets } else { documentAssets = assets }
            fixture.controller.surface.applyPresentation(
                DisplayPresentation(
                    primary                 : nil,
                    secondary               : nil,
                    notice                  : nil,
                    expanded                : nil,
                    expandedIsLiveActivity  : false,
                    showsWidgets            : false,
                    contextualPage          : nil,
                    contextualPageIsSelected: false,
                    widgetContentRevision   : 0,
                    style                   : .notch,
                    optionsPage             : try optionsPage(id: id, assets: assets),
                    optionsLeaseID          : UUID()
                )
            )
        }
        #expect(outgoingAssets != nil)
        #expect(documentAssets != nil)
        #expect(fixture.hostView.visibleOptionsHostCount > 0)
        fixture.controller.stop()
        #expect(fixture.hostView.visibleOptionsHostCount == 0)
        #expect(outgoingAssets == nil)
        #expect(documentAssets == nil)
    }

    @Test
    func optionsContentIsClippedBelowTheNavigationBand() throws {
        let host = NotchHostView(frame: CGRect(x: 0, y: 0, width: 440, height: 144))
        let panel = NotchPanel(contentView: host)
        defer { panel.close() }
        let frame = CGRect(x: 20, y: 16, width: 400, height: 92)
        host.setOptionsContent(
            AnyView(Color.red.frame(width: 400, height: 300)),
            identity     : UUID(),
            frame        : frame,
            reducesMotion: true
        )
        let nativeHosts = host.subviews.flatMap(\.subviews).compactMap {
            $0 as? NSHostingView<AnyView>
        }.filter { !$0.isHidden }
        let options = try #require(nativeHosts.first)
        #expect(nativeHosts.count == 1)
        #expect(options.frame == frame)
        #expect(options.clipsToBounds)
        options.layoutSubtreeIfNeeded()
        func findScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for child in view.subviews {
                if let scroll = findScrollView(in: child) { return scroll }
            }
            return nil
        }
        let scroll = try #require(findScrollView(in: options))
        let document = try #require(scroll.documentView)
        #expect(document.frame.height > scroll.contentView.bounds.height)
        let divider = try #require(host.subviews.flatMap { $0.layer?.sublayers ?? [] }.first {
            $0.name == "options.header.divider"
        })
        #expect(!divider.isHidden)
        #expect(divider.frame.minY >= frame.maxY)
        #expect(divider.frame.maxY <= host.bounds.maxY)
        host.clearOptionsContent()
        #expect(divider.isHidden)
    }

    @Test(arguments: [false, true])
    func nativeTransitionReleasesOutgoingDocumentAssets(reducesMotion: Bool) async throws {
        let host    = NotchHostView(frame: CGRect(x: 0, y: 0, width: 640, height: 260))
        let panel   = NotchPanel(contentView: host)
        defer { panel.close() }
        let frame   = CGRect(x: 20, y: 20, width: 600, height: 180)
        let context = NotchContextualPageContext(availableSize: frame.size)
        weak var outgoingAssets: OptionsLifetimeAssets?
        weak var incomingAssets: OptionsLifetimeAssets?
        do {
            let assets = OptionsLifetimeAssets()
            outgoingAssets = assets
            host.setOptionsContent(
                try optionsPage(id: "first", assets: assets).makeContentView(in: context),
                identity     : UUID(),
                frame        : frame,
                reducesMotion: reducesMotion
            )
        }
        host.layoutSubtreeIfNeeded()
        do {
            let assets = OptionsLifetimeAssets()
            incomingAssets = assets
            host.setOptionsContent(
                try optionsPage(id: "latest", assets: assets).makeContentView(in: context),
                identity     : UUID(),
                frame        : frame,
                reducesMotion: reducesMotion
            )
        }
        host.layoutSubtreeIfNeeded()
        // Both mounted document roots own assets while the finite transition is active.
        #expect(outgoingAssets != nil)
        #expect(incomingAssets != nil)
        try await settle { outgoingAssets == nil }
        #expect(outgoingAssets == nil)
        #expect(incomingAssets != nil)
        host.clearOptionsContent()
        #expect(incomingAssets == nil)
    }

    @Test
    func nativeTransitionRetargetKeepsAtMostTwoVisibleHostsAndClearsOutgoing() async throws {
        let host  = NotchHostView(frame: CGRect(x: 0, y: 0, width: 640, height: 260))
        let frame = CGRect(x: 20, y: 20, width: 600, height: 180)
        host.setContent(AnyView(Text("Grid")), frame: frame, isVisible: true)
        host.setOptionsContent(
            AnyView(Text("First")),
            identity     : UUID(),
            frame        : frame,
            reducesMotion: false
        )
        #expect(host.visibleOptionsHostCount <= 2)
        host.setOptionsContent(nil, identity: nil, frame: frame, reducesMotion: false)
        host.setOptionsContent(
            AnyView(Text("Latest")),
            identity     : UUID(),
            frame        : frame,
            reducesMotion: false
        )
        try await settle { host.visibleOptionsHostCount == 1 }
        #expect(host.visibleOptionsHostCount == 1)
        host.clearOptionsContent()
        #expect(host.visibleOptionsHostCount == 0)
    }

    /// settle waits for the 180 ms transition's cleanup, which runs on the main actor: under a
    /// full parallel test run the main actor can be busy for seconds, so a fixed sleep is flaky.
    private func settle(
        within timeout: Duration = .seconds(20),
        until condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        try await Task.sleep(for: .milliseconds(200))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// optionsPage is a page whose content view owns `assets`, so a weak reference tells whether
    /// a host still holds the root it was given.
    private func optionsPage(
        id    : String,
        assets: OptionsLifetimeAssets
    ) throws -> CoordinatorContextualPage {
        CoordinatorContextualPage(id: id, contentRevision: 1) {
            AnyView(OptionsLifetimeView(assets: assets))
        }
    }

    /// optionsWidget is a plugin widget at revision 1 that offers an options page, or none.
    private func optionsWidget(
        _ id         : WidgetIdentifier,
        offersOptions: Bool = true
    ) throws -> PluginWidget {
        let key      = PluginPublicationKey(plugin: PluginID(rawValue: "com.example.options")!, feature: id.rawValue.components(separatedBy: "/").last!, surface: .widget)
        let document = try PluginDocument(
            root         : PluginNode(.button(action: "open"), children: [PluginNode(.text("Widget"))]),
            optionsRoot  : offersOptions ? PluginNode(.text("Options")) : nil,
            optionsAction: offersOptions ? "open" : nil
        )
        var publisher = PluginPublicationStore()
        let store     = PluginNodeStore(key: key, submit: { _ in })
        let change    = publisher.apply(document, staleAfter: nil, for: key, at: .now)
        store.apply(try #require(change))
        return PluginWidget(id: id, sizes: [], store: store, visibility: { _ in }, supportsFullscreen: true)
    }

    private func optionsWidgetID() -> WidgetIdentifier {
        WidgetIdentifier("plugin:com.example.options/f" + UUID().uuidString.prefix(8).lowercased())
    }
}

/// OptionsLifetimeAssets is owned by an options page's root view; weak test references cannot
/// keep it alive after both reusable hosts discard that root.
private final class OptionsLifetimeAssets {}

private struct OptionsLifetimeView: View {

    let assets: OptionsLifetimeAssets

    var body: some View {
        Text("Options")
    }
}

/// RootProbe tells, through a weak reference, whether a host still holds the root it was given.
private final class RootProbe {}

private struct RootProbeView: View {

    let probe: RootProbe

    var body: some View {
        Text("Probe")
    }
}
