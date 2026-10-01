//
//  AddonPresentationTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import CascadeRuntime
import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct AddonPresentationTests {

    @Test
    func retainedWidgetContextCannotInvalidateAfterSuspend() {
        let host              = WidgetHost()
        let widget            = WidgetFixture()
        var changes           = 0
        host.onContentChanged = { changes += 1 }
        host.register(widget)
        host.update(state: .open)

        let retained = widget.context
        host.update(state: .closed)
        retained?.setNeedsContent()

        #expect(changes == 0)
        #expect(widget.suspensions == 1)
    }

    @Test
    func unregisterRevokesContextBeforeSuspendingWidget() {
        let host              = WidgetHost()
        let widget            = WidgetFixture()
        var changes           = 0
        host.onContentChanged = { changes += 1 }
        host.register(widget)
        host.update(state: .open)

        let before = changes
        host.unregister(id: widget.id)
        #expect(changes == before + 1)

        widget.context?.setNeedsContent()
        #expect(changes == before + 1)
    }

    @Test
    func identicalSnapshotDoesNotRebuildPresentation() throws {
        let sink        = PresentationSinkFixture()
        let bridge      = AddonPresentationBridge(sink: sink)
        let publication = try fixturePublication(
            kind    : .widget,
            revision: 3,
            text    : "Ready"
        )

        bridge.apply([publication])
        bridge.apply([publication])

        #expect(sink.registeredWidgets.count == 1)
        #expect(sink.unregisteredWidgetIDs.isEmpty)
    }

    @Test
    func timelineContentChangeAtSameWireRevisionRebuildsOnlyThatPresentation() throws {
        var now         = Date(timeIntervalSince1970: 100)
        let sink        = PresentationSinkFixture()
        let bridge      = AddonPresentationBridge(sink: sink, now: { now })
        let publication = try timelinePublication(
            revision: 4,
            first   : "Soon",
            second  : "Now"
        )

        bridge.apply([publication])
        let first = try #require(sink.registeredWidgets.last as? SnapshotWidget)
        #expect(first.document.accessibilityLabel == "Soon")

        now = Date(timeIntervalSince1970: 200)
        bridge.apply([publication])
        let second = try #require(sink.registeredWidgets.last as? SnapshotWidget)
        #expect(second.document.accessibilityLabel == "Now")
        #expect(sink.registeredWidgets.count == 1)
        #expect(sink.unregisteredWidgetIDs.isEmpty)
    }

    @Test
    func snapshotRemainsVisibleWithoutProducerObject() throws {
        let sink   = PresentationSinkFixture()
        let bridge = AddonPresentationBridge(sink: sink)
        bridge.apply([try fixturePublication(kind: .widget, revision: 1, text: "Durable")])

        let widget = try #require(sink.registeredWidgets.first as? SnapshotWidget)
        #expect(widget.document.accessibilityLabel == "Durable")

        _ = widget.makeContentView()
    }

    @Test
    func retainedAssetResolverPreservesItsObservedPublicationRevision() {
        let assets = AssetResolverFixture()
        let id     = publicationID()
        let older  = ScopedAssetResolver(
            base               : assets,
            publicationID      : id,
            publicationRevision: 7
        )
        let newer = ScopedAssetResolver(
            base               : assets,
            publicationID      : id,
            publicationRevision: 8
        )

        _ = older.image(for: "cover")
        _ = newer.image(for: "cover")
        _ = older.image(for: "cover")

        #expect(assets.requests == [
            .init(assetID: "cover", publicationID: id, revision: 7),
            .init(assetID: "cover", publicationID: id, revision: 8),
            .init(assetID: "cover", publicationID: id, revision: 7)
        ])
    }

    @Test
    func sensitiveWidgetRedactsBeforeAssetResolutionAndAccessibility() throws {
        let sink   = PresentationSinkFixture()
        let assets = AssetResolverFixture()
        let bridge = AddonPresentationBridge(sink: sink, assets: assets)
        bridge.apply([try sensitiveImageWidget()])

        let widget = try #require(sink.registeredWidgets.first as? SnapshotWidget)
        #expect(widget.accessibilityLabel == "Sensitive content hidden")

        _ = widget.makeContentView()
        #expect(assets.requests.isEmpty)
    }

    @Test
    func removalRevokesCopiedActionCallback() throws {
        let sink    = PresentationSinkFixture()
        var actions: [String] = []
        let bridge  = AddonPresentationBridge(
            sink    : sink,
            onAction: { _, _, action in actions.append(action.id) }
        )
        let publication = try actionWidget()
        bridge.apply([publication])

        let widget = try #require(sink.registeredWidgets.first as? SnapshotWidget)
        widget.activate(in: WidgetContext.testContext())

        let copied = widget.copiedActionForTesting()
        copied(try ActionDescriptor(id: "run", label: "Run", payload: Data()))
        bridge.apply([])
        copied(try ActionDescriptor(id: "run", label: "Run", payload: Data()))

        #expect(actions == ["run"])
        #expect(sink.unregisteredWidgetIDs == [widget.id])
    }

    @Test
    func copiedWidgetActionCannotCrossSuspendAndReactivation() throws {
        let sink    = PresentationSinkFixture()
        var actions: [String] = []
        let bridge  = AddonPresentationBridge(
            sink    : sink,
            onAction: { _, _, action in actions.append(action.id) }
        )
        bridge.apply([try actionWidget()])

        let widget = try #require(sink.registeredWidgets.first as? SnapshotWidget)
        widget.activate(in: .testContext())

        let old = widget.copiedActionForTesting()
        widget.suspend()
        widget.activate(in: .testContext())
        old(try ActionDescriptor(id: "run", label: "Run", payload: Data()))
        widget.dispatchForTesting(try ActionDescriptor(id: "run", label: "Run", payload: Data()))

        #expect(actions == ["run"])
    }

    @Test
    func noticeContentUpdateKeepsOriginalLifetimeAndCannotResurrectRemoval() throws {
        let sink   = PresentationSinkFixture()
        let bridge = AddonPresentationBridge(sink: sink)

        bridge.apply([try fixturePublication(kind: .notice, revision: 1, text: "Started")])
        bridge.apply([try fixturePublication(kind: .notice, revision: 2, text: "Finished")])
        #expect(sink.shownNotices.count == 1)
        #expect(sink.updatedNotices.count == 1)

        bridge.apply([])
        bridge.apply([try fixturePublication(kind: .notice, revision: 3, text: "Late")])
        #expect(sink.shownNotices.count == 1)
        #expect(sink.updatedNotices.count == 1)
    }

    @Test
    func activityContentUpdatesDoNotRenewTheEightHourAnchor() throws {
        var now    = Date(timeIntervalSince1970: 100)
        let sink   = PresentationSinkFixture()
        let bridge = AddonPresentationBridge(sink: sink, now: { now })

        bridge.apply([try fixturePublication(kind: .activity, revision: 1, text: "One")])
        now = Date(timeIntervalSince1970: 1_000)
        bridge.apply([try fixturePublication(kind: .activity, revision: 2, text: "Two")])

        let first  = try #require(sink.presentedActivities.first as? SnapshotActivity)
        let second = try #require(sink.presentedActivities.last as? SnapshotActivity)
        #expect(first.lifetime.startedAt == Date(timeIntervalSince1970: 100))
        #expect(second.lifetime.startedAt == first.lifetime.startedAt)
        #expect(second.lifetime.expiresAt == first.lifetime.expiresAt)
    }

    @Test(arguments: [Publication.Kind.activity, .notice])
    func copiedActivityActionCannotCrossSuspendOrExpiry(kind: Publication.Kind) throws {
        var now     = Date(timeIntervalSince1970: 100)
        var actions = 0
        let lease   = ActionLease(
            expiresAt: Date(timeIntervalSince1970: 150),
            now      : { now }
        ) { _ in actions += 1 }
        let set = try actionPresentation(kind: kind)

        let copied: @MainActor @Sendable (ActionDescriptor) -> Void
        if kind == .activity {
            let activity = SnapshotActivity(
                id      : "a",
                sourceID: "addon:test",
                revision: 1,
                content : set,
                lifetime: .init(startedAt: now),
                assets  : ScopedAssetResolver(
                    base               : AssetResolverFixture(),
                    publicationID      : publicationID(),
                    publicationRevision: 1
                ),
                actions : lease
            )
            activity.activate(in: LiveActivityContext(onInvalidate: {}))
            copied = activity.copiedActionForTesting()
            activity.suspend()
            activity.activate(in: LiveActivityContext(onInvalidate: {}))
        } else {
            let notice = SnapshotNotice(
                id      : "n",
                sourceID: "addon:test",
                revision: 1,
                content : set,
                assets  : ScopedAssetResolver(
                    base               : AssetResolverFixture(),
                    publicationID      : publicationID(),
                    publicationRevision: 1
                ),
                actions : lease
            )
            notice.activate(in: LiveActivityContext(onInvalidate: {}))
            copied = notice.copiedActionForTesting()
            notice.suspend()
            notice.activate(in: LiveActivityContext(onInvalidate: {}))
        }

        copied(try ActionDescriptor(id: "run", label: "Run", payload: Data()))
        #expect(actions == 0)

        now = Date(timeIntervalSince1970: 151)
        lease.dispatch(try ActionDescriptor(id: "run", label: "Run", payload: Data()))
        #expect(actions == 0)
    }

    @Test
    func replacementActivityActionsFollowRetainedInstanceVisibility() throws {
        let instant = Date(timeIntervalSince1970: 100)
        var actions: [String] = []
        let content = try actionPresentation(kind: .activity)
        let assets  = ScopedAssetResolver(
            base               : AssetResolverFixture(),
            publicationID      : publicationID(),
            publicationRevision: 1
        )
        let old = SnapshotActivity(
            id      : "shared",
            sourceID: "addon:test",
            revision: 1,
            content : content,
            lifetime: .init(startedAt: instant),
            assets  : assets,
            actions : ActionLease(expiresAt: .distantFuture) { _ in actions.append("old") }
        )
        let replacement = SnapshotActivity(
            id      : "shared",
            sourceID: "addon:test",
            revision: 2,
            content : content,
            lifetime: .init(startedAt: instant),
            assets  : assets,
            actions : ActionLease(expiresAt: .distantFuture) { _ in actions.append("replacement") }
        )
        let action = try ActionDescriptor(
            id     : "run",
            label  : "Run",
            payload: Data()
        )

        let host = LiveActivityHost(now: { instant })
        host.setVisible(true)
        host.present(old)
        host.setVisibleActivities([old])

        let retainedOldAction = old.copiedActionForTesting()
        host.present(replacement)
        host.setVisibleActivities([old, replacement])

        let replacementAction = replacement.copiedActionForTesting()
        retainedOldAction(action)
        replacementAction(action)
        #expect(actions == ["old", "replacement"])

        host.setVisibleActivities([replacement])
        retainedOldAction(action)
        replacementAction(action)
        #expect(actions == ["old", "replacement", "replacement"])

        host.stop()
    }

    @Test
    func endingReplacementRevokesActionsFromEveryRetainedSameIDInstance() throws {
        let instant = Date(timeIntervalSince1970: 100)
        var actions: [String] = []
        let content = try actionPresentation(kind: .activity)
        let assets  = ScopedAssetResolver(
            base               : AssetResolverFixture(),
            publicationID      : publicationID(),
            publicationRevision: 1
        )
        let old = SnapshotActivity(
            id      : "shared",
            sourceID: "addon:test",
            revision: 1,
            content : content,
            lifetime: .init(startedAt: instant),
            assets  : assets,
            actions : ActionLease { _ in actions.append("old") }
        )
        let replacement = SnapshotActivity(
            id      : "shared",
            sourceID: "addon:test",
            revision: 2,
            content : content,
            lifetime: .init(startedAt: instant),
            assets  : assets,
            actions : ActionLease { _ in actions.append("replacement") }
        )
        let action = try ActionDescriptor(
            id     : "run",
            label  : "Run",
            payload: Data()
        )

        let host = LiveActivityHost(now: { instant })
        host.setVisible(true)
        host.present(old)
        host.setVisibleActivities([old])

        let oldAction = old.copiedActionForTesting()
        host.present(replacement)
        host.setVisibleActivities([old, replacement])

        let replacementAction = replacement.copiedActionForTesting()
        host.end(id: replacement.id)
        oldAction(action)
        replacementAction(action)
        #expect(actions.isEmpty)

        host.stop()
    }

    @Test
    func refreshingOneWidgetDoesNotRebuildUnaffectedWidgetFactory() {
        let host   = WidgetHost()
        let first  = WidgetFixture(id: "first")
        let second = WidgetFixture(id: "second")
        host.register(first)
        host.register(second)
        host.update(state: .open)

        host.onContentChanged = {
            _ = host.makeContentView(
                interior     : CGRect(x: 0, y: 0, width: 400, height: 120),
                notchWidth   : 100,
                topBandHeight: 30,
                hostHeight   : 120
            )
        }
        _ = host.makeContentView(
            interior     : CGRect(x: 0, y: 0, width: 400, height: 120),
            notchWidth   : 100,
            topBandHeight: 30,
            hostHeight   : 120
        )

        let unaffectedCount = second.factoryCount
        first.context?.setNeedsContent()
        #expect(first.factoryCount == 2)
        #expect(second.factoryCount == unaffectedCount)
    }

    @Test
    func futureOnlyRevisionKeepsIdentityPendingUntilFirstEntryIsDue() throws {
        var now    = Date(timeIntervalSince1970: 100)
        let sink   = PresentationSinkFixture()
        let bridge = AddonPresentationBridge(sink: sink, now: { now })
        bridge.apply([try fixturePublication(kind: .widget, revision: 1, text: "Current")])

        let future = try futureTimelinePublication(
            kind    : .widget,
            revision: 2,
            due     : 200,
            text    : "Scheduled"
        )
        bridge.apply([future])
        #expect(sink.unregisteredWidgetIDs.count == 1)

        now = Date(timeIntervalSince1970: 200)
        bridge.apply([future])
        #expect(sink.registeredWidgets.count == 2)
        #expect((sink.registeredWidgets.last as? SnapshotWidget)?.document.accessibilityLabel == "Scheduled")
    }

    @Test
    func futureOnlyActivityRevisionPreservesOriginalResidenceAnchor() throws {
        var now    = Date(timeIntervalSince1970: 100)
        let sink   = PresentationSinkFixture()
        let bridge = AddonPresentationBridge(sink: sink, now: { now })
        bridge.apply([try fixturePublication(kind: .activity, revision: 1, text: "Current")])

        let first  = try #require(sink.presentedActivities.last as? SnapshotActivity)
        let future = try futureTimelinePublication(
            kind    : .activity,
            revision: 2,
            due     : 200,
            text    : "Scheduled"
        )
        bridge.apply([future])
        now = Date(timeIntervalSince1970: 200)
        bridge.apply([future])

        let second = try #require(sink.presentedActivities.last as? SnapshotActivity)
        #expect(second.lifetime.startedAt == first.lifetime.startedAt)
    }

    @Test
    func firstDueNoticeShowsOnceAndLaterTimelineEntryUsesNonReplayingUpdate() throws {
        var now       = Date(timeIntervalSince1970: 100)
        let sink      = PresentationSinkFixture()
        let bridge    = AddonPresentationBridge(sink: sink, now: { now })
        let firstSet  = try fixturePublication(kind: .notice, revision: 1, text: "First").content!
        let secondSet = try fixturePublication(kind: .notice, revision: 1, text: "Second").content!

        let notice = try Publication(
            id         : publicationID(),
            revision   : 1,
            kind       : .notice,
            content    : nil,
            timeline   : [
                try ScheduledEntry(date: Date(timeIntervalSince1970: 200), content: firstSet),
                try ScheduledEntry(date: Date(timeIntervalSince1970: 250), content: secondSet),
            ],
            expiresAt  : Date(timeIntervalSince1970: 300),
            stalePolicy: .remove
        )
        bridge.apply([notice])
        #expect(sink.shownNotices.isEmpty)

        now = Date(timeIntervalSince1970: 200)
        bridge.apply([notice])
        #expect(sink.shownNotices.count == 1)

        now = Date(timeIntervalSince1970: 250)
        bridge.apply([notice])
        #expect(sink.shownNotices.count == 1)
        #expect(sink.updatedNotices.count == 1)
    }

    @Test
    func storeToBridgePreservesPendingIdentityAndDisableRemovesFutureContent() async throws {
        var now     = Date(timeIntervalSince1970: 100)
        let store   = PublicationStore(now: { Date(timeIntervalSince1970: 100) })
        let sink    = PresentationSinkFixture()
        let bridge  = AddonPresentationBridge(sink: sink, now: { now })
        let initial = try fixturePublication(
            kind    : .widget,
            revision: 1,
            text    : "Current"
        )
        try await store.accept(initial, owner: initial.id.addonID)
        bridge.apply(await store.snapshot(at: now))

        let future = try futureTimelinePublication(
            kind    : .widget,
            revision: 2,
            due     : 200,
            text    : "Scheduled"
        )
        try await store.accept(future, owner: initial.id.addonID)
        bridge.apply(await store.snapshot(at: now))
        #expect(sink.unregisteredWidgetIDs.count == 1)
        #expect(sink.registeredWidgets.count == 1)

        now = Date(timeIntervalSince1970: 200)
        bridge.apply(await store.snapshot(at: now))
        #expect((sink.registeredWidgets.last as? SnapshotWidget)?.document.accessibilityLabel == "Scheduled")
        #expect(sink.registeredWidgets.count == 2)

        let next = try futureTimelinePublication(
            kind    : .widget,
            revision: 3,
            due     : 300,
            text    : "Revoked"
        )
        try await store.accept(next, owner: initial.id.addonID)
        bridge.apply(await store.snapshot(at: now))
        await store.remove(owner: initial.id.addonID)
        bridge.apply(await store.snapshot(at: now))

        now = Date(timeIntervalSince1970: 300)
        bridge.apply(await store.snapshot(at: now))
        #expect(sink.registeredWidgets.count == 2)
        #expect(await store.retainedBytes == 0)
    }

    @Test
    func tombstoneSaturationStillAllowsExistingPublicationUpdates() throws {
        let sink   = PresentationSinkFixture()
        let bridge = AddonPresentationBridge(sink: sink)
        let active = try fixturePublication(
            kind    : .widget,
            revision: 1,
            text    : "One"
        )
        bridge.apply([active])

        for index in 0...4_096 {
            let churn = try fixturePublication(
                kind    : .widget,
                revision: 1,
                text    : "Churn",
                id      : publicationID(index: index + 10)
            )
            bridge.apply([active, churn])
            bridge.apply([active])
        }

        bridge.apply([try fixturePublication(kind: .widget, revision: 2, text: "Two")])
        #expect((sink.registeredWidgets.first as? SnapshotWidget)?.document.accessibilityLabel == "Two")
    }
}

