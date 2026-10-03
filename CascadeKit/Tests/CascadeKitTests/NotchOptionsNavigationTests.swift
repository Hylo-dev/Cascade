//
//  NotchOptionsNavigationTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CascadePresentation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct NotchOptionsNavigationTests {

    @Test
    func backKeepsContextualSlotAndRejectsDelayedOpening() throws {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10])
        let source   = try publicationID()
        fixture.coordinator.register(try snapshot(source))
        let shelf = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        #expect(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 2)
                == nil
        )
        let origin = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
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
        let sourceA = try publicationID()
        let sourceB = try publicationID()
        fixture.coordinator.register(try snapshot(sourceA))
        fixture.coordinator.register(try snapshot(sourceB))
        let shelf = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let original = try #require(fixture.surfaces[10]?.presentations.last)
        #expect(original.showsWidgets)
        #expect(!original.contextualPageIsSelected)
        let originA = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: sourceA, observedRevision: 1)
        )
        let originB = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: sourceB, observedRevision: 1)
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
        let source  = try publicationID()
        fixture.coordinator.register(try snapshot(source))
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let first = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
        )
        fixture.coordinator.setContextualPage(
            CoordinatorContextualPage(id: "shelf", contentRevision: 1),
            prefersDefault: false
        )
        fixture.coordinator.showContextualPage(on: 10)
        #expect(!first.isValid)
        #expect(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
                == nil
        )
        fixture.coordinator.showOrdinaryPage(on: 10)
        let second = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
        )
        fixture.surfaces[10]?.onCollapseRequested?()
        #expect(!second.isValid)
        let closing = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.onCollapseFinished?(closing)
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let third = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
        )
        fixture.inventory.entries = [fixture.entry(displayID: 11)]
        fixture.inventory.sendChange()
        #expect(!third.isValid)
        fixture.coordinator.stop()
    }

    @Test
    func widgetAndDisplayReplacementRevokePendingOrigins() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let source  = try publicationID()
        fixture.coordinator.register(try snapshot(source))
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let first = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
        )
        fixture.coordinator.register(try snapshot(source))
        #expect(!first.isValid)
        let second = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
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
        let source  = try publicationID()
        fixture.coordinator.register(try snapshot(source))
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        let origin = try #require(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
        )
        fixture.activityHost.present(CoordinatorActivityFixture(id: "music"))
        #expect(!origin.isValid)
        #expect(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
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
    func redactedSnapshotCannotCaptureAnOrigin() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let source  = try publicationID()
        let widget  = try SnapshotWidget(
            id:
                "addon:\(source.addonID.rawValue):\(source.sessionID.uuidString):\(source.instanceID.uuidString)",
            document              : ContentDocument(
                root              : .text("Secret"),
                privacy           : .sensitive,
                accessibilityLabel: "Secret"
            ),
            assets                 : ScopedAssetResolver(
                base               : EmptyAddonAssetResolver(),
                publicationID      : source,
                publicationRevision: 1
            ),
            actions: ActionLease { _ in }
        )
        fixture.coordinator.register(widget)
        fixture.coordinator.start()
        fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        #expect(
            fixture.coordinator.captureOptionsOrigin(publicationID: source, observedRevision: 1)
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
            revision     : 1,
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
        panel.close()
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
                revision     : 1,
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
                revision     : 1,
                frame        : frame,
                reducesMotion: reducesMotion
            )
        }
        host.layoutSubtreeIfNeeded()
        // Both mounted document roots own assets while the finite transition is active.
        #expect(outgoingAssets != nil)
        #expect(incomingAssets != nil)
        try await Task.sleep(for: .milliseconds(250))
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
            revision     : 1,
            frame        : frame,
            reducesMotion: false
        )
        #expect(host.visibleOptionsHostCount <= 2)
        host.setOptionsContent(nil, identity: nil, revision: 0, frame: frame, reducesMotion: false)
        host.setOptionsContent(
            AnyView(Text("Latest")),
            identity     : UUID(),
            revision     : 1,
            frame        : frame,
            reducesMotion: false
        )
        try await Task.sleep(for: .milliseconds(250))
        #expect(host.visibleOptionsHostCount == 1)
        host.clearOptionsContent()
        #expect(host.visibleOptionsHostCount == 0)
    }

    /// optionsPage uses the real snapshot document renderer so the weak resolver
    /// tracks retained document assets rather than a host's visibility flag.
    private func optionsPage(
        id    : String,
        assets: OptionsLifetimeAssets
    ) throws -> SnapshotOptionsPage {
        try SnapshotOptionsPage(
            id      : id,
            document: ContentDocument(
                root              : .text(id),
                privacy           : .publicContent,
                accessibilityLabel: id
            ),
            assets : assets,
            actions: ActionLease { _ in }
        )
    }

    private func snapshot(_ source: PublicationID) throws -> SnapshotWidget {
        try SnapshotWidget(
            id:
                "addon:\(source.addonID.rawValue):\(source.sessionID.uuidString):\(source.instanceID.uuidString)",
            document              : ContentDocument(
                root              : .text("Widget"),
                privacy           : .publicContent,
                accessibilityLabel: "Widget"
            ),
            assets                 : ScopedAssetResolver(
                base               : EmptyAddonAssetResolver(),
                publicationID      : source,
                publicationRevision: 1
            ),
            actions: ActionLease { _ in }
        )
    }

    private func publicationID() throws -> PublicationID {
        PublicationID(
            addonID   : try #require(AddonID(rawValue: "com.example.options")),
            instanceID: UUID(),
            sessionID : UUID()
        )
    }
}

/// OptionsLifetimeAssets is owned by the real snapshot document root; weak test
/// references cannot keep it alive after both reusable hosts discard that root.
@MainActor
private final class OptionsLifetimeAssets: ContentAssetResolving {

    func image(for assetID: String) -> Image? { nil }
}
