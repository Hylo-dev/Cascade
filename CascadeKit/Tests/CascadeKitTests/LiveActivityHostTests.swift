//
//  LiveActivityHostTests.swift
//  CascadeKitTests
//

import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
private extension LiveActivityHost {
    var currentActivity: (any NotchActivity)? {
        switch expansionSelection {
        case .none:
            selection.notice ?? selection.primary
        case .activity:
            selection.expanded ?? selection.primary
        case .fallback:
            selection.expanded
        case .widgets:
            nil
        }
    }

    var secondaryActivity: (any NotchActivity)? {
        guard expansionSelection == .none, selection.notice == nil else { return nil }
        return selection.secondary
    }

    func setExpanded(
        _ expanded : Bool,
        activityID: String? = nil
    ) {
        guard expanded else {
            setExpansion(.none)
            return
        }
        if let activityID {
            setExpansion(.activity(activityID))
        } else if let primary = selection.primary {
            setExpansion(.activity(primary.id))
        } else {
            setExpansion(.fallback)
        }
    }
}

@MainActor
struct LiveActivityHostTests {
    @Test
    func synchronousRemovalDuringActivationCannotActivateALaterSnapshotEntry() {
        let host = LiveActivityHost()
        let first = ReentrantLiveFixture("first", sourceID: "source")
        let second = ReentrantLiveFixture("second", sourceID: "source")
        var removed = false
        let removeSource = {
            guard !removed else { return }
            removed = true
            host.dismissActivities(from: "source")
        }
        first.onActivate = removeSource
        second.onActivate = removeSource
        host.present(first)
        host.present(second)
        host.setVisible(true)

        host.setVisibleActivities([first, second])

        #expect(first.activations == first.suspensions)
        #expect(second.activations == second.suspensions)
        #expect(!host.isPresentationValid(first))
        #expect(!host.isPresentationValid(second))
    }