private extension WidgetContext {

    static func testContext() -> WidgetContext { WidgetContext(state: .open, requestContent: {}) }
}

private func fixturePublication(
    kind    : Publication.Kind,
    revision: UInt64,
    text    : String,
    id      : PublicationID = publicationID()
) throws -> Publication {
    let document = try ContentDocument(
        root              : try ContentNode(
            kind    : .text,
            text    : text,
            assetID : nil,
            value   : nil,
            deadline: nil,
            actionID: nil,
            children: nil
        ),
        privacy           : .publicContent,
        accessibilityLabel: text
    )

    let set: PresentationSet
    switch kind {
        case .widget:
            set = try PresentationSet(
                widget         : document,
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            )

        case .activity:
            set = try PresentationSet(
                widget         : nil,
                compactLeading : document,
                compactTrailing: document,
                minimal        : document,
                expanded       : document
            )

        case .notice:
            set = try PresentationSet(
                widget         : nil,
                compactLeading : document,
                compactTrailing: document,
                minimal        : document,
                expanded       : nil
            )
    }

    return try Publication(
        id         : id,
        revision   : revision,
        kind       : kind,
        content    : set,
        timeline   : nil,
        expiresAt  : Date(timeIntervalSince1970: 4_000_000_000),
        stalePolicy: .remove
    )
}

