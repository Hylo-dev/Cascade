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
        let widgetID =
            "addon:\(source.addonID.rawValue):\(source.sessionID.uuidString):\(source.instanceID.uuidString)"
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
        #expect(panel.firstResponder is OptionsBackButton)
        #expect(panel.canBecomeKey)
        host.clearOptionsContent()
        panel.close()
    }

    @Test
    func stoppingAControllerImmediatelyClearsOptionsRoots() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.start()
        fixture.controller.surface.setOptionsDismissHandler({})
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
                optionsPage             : CoordinatorContextualPage(id: "detail", contentRevision: 1),
                optionsLeaseID          : UUID()
            )
        )
        #expect(fixture.hostView.retainedOptionsHostCount > 0)
        fixture.controller.stop()
        #expect(fixture.hostView.retainedOptionsHostCount == 0)
    }

    @Test
    func nativeTransitionRetargetKeepsTwoHostsAndClearsOutgoing() async throws {
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
        #expect(host.retainedOptionsHostCount <= 2)
        host.setOptionsContent(nil, identity: nil, revision: 0, frame: frame, reducesMotion: false)
        host.setOptionsContent(
            AnyView(Text("Latest")),
            identity     : UUID(),
            revision     : 1,
            frame        : frame,
            reducesMotion: false
        )
        try await Task.sleep(for: .milliseconds(250))
        #expect(host.retainedOptionsHostCount == 1)
        host.clearOptionsContent()
        #expect(host.retainedOptionsHostCount == 0)
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