    @Test
    func copiesShareActivationUntilLastPresentationLeaves() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        host.setVisible(true)
        host.present(music)
        var changes = 0
        host.onChange = { changes += 1 }
        host.setVisibleActivities([music, music])
        host.setVisibleActivities([music])
        #expect(music.activations == 1)
        #expect(changes == 0)
        host.setExpansion(.activity(music.id))
        #expect(host.selection.primary?.id == music.id)
        #expect(host.selection.expanded?.id == music.id)
        host.setVisibleActivities([music])
        #expect(music.suspensions == 0)
        host.setVisibleActivities([])
        #expect(music.suspensions == 1)
        host.stop()
    }

    @Test
    func noticeOverrideDoesNotEraseCompactLiveSelection() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        let timer = LiveFixture("timer", sourceID: "timer", relevance: 0.1)
        let notice = NoticeFixture("device")
        host.present(music)
        host.present(timer)
        host.showNotice(notice)
        #expect(host.selection.primary === music)
        #expect(host.selection.secondary === timer)
        #expect(host.selection.notice === notice)
        #expect(host.currentActivity === notice)
        host.stop()
    }

    @Test
    func explicitFallbackNeverAutoselectsARegisteredLiveActivity() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        host.present(music)
        host.setExpansion(.fallback)
        #expect(host.selection.primary === music)
        #expect(host.selection.expanded == nil)
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func replacementWithSameLogicalIDKeepsContextsInstanceScoped() {
        let host = LiveActivityHost()
        let old = LiveFixture("music")
        let replacement = LiveFixture("music")
        host.setVisible(true)
        host.present(old)
        host.setVisibleActivities([old])
        let oldContext = old.context
        host.present(replacement)
        host.setVisibleActivities([old, replacement])
        #expect(old.activations == 1)
        #expect(replacement.activations == 1)
        replacement.contentRevision = 1
        old.contentRevision = 99
        var changes = 0
        host.onChange = { changes += 1 }
        oldContext?.invalidate()
        #expect(changes == 0)
        host.setVisibleActivities([replacement])
        #expect(old.suspensions == 1)
        #expect(replacement.suspensions == 0)
        replacement.context?.invalidate()
        #expect(changes == 1)
        host.stop()
    }

    @Test
    func globalVisibilitySuspendsAndReactivatesTheDesiredInstanceOnce() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        host.present(music)
        host.setVisibleActivities([music])
        host.setVisible(true)
        #expect(music.activations == 1)
        host.setVisible(false)
        #expect(music.suspensions == 1)
        host.setVisible(true)
        #expect(music.activations == 2)
        host.setVisible(true)
        #expect(music.activations == 2)
        host.stop()
    }

    @Test
    func endedInstanceCannotBeReactivatedByAStalePresentationUnion() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        host.setVisible(true)
        host.present(music)
        host.setVisibleActivities([music])
        host.end(id: music.id)
        #expect(music.suspensions == 1)
        host.setVisibleActivities([music])
        #expect(music.activations == 1)
        #expect(host.selection.primary == nil)
        host.setVisibleActivities([])
        let replay = host.setVisibleActivities([music])
        #expect(replay.accepted.isEmpty)
        #expect(replay.rejected.first === music)
        #expect(music.activations == 1)
        host.stop()
    }

    @Test(arguments: ["end", "dismiss", "source", "expiry"])
    func terminalOperationsRevokeEveryRetainedSameIDInstance(reason: String) {
        var now = Date(timeIntervalSince1970: 100)
        let host = LiveActivityHost(now: { now })
        let old = LiveFixture("music")
        let replacement = LiveFixture("music")
        replacement.lifetime = NotchActivityLifetime(startedAt: now, duration: 5)
        host.setVisible(true)
        host.present(old)
        host.setVisibleActivities([old])
        host.present(replacement)
        host.setVisibleActivities([old, replacement])
        var validityChanges = 0
        host.onValidityChange = { validityChanges += 1 }

        switch reason {
        case "end":
            host.end(id: replacement.id)
        case "dismiss":
            host.dismiss(id: replacement.id)
        case "source":
            host.dismissActivities(from: replacement.sourceID)
        case "expiry":
            now = now.addingTimeInterval(6)
            host.expireNotices()
        default:
            Issue.record("Unknown terminal reason")
        }

        #expect(old.suspensions == 1)
        #expect(replacement.suspensions == 1)
        #expect(validityChanges == 1)
        #expect(!host.isPresentationValid(old))
        #expect(!host.isPresentationValid(replacement))
        let stale = host.setVisibleActivities([old, replacement])
        #expect(stale.accepted.isEmpty)
        #expect(stale.rejected.count == 2)
        #expect(old.activations == 1)
        #expect(replacement.activations == 1)
        host.stop()
    }

    @Test
    func lockRevokesRetainedNoticeReplacementsButKeepsLiveUnionDesired() {
        let host = LiveActivityHost()
        let live = LiveFixture("music")
        let oldNotice = NoticeFixture("device")
        let replacementNotice = NoticeFixture("device")
        replacementNotice.contentRevision = 1
        host.setVisible(true)
        host.present(live)
        host.showNotice(oldNotice)
        host.setVisibleActivities([live, oldNotice])
        host.updateNotice(replacementNotice)
        host.setVisibleActivities([live, oldNotice, replacementNotice])
        host.setVisible(false)
        #expect(oldNotice.suspensions == 1)
        #expect(replacementNotice.suspensions == 1)
        #expect(live.suspensions == 1)
        host.setVisible(true)
        #expect(live.activations == 2)
        #expect(oldNotice.activations == 1)
        #expect(replacementNotice.activations == 1)
        let stale = host.setVisibleActivities([live, oldNotice, replacementNotice])
        #expect(stale.accepted.count == 1)
        #expect(stale.accepted.first === live)
        #expect(stale.rejected.count == 2)
        host.stop()
    }

    @Test
    func outgoingValidityIsBoundedAndCannotReplayAfterAcknowledgement() {
        let host = LiveActivityHost()
        host.setVisible(true)
        for index in 0..<100 {
            let old = NoticeFixture("notice-\(index)")
            let replacement = NoticeFixture("notice-\(index)")
            replacement.contentRevision = 1
            host.showNotice(old)
            host.setVisibleActivities([old])
            host.updateNotice(replacement)
            host.setVisibleActivities([old, replacement])
            #expect(host.retainedOutgoingActivityCount == 1)
            host.setVisibleActivities([replacement])
            #expect(host.retainedOutgoingActivityCount == 0)
            let replay = host.setVisibleActivities([old])
            #expect(replay.accepted.isEmpty)
            #expect(replay.rejected.first === old)
            host.dismiss(id: replacement.id)
            host.setVisibleActivities([])
        }
        host.stop()
    }

    @Test
    func retainedTerminalChangeIsObservableWhenSelectionDoesNotMove() {
        let host = LiveActivityHost()
        host.setVisible(true)
        host.present(LiveFixture("primary", sourceID: "primary", relevance: 1))
        host.present(LiveFixture("secondary", sourceID: "secondary", relevance: 0.9))
        let old = LiveFixture("hidden", sourceID: "hidden", relevance: 0.1)
        let replacement = LiveFixture("hidden", sourceID: "hidden", relevance: 0.1)
        host.present(old)
        host.setVisibleActivities([old])
        host.present(replacement)
        host.setVisibleActivities([old, replacement])
        var selectionChanges = 0
        var validityChanges = 0
        host.onChange = { selectionChanges += 1 }
        host.onValidityChange = { validityChanges += 1 }
        host.end(id: replacement.id)
        #expect(selectionChanges == 0)
        #expect(validityChanges == 1)
        #expect(host.presentationValidityRevision == 1)
        #expect(!host.isPresentationValid(old))
        #expect(!host.isPresentationValid(replacement))
        host.stop()
    }

    @Test
    func expandedFallbackHasNoCompactSurfaceOrResourcesUntilOpened() {
        let host = LiveActivityHost()
        let music = LiveFixture("paused-music")
        host.setVisible(true)
        host.setExpandedFallback(music)
        #expect(host.currentActivity == nil)
        #expect(music.activations == 0)
        host.setExpanded(true)
        host.setVisibleActivities([music])
        #expect(host.currentActivity?.id == music.id)
        #expect(music.activations == 1)
        music.contentRevision += 1
        var changes = 0
        host.onChange = { changes += 1 }
        music.context?.invalidate()
        #expect(changes == 1)
        host.setExpanded(false)
        host.setVisibleActivities([])
        #expect(host.currentActivity == nil)
        #expect(music.suspensions == 1)
        host.stop()
    }

    @Test
    func clearingFallbackDoesNotRevokeTheSameObjectFromItsCompactLiveRole() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        host.setVisible(true)
        host.present(music)
        host.setExpandedFallback(music)
        host.setExpansion(.fallback)
        host.setVisibleActivities([music])
        let validityRevision = host.presentationValidityRevision

        host.setExpandedFallback(nil)

        #expect(host.selection.primary === music)
        #expect(host.selection.expanded == nil)
        #expect(host.isPresentationValid(music))
        #expect(host.presentationValidityRevision == validityRevision)
        #expect(music.suspensions == 0)
        host.stop()
    }

    @Test
    func clearingFallbackOnlyContentTearsItDownAfterTheNewUnionIsApplied() {
        let host = LiveActivityHost()
        let fallback = LiveFixture("paused-music")
        host.setVisible(true)
        host.setExpandedFallback(fallback)
        host.setExpansion(.fallback)
        host.setVisibleActivities([fallback])

        host.setExpandedFallback(nil)

        #expect(fallback.suspensions == 0)
        host.setVisibleActivities([])
        #expect(fallback.suspensions == 1)
        #expect(fallback.activations == 1)
        host.stop()
    }

    @Test
    func endingPlaybackKeepsTheOpenFallbackAndResumeRestoresCompact() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        host.setVisible(true)
        host.present(music)
        host.setVisibleActivities([music])
        host.setExpandedFallback(music)
        host.setExpanded(true)
        host.end(id: music.id)
        #expect(host.currentActivity?.id == music.id)
        #expect(music.activations == 1)
        #expect(music.suspensions == 0)
        host.setExpanded(false)
        #expect(host.currentActivity == nil)
        host.present(music)
        #expect(host.currentActivity?.id == music.id)
        host.dismissActivities(from: music.sourceID)
        host.setExpanded(true)
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func fallbackDoesNotCompeteWithOtherActivitiesOrExpireAsALiveSession() {
        var now = Date(timeIntervalSince1970: 100)
        let host = LiveActivityHost(now: { now })
        let music = LiveFixture("paused-music")
        music.lifetime = NotchActivityLifetime(startedAt: now, duration: 1)
        host.setExpandedFallback(music)
        let timer = LiveFixture("timer", sourceID: "timer")
        host.present(timer)
        host.setExpanded(true)
        #expect(host.currentActivity?.id == timer.id)
        host.setExpanded(false)
        host.end(id: timer.id)
        now = now.addingTimeInterval(2)
        host.expireNotices()
        host.setExpanded(true)
        #expect(host.currentActivity?.id == music.id)
        host.setExpandedFallback(nil)
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func noticeUsesBothCompactSidesAndRestoresTheOngoingActivity() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        let notice = NoticeFixture("device")
        host.setVisible(true)
        host.present(music)
        host.setVisibleActivities([music])
        host.showNotice(notice)
        host.setVisibleActivities([notice])
        #expect(host.currentActivity?.id == "device")
        #expect(host.secondaryActivity == nil)
        #expect(music.suspensions == 1)
        host.dismiss(id: "device")
        host.setVisibleActivities([music])
        #expect(host.currentActivity?.id == "music")
        #expect(host.secondaryActivity == nil)
        #expect(music.activations == 2)
        host.stop()
    }

    @Test
    func twoSourcesUseRelevanceAndCanExpandTheSecondaryActivity() {
        let host = LiveActivityHost()
        let music = LiveFixture("music", relevance: 0.9)
        let timer = LiveFixture("timer", sourceID: "timer", relevance: 0.4)
        host.present(music)
        host.present(timer)
        #expect(host.currentActivity?.id == "music")
        #expect(host.secondaryActivity?.id == "timer")
        host.setExpanded(true, activityID: "timer")
        host.showNotice(NoticeFixture("device"))
        #expect(host.currentActivity?.id == "timer")
        #expect(host.secondaryActivity == nil)
        host.setExpanded(false)
        #expect(host.currentActivity?.id == "music")
        host.stop()
    }

    @Test
    func openingANoticeDiscardsItAndExpandsOnlyAnOngoingTask() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        host.present(music)
        host.showNotice(NoticeFixture("device"))
        host.setExpanded(true, activityID: "device")
        #expect(host.currentActivity?.id == "music")
        #expect(host.pendingNoticeCount == 0)
        host.showNotice(NoticeFixture("volume"))
        #expect(host.pendingNoticeCount == 0)
        #expect(host.currentActivity?.id == "music")
        host.setExpanded(false)
        #expect(host.currentActivity?.id == "music")
        host.stop()
    }

    @Test
    func openingANoticeWithoutALiveTaskShowsTheWidgetSurface() {
        let host = LiveActivityHost()
        host.showNotice(NoticeFixture("device"))
        host.setExpanded(true)
        #expect(host.currentActivity == nil)
        #expect(host.pendingNoticeCount == 0)
        host.setExpanded(false)
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func latestNoticeTakesPriorityOverOlderStatusEvents() {
        let host = LiveActivityHost()
        host.showNotice(NoticeFixture("device"))
        host.showNotice(NoticeFixture("volume"))
        #expect(host.currentActivity?.id == "volume")
        host.stop()
    }

    @Test
    func sourceAggregationDoesNotFillBothMinimalSlotsWithTheSameIntegration() {
        let host = LiveActivityHost()
        host.present(LiveFixture("first", sourceID: "sports"))
        host.present(LiveFixture("second", sourceID: "sports"))
        host.present(LiveFixture("timer", sourceID: "timer", relevance: 0.1))
        #expect(host.currentActivity?.id == "second")
        #expect(host.secondaryActivity?.id == "timer")
        host.stop()
    }

    @Test
    func endedOrExpiredLiveContentDisappearsEvenDuringManualExpansion() {
        var now = Date(timeIntervalSince1970: 100)
        let host = LiveActivityHost(now: { now })
        let music = LiveFixture("music")
        music.lifetime = NotchActivityLifetime(startedAt: now, duration: 4)
        host.setVisible(true)
        host.present(music)
        host.setVisibleActivities([music])
        host.setExpanded(true)
        now = now.addingTimeInterval(5)
        host.expireNotices()
        #expect(host.currentActivity == nil)
        #expect(music.suspensions == 1)
        host.setExpanded(false)
        #expect(host.currentActivity == nil)
        let timer = LiveFixture("timer")
        host.present(timer)
        host.setExpanded(true)
        host.end(id: timer.id)
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func lifetimeUpdatesCannotMoveTheOriginalSessionDeadline() {
        let start = Date(timeIntervalSince1970: 100)
        var now = start
        let host = LiveActivityHost(now: { now })
        let activity = LiveFixture("music")
        activity.lifetime = NotchActivityLifetime(startedAt: start)
        host.setVisible(true)
        host.present(activity)
        host.setVisibleActivities([activity])
        now = start.addingTimeInterval(7 * 60 * 60)
        activity.lifetime = NotchActivityLifetime(startedAt: now)
        host.present(activity)
        now = start.addingTimeInterval(7.5 * 60 * 60)
        activity.lifetime = NotchActivityLifetime(startedAt: now)
        activity.context?.invalidate()
        host.setExpanded(true)
        now = start.addingTimeInterval(NotchActivityLifetime.maximumDuration)
        host.expireNotices()
        #expect(host.currentActivity == nil)
        #expect(activity.suspensions == 1)
        host.stop()
    }

    @Test
    func futureStartDatesCannotExceedEightHoursOfResidence() {
        var now = Date(timeIntervalSince1970: 100)
        let host = LiveActivityHost(now: { now })
        let activity = LiveFixture("future")
        activity.lifetime = NotchActivityLifetime(startedAt: now.addingTimeInterval(86_400))
        host.present(activity)
        now = now.addingTimeInterval(NotchActivityLifetime.maximumDuration)
        host.expireNotices()
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func estimatedEndCanExtendWithinTheOriginalSessionMaximum() {
        var now = Date(timeIntervalSince1970: 100)
        let start = now
        let host = LiveActivityHost(now: { now })
        let activity = LiveFixture("delivery")
        activity.lifetime = NotchActivityLifetime(startedAt: start, duration: 60)
        host.present(activity)
        now = now.addingTimeInterval(30)
        activity.lifetime = NotchActivityLifetime(startedAt: start, duration: 120)
        host.present(activity)
        now = start.addingTimeInterval(90)
        host.expireNotices()
        #expect(host.currentActivity?.id == activity.id)
        now = start.addingTimeInterval(120)
        host.expireNotices()
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func freshnessChangesWithoutPollingAndCanBeRenewedWhileKeepingIdentity() {
        var now = Date(timeIntervalSince1970: 100)
        let host = LiveActivityHost(now: { now })
        let activity = LiveFixture("delivery")
        activity.lifetime = NotchActivityLifetime(startedAt: now, duration: 600, staleDate: now.addingTimeInterval(10))
        host.present(activity)
        #expect(!host.isStale(activity))
        var changes = 0
        host.onChange = { changes += 1 }
        now = now.addingTimeInterval(11)
        host.expireNotices()
        #expect(host.isStale(activity))
        #expect(changes == 1)
        host.expireNotices()
        #expect(changes == 1)
        activity.lifetime = NotchActivityLifetime(startedAt: Date(timeIntervalSince1970: 100), duration: 600, staleDate: now.addingTimeInterval(50))
        host.present(activity)
        #expect(!host.isStale(activity))
        #expect(changes == 2)
        host.stop()
    }

    @Test
    func sameRevisionDoesNotRedrawOrProlongANotice() {
        var now = Date(timeIntervalSince1970: 100)
        let host = LiveActivityHost(now: { now })
        let notice = NoticeFixture("device")
        host.showNotice(notice)
        var changes = 0
        host.onChange = { changes += 1 }
        now = now.addingTimeInterval(3)
        host.showNotice(notice)
        #expect(changes == 0)
        now = now.addingTimeInterval(2)
        host.expireNotices()
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func metadataUpdateKeepsTheOriginalNoticeDeadline() {
        let start = Date(timeIntervalSince1970: 100)
        var now = start
        let host = LiveActivityHost(now: { now })
        let original = NoticeFixture("device")
        host.setVisible(true)
        host.showNotice(original)
        host.setVisibleActivities([original])
        now = start.addingTimeInterval(3)
        let enriched = NoticeFixture("device")
        enriched.contentRevision = 1
        enriched.displayDuration = 10
        host.updateNotice(enriched)
        host.setVisibleActivities([enriched])
        #expect(host.currentActivity === enriched)
        #expect(original.suspensions == 1)
        #expect(enriched.activations == 1)
        now = start.addingTimeInterval(4)
        host.expireNotices()
        #expect(host.currentActivity == nil)
        #expect(enriched.suspensions == 1)
        host.stop()
    }

    @Test
    func metadataUpdateKeepsANewerNoticeInFront() {
        let host = LiveActivityHost()
        host.showNotice(NoticeFixture("device"))
        let volume = NoticeFixture("volume", sourceID: "volume")
        host.showNotice(volume)
        let enriched = NoticeFixture("device")
        enriched.contentRevision = 1
        host.updateNotice(enriched)
        #expect(host.currentActivity === volume)
        #expect(host.pendingNoticeCount == 2)
        host.dismiss(id: "volume")
        #expect(host.currentActivity === enriched)
        host.stop()
    }

    @Test(arguments: ["never shown", "hover", "expired", "dismissed", "source disabled", "hidden"])
    func metadataUpdateCannotResurrectAnAbsentNotice(reason: String) {
        var now = Date(timeIntervalSince1970: 100)
        let host = LiveActivityHost(now: { now })
        host.setVisible(true)
        if reason != "never shown" { host.showNotice(NoticeFixture("device")) }
        switch reason {
        case "hover": host.setExpanded(true)
        case "expired": now = now.addingTimeInterval(4)
        case "dismissed": host.dismiss(id: "device")
        case "source disabled": host.dismissActivities(from: "bluetooth")
        case "hidden": host.setVisible(false)
        default: break
        }
        let enriched = NoticeFixture("device")
        enriched.contentRevision = 1
        host.updateNotice(enriched)
        host.setExpanded(false)
        host.setVisible(true)
        #expect(host.pendingNoticeCount == 0)
        #expect(host.currentActivity == nil)
        #expect(enriched.activations == 0)
        host.stop()
    }

    @Test
    func metadataUpdateRejectsOtherSourcesAndNonIncreasingRevisions() {
        let host = LiveActivityHost()
        let original = NoticeFixture("device")
        original.contentRevision = 2
        host.showNotice(original)
        var changes = 0
        host.onChange = { changes += 1 }
        for revision: UInt64 in [1, 2] {
            let outdated = NoticeFixture("device")
            outdated.contentRevision = revision
            host.updateNotice(outdated)
        }
        let otherSource = NoticeFixture("device", sourceID: "unrelated")
        otherSource.contentRevision = 3
        host.updateNotice(otherSource)
        #expect(host.currentActivity === original)
        #expect(changes == 0)
        original.contentRevision = 3
        host.updateNotice(original)
        #expect(changes == 1)
        host.stop()
    }

    @Test
    func onlyChangedRevisionsInvalidateVisibleContent() {
        let host = LiveActivityHost()
        let activity = LiveFixture("music")
        host.setVisible(true)
        host.present(activity)
        host.setVisibleActivities([activity])
        var changes = 0
        host.onChange = { changes += 1 }
        host.present(activity)
        activity.context?.invalidate()
        #expect(changes == 0)
        activity.contentRevision += 1
        activity.context?.invalidate()
        host.present(activity)
        #expect(changes == 1)
        host.stop()
    }

    @Test
    func compactInvalidationsRemainValidWhileAnotherActivityIsExpanded() {
        let host = LiveActivityHost()
        let music = LiveFixture("music")
        let timer = LiveFixture("timer", sourceID: "timer", relevance: 0.1)
        host.setVisible(true)
        host.present(music)
        host.present(timer)
        host.setVisibleActivities([music, timer])
        #expect(timer.activations == 1)
        let oldContext = timer.context
        host.setExpanded(true)
        host.setVisibleActivities([music, timer])
        #expect(timer.suspensions == 0)
        var changes = 0
        host.onChange = { changes += 1 }
        timer.contentRevision += 1
        oldContext?.invalidate()
        #expect(changes == 1)
        host.stop()
    }

    @Test
    func noticesDoNotReplaceAnOpenWidgetPage() {
        let host = LiveActivityHost()
        host.setExpanded(true)
        host.showNotice(NoticeFixture("device"))
        #expect(host.currentActivity == nil)
        host.setExpanded(false)
        #expect(host.currentActivity == nil)
        host.stop()
    }

    @Test
    func disablingASourceRemovesItsExpandedAndQueuedContent() {
        let host = LiveActivityHost()
        host.present(LiveFixture("music"))
        host.showNotice(NoticeFixture("device-a"))
        host.setExpanded(true)
        host.showNotice(NoticeFixture("device-b"))
        host.dismissActivities(from: "bluetooth")
        #expect(host.currentActivity?.id == "music")
        #expect(host.pendingNoticeCount == 0)
        host.setExpanded(false)
        #expect(host.currentActivity?.id == "music")
        host.stop()
    }

    @Test
    func limitsNoticeBacklogAndClearsItWhenHidden() {
        let host = LiveActivityHost()
        host.setVisible(true)
        for index in 0..<30 { host.showNotice(NoticeFixture("device-\(index)")) }
        #expect(host.pendingNoticeCount <= 8)
        host.setVisible(false)
        #expect(host.pendingNoticeCount == 0)
        #expect(host.currentActivity == nil)
        host.stop()
    }
}

@MainActor
private class ContentFixture: NotchActivity {
    let id: String
    let sourceID: String
    var contentRevision: UInt64 = 0
    var accessibilityLabel: String { id }
    var privacy: NotchActivityPrivacy { .standard }
    var activations = 0
    var suspensions = 0
    var context: LiveActivityContext?

    init(_ id: String, sourceID: String) {
        self.id = id
        self.sourceID = sourceID
    }
    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView { AnyView(Text(id)) }
    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView { AnyView(Text(id)) }
    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView { AnyView(Text(id)) }
    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView { AnyView(Text(id)) }
    func activate(in context: LiveActivityContext) {
        self.context = context
        activations += 1
    }
    func suspend() { suspensions += 1 }
}

@MainActor
private final class LiveFixture: ContentFixture, NotchLiveActivity {
    var lifetime = NotchActivityLifetime()
    let relevanceScore: Double
    init(_ id: String, sourceID: String = "media", relevance: Double = 0.5) {
        relevanceScore = relevance
        super.init(id, sourceID: sourceID)
    }
}

@MainActor
private final class ReentrantLiveFixture: ContentFixture, NotchLiveActivity {
    var lifetime = NotchActivityLifetime()
    let relevanceScore: Double = 0.5
    var onActivate: (() -> Void)?

    override func activate(in context: LiveActivityContext) {
        super.activate(in: context)
        onActivate?()
    }
}

@MainActor
private final class NoticeFixture: ContentFixture, NotchTransientNotice {
    var displayDuration: TimeInterval = 4
    override init(_ id: String, sourceID: String = "bluetooth") { super.init(id, sourceID: sourceID) }
}