private func timelinePublication(
    revision: UInt64,
    first   : String,
    second  : String
) throws -> Publication {
    let firstContent  = try fixturePublication(kind: .widget, revision: revision, text: first).content!
    let secondContent = try fixturePublication(kind: .widget, revision: revision, text: second).content!

    return try Publication(
        id         : publicationID(),
        revision   : revision,
        kind       : .widget,
        content    : nil,
        timeline   : [
            try ScheduledEntry(date: Date(timeIntervalSince1970: 50), content: firstContent),
            try ScheduledEntry(date: Date(timeIntervalSince1970: 150), content: secondContent)
        ],
        expiresAt  : Date(timeIntervalSince1970: 10_000),
        stalePolicy: .remove
    )
}

private func sensitiveImageWidget() throws -> Publication {
    let node = try ContentNode(
        kind              : .image,
        text              : nil,
        assetID           : "secret",
        value             : nil,
        deadline          : nil,
        actionID          : nil,
        children          : nil,
        accessibilityLabel: "Secret photo"
    )
    let document = try ContentDocument(
        root              : node,
        privacy           : .sensitive,
        accessibilityLabel: "Private account balance",
        assetIDs          : ["secret"]
    )
    let set = try PresentationSet(
        widget         : document,
        compactLeading : nil,
        compactTrailing: nil,
        minimal        : nil,
        expanded       : nil
    )

    return try Publication(
        id         : publicationID(),
        revision   : 1,
        kind       : .widget,
        content    : set,
        timeline   : nil,
        expiresAt  : Date(timeIntervalSince1970: 4_000_000_000),
        stalePolicy: .remove
    )
}

private func actionWidget() throws -> Publication {
    let node = try ContentNode(
        kind         : .action,
        text         : "Run",
        assetID      : nil,
        value        : nil,
        deadline     : nil,
        actionID     : "run",
        children     : nil,
        actionPayload: Data()
    )
    let document = try ContentDocument(
        root              : node,
        privacy           : .publicContent,
        accessibilityLabel: "Run action"
    )
    let set = try PresentationSet(
        widget         : document,
        compactLeading : nil,
        compactTrailing: nil,
        minimal        : nil,
        expanded       : nil
    )

    return try Publication(
        id         : publicationID(),
        revision   : 1,
        kind       : .widget,
        content    : set,
        timeline   : nil,
        expiresAt  : Date(timeIntervalSince1970: 4_000_000_000),
        stalePolicy: .remove
    )
}

private func actionPresentation(kind: Publication.Kind) throws -> PresentationSet {
    let node = try ContentNode(
        kind         : .action,
        text         : "Run",
        assetID      : nil,
        value        : nil,
        deadline     : nil,
        actionID     : "run",
        children     : nil,
        actionPayload: Data()
    )
    let document = try ContentDocument(
        root              : node,
        privacy           : .publicContent,
        accessibilityLabel: "Run"
    )

    return kind == .activity
        ? try PresentationSet(
            widget         : nil,
            compactLeading : document,
            compactTrailing: document,
            minimal        : document,
            expanded       : document
        )
        : try PresentationSet(
            widget         : nil,
            compactLeading : document,
            compactTrailing: document,
            minimal        : document,
            expanded       : nil
        )
}

private func futureTimelinePublication(
    kind    : Publication.Kind,
    revision: UInt64,
    due     : TimeInterval,
    text    : String
) throws -> Publication {
    let content = try fixturePublication(kind: kind, revision: revision, text: text).content!

    return try Publication(
        id         : publicationID(),
        revision   : revision,
        kind       : kind,
        content    : nil,
        timeline   : [try ScheduledEntry(date: Date(timeIntervalSince1970: due), content: content)],
        expiresAt  : Date(timeIntervalSince1970: 1_000),
        stalePolicy: .remove
    )
}

private func publicationID() -> PublicationID {
    PublicationID(
        addonID   : AddonID(rawValue: "com.example.addon")!,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        sessionID : UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    )
}

private func publicationID(index: Int) -> PublicationID {
    PublicationID(
        addonID   : AddonID(rawValue: "com.example.addon")!,
        instanceID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
        sessionID : UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    )
}
