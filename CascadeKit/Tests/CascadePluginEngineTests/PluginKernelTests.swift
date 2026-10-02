//
//  PluginKernelTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginKernelTests {

    private typealias Fixtures = PluginEngineFixtures

    private let clock    = PluginEngineFixtures.clockID
    private let music    = PluginEngineFixtures.musicID
    private let start    = PluginEngineFixtures.start
    private let activity = PluginPublicationKey(plugin: PluginEngineFixtures.musicID, feature: "now-playing", surface: .activity)

    /// playing registers the music plugin and answers its first refresh with `document` on the
    /// activity, leaving the kernel idle at `start` with revision 1 on screen.
    private func playing(
        _ document: PluginDocument,
        in kernel : inout PluginKernel,
        staleAfter: Double? = nil
    ) throws {
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)
        _ = kernel.complete(
            music,
            token : 1,
            result: Fixtures.result(try Fixtures.output("now-playing", .activity, document, staleAfter: staleAfter)),
            at    : start
        )
    }

    @Test
    func registrationStartsThePluginAndAsksForARefresh() throws {
        var kernel = Fixtures.kernel()

        let effects = kernel.register(try Fixtures.clock(), grants: [], at: start)

        #expect(effects == [.start(clock, entryPoint: "ClockPlugin"), .dispatch(clock, .refresh, token: 1)])
        #expect(kernel.nextDelay(at: start) == .milliseconds(250))
    }

    @Test
    func aChangedPublicationIsDeliveredAndAnEqualOneIsNot() throws {
        let song   = try Fixtures.text("Song")
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)

        let first = kernel.complete(music, token: 1, result: Fixtures.result(try Fixtures.output("now-playing", .activity, song)), at: start)
        guard case .deliver(let changes) = first.first else {
            Issue.record("The first publication was not delivered")
            return
        }
        #expect(changes.map(\.revision) == [1])
        #expect(changes.first?.content?.diff.inserted == [PluginNodeID(rawValue: "root:text")])

        _ = kernel.receive(try Fixtures.nowPlaying("Song"), at: start)
        let second = kernel.complete(music, token: 2, result: Fixtures.result(try Fixtures.output("now-playing", .activity, song)), at: start)

        #expect(second.isEmpty)
    }

    @Test
    func aSharedSourceStartsWithTheFirstHolderAndStopsWithTheLast() throws {
        var kernel = Fixtures.kernel()

        let first  = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)
        let second = kernel.register(try Fixtures.music(Fixtures.radioID), grants: ["automation.music"], at: start)

        #expect(first.contains(.startSource("media.nowPlaying")))
        #expect(!second.contains(.startSource("media.nowPlaying")))
        #expect(!kernel.revoke("automation.music", from: music, at: start).contains(.stopSource("media.nowPlaying")))
        #expect(kernel.revoke("automation.music", from: Fixtures.radioID, at: start).contains(.stopSource("media.nowPlaying")))
    }

    @Test
    func sourceEventsCoalesceToTheLatestWhileThePluginIsBusy() throws {
        let three  = try Fixtures.nowPlaying("Three")
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)

        for title in ["One", "Two"] {
            #expect(kernel.receive(try Fixtures.nowPlaying(title), at: start).isEmpty)
        }
        #expect(kernel.receive(three, at: start).isEmpty)

        let effects = kernel.complete(music, token: 1, result: Fixtures.result(try PluginOutput()), at: start)

        #expect(effects == [.dispatch(music, .source(three), token: 2)])
    }

    @Test
    func aThrowPausesThePluginForASecondThenRefreshesIt() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.clock(), grants: [], at: start)

        #expect(kernel.complete(clock, token: 1, result: Fixtures.result(nil), at: start).isEmpty)
        #expect(kernel.nextDelay(at: start) == .seconds(1))
        #expect(kernel.tick(at: start.advanced(by: 0.5)).isEmpty)
        #expect(kernel.tick(at: start.advanced(by: 1)) == [.dispatch(clock, .refresh, token: 2)])
        #expect(kernel.state(of: clock) == .active)
    }

    @Test
    func aRetryPrimesThePluginWithTheLatestSourceState() throws {
        let song   = try Fixtures.nowPlaying("Song")
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)
        _ = kernel.receive(song, at: start)
        _ = kernel.complete(music, token: 1, result: Fixtures.result(nil), at: start)

        let later = start.advanced(by: 1)

        #expect(kernel.tick(at: later) == [.dispatch(music, .source(song), token: 2)])
        #expect(kernel.complete(music, token: 2, result: Fixtures.result(try PluginOutput()), at: later) == [.dispatch(music, .refresh, token: 3)])
    }

    @Test
    func aQuarantineWithdrawsEveryPublicationOfThePlugin() throws {
        var kernel = Fixtures.kernel(policy: FixedHealthPolicy(answer: .quarantine))
        try playing(Fixtures.text("Song"), in: &kernel)
        _ = kernel.receive(try Fixtures.nowPlaying("Two"), at: start)

        let effects = kernel.complete(music, token: 2, result: Fixtures.result(nil), at: start)

        guard case .deliver(let changes) = effects.first else {
            Issue.record("Nothing was withdrawn")
            return
        }
        #expect(changes.map(\.content) == [nil])
        #expect(effects.contains(.stopSource("media.nowPlaying")))
        #expect(kernel.state(of: music) == .quarantined)
    }

    @Test
    func aHangStopsThePluginWithdrawsItsContentAndIgnoresItsLateAnswer() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.text("Song"), in: &kernel)
        _ = kernel.receive(try Fixtures.nowPlaying("Two"), at: start)

        #expect(kernel.tick(at: start.advanced(by: 0.2)).isEmpty)

        let effects = kernel.tick(at: start.advanced(by: 0.25))

        #expect(effects.first == .stop(music))
        #expect(effects.contains(.stopSource("media.nowPlaying")))
        #expect(effects.contains { effect in
            guard case .deliver(let changes) = effect else { return false }

            return changes.allSatisfy { $0.content == nil }
        })
        #expect(kernel.state(of: music) == .disabledAfterHang)

        let late = start.advanced(by: 1)

        #expect(kernel.complete(music, token: 2, result: Fixtures.result(try Fixtures.output("now-playing", .activity, Fixtures.text("Late"))), at: late).isEmpty)
        #expect(kernel.nextDelay(at: late) == nil)
    }

    @Test
    func aReenabledPluginStartsAgainAndASecondHangQuarantinesIt() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.clock(), grants: [], at: start)
        _ = kernel.tick(at: start.advanced(by: 0.25))

        #expect(kernel.reenable(clock, at: start.advanced(by: 1)) == [.start(clock, entryPoint: "ClockPlugin"), .dispatch(clock, .refresh, token: 2)])

        _ = kernel.tick(at: start.advanced(by: 1.25))

        #expect(kernel.state(of: clock) == .quarantined)
    }

    @Test
    func cpuDebtHoldsTheNextEventUntilItIsRepaid() throws {
        let two    = try Fixtures.nowPlaying("Two")
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)
        _ = kernel.complete(music, token: 1, result: Fixtures.result(try PluginOutput(), cpuTime: .milliseconds(150)), at: start)

        #expect(kernel.receive(two, at: start).isEmpty)
        #expect(kernel.nextDelay(at: start) == .seconds(10))
        #expect(kernel.tick(at: start.advanced(by: 10)) == [.dispatch(music, .source(two), token: 2)])
    }

    @Test
    func aBurstOfEightPublicationsHoldsTheNextEvent() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)

        for token in UInt64(1)...8 {
            _ = kernel.complete(
                music,
                token : token,
                result: Fixtures.result(try Fixtures.output("now-playing", .activity, Fixtures.text("\(token)"))),
                at    : start
            )
            _ = kernel.receive(try Fixtures.nowPlaying("\(token)"), at: start)
        }

        let eight = try Fixtures.nowPlaying("8")

        #expect(kernel.nextDelay(at: start) == .milliseconds(250))
        #expect(kernel.tick(at: start.advanced(by: 0.25)) == [.dispatch(music, .source(eight), token: 9)])
    }

    @Test
    func aRevokedPermissionWithdrawsTheFeatureAndRefusesItsActions() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.controls(), in: &kernel)

        let effects = kernel.revoke("automation.music", from: music, at: start)

        guard case .deliver(let changes) = effects.first else {
            Issue.record("Nothing was withdrawn")
            return
        }
        #expect(changes.map(\.content) == [nil])
        #expect(effects.last == .stopSource("media.nowPlaying"))

        let request = PluginActionRequest(key: activity, node: PluginNodeID(rawValue: "#next:button"), revision: 1)

        #expect(kernel.submit(request, at: start) == [.reject(request)])
    }

    @Test
    func anActionIsDispatchedAheadOfPendingSources() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.controls(), in: &kernel)
        _ = kernel.receive(try Fixtures.nowPlaying("Two"), at: start)
        _ = kernel.receive(try Fixtures.nowPlaying("Three"), at: start)

        let request = PluginActionRequest(key: activity, node: PluginNodeID(rawValue: "#play:toggle"), revision: 1, value: .bool(false))
        let toggled = try PluginActionEvent(feature: "now-playing", action: "togglePlayback", value: .bool(false))

        #expect(kernel.submit(request, at: start).isEmpty)
        #expect(kernel.complete(music, token: 2, result: Fixtures.result(try PluginOutput()), at: start) == [.dispatch(music, .action(toggled), token: 3)])
    }

    @Test
    func aStaleSurfaceAsksForOneRefreshWhenItBecomesVisible() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.text("Song"), in: &kernel, staleAfter: 60)

        #expect(kernel.setVisible(true, for: activity, at: start.advanced(by: 30)).isEmpty)
        #expect(kernel.setVisible(false, for: activity, at: start.advanced(by: 40)).isEmpty)
        #expect(kernel.setVisible(true, for: activity, at: start.advanced(by: 61)) == [.dispatch(music, .refresh, token: 2)])
        #expect(kernel.setVisible(true, for: activity, at: start.advanced(by: 62)).isEmpty)
    }

    @Test
    func aWakeComesAtTheTimeAskedForButNeverWithinASecond() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.clock(), grants: [], at: start)
        _ = kernel.complete(clock, token: 1, result: Fixtures.result(try PluginOutput(wake: start.wall.addingTimeInterval(0.2))), at: start)

        #expect(kernel.nextDelay(at: start) == .seconds(1))
        #expect(kernel.tick(at: start.advanced(by: 1)) == [.dispatch(clock, .wake, token: 2)])
    }

    @Test
    func aWakeFarInTheFutureSleepsAtMostADay() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.clock(), grants: [], at: start)
        _ = kernel.complete(clock, token: 1, result: Fixtures.result(try PluginOutput(wake: start.wall.addingTimeInterval(1e9))), at: start)

        #expect(kernel.nextDelay(at: start) == .seconds(86_400))
    }

    @Test
    func aFeatureNeedingAMissingSourceIsUnavailableWithoutBlame() throws {
        var kernel     = Fixtures.kernel(sources: [], policy: FixedHealthPolicy(answer: .quarantine))
        let registered = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)

        #expect(!registered.contains(.startSource("media.nowPlaying")))
        #expect(kernel.complete(music, token: 1, result: Fixtures.result(try Fixtures.output("now-playing", .activity, Fixtures.text("Song"))), at: start).isEmpty)
        #expect(kernel.state(of: music) == .active)
    }

    @Test
    func anUndeclaredSurfaceIsRefusedWhileTheValidPublicationStands() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.clock(), grants: [], at: start)
        let output = try PluginOutput(
            publications: [
                PluginPublication(feature: "time", surface: .activity, document: Fixtures.text("Wrong")),
                PluginPublication(feature: "time", surface: .widget, document: Fixtures.text("12:00")),
            ]
        )

        let effects = kernel.complete(clock, token: 1, result: Fixtures.result(output), at: start)

        guard case .deliver(let changes) = effects.first else {
            Issue.record("The valid publication was not delivered")
            return
        }
        #expect(changes.map(\.key.surface) == [.widget])
    }

    @Test
    func anUndeclaredComponentCountsAsAnIncident() throws {
        let spectrum = try PluginDocument(root: PluginNode(.component(id: "audio.spectrum", version: 1, parameters: [:])))
        var kernel   = Fixtures.kernel(policy: FixedHealthPolicy(answer: .quarantine))

        try playing(spectrum, in: &kernel)

        #expect(kernel.state(of: music) == .quarantined)
    }

    @Test
    func nothingIsDueOnceEveryPluginHasAnswered() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.text("Song"), in: &kernel)

        #expect(kernel.nextDelay(at: start) == nil)
    }

    @Test
    func aRevocationRefusesTheActionsAlreadyQueued() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.controls(), in: &kernel)
        _ = kernel.receive(try Fixtures.nowPlaying("Two"), at: start)

        let request = PluginActionRequest(key: activity, node: PluginNodeID(rawValue: "#next:button"), revision: 1)
        _ = kernel.submit(request, at: start)
        _ = kernel.revoke("automation.music", from: music, at: start)

        #expect(kernel.complete(music, token: 2, result: Fixtures.result(try PluginOutput()), at: start) == [.reject(request)])
    }

    @Test
    func aSourceEventQueuedBeforeRevocationIsDropped() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.text("Song"), in: &kernel)
        _ = kernel.receive(try Fixtures.nowPlaying("Two"), at: start)
        _ = kernel.receive(try Fixtures.nowPlaying("Three"), at: start)
        _ = kernel.revoke("automation.music", from: music, at: start)

        #expect(kernel.complete(music, token: 2, result: Fixtures.result(try PluginOutput()), at: start).isEmpty)
    }

    @Test
    func anActionThatWaitedPastTheTimeoutIsRefusedNotRun() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.controls(), in: &kernel)
        _ = kernel.receive(try Fixtures.nowPlaying("Two"), at: start)

        let request = PluginActionRequest(key: activity, node: PluginNodeID(rawValue: "#play:toggle"), revision: 1, value: .bool(false))
        _ = kernel.submit(request, at: start)
        _ = kernel.complete(music, token: 2, result: Fixtures.result(try PluginOutput(), cpuTime: .milliseconds(150)), at: start)

        #expect(kernel.tick(at: start.advanced(by: 11)) == [.reject(request)])
    }

    @Test
    func contentAgesWhileTheMacSleeps() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.text("Song"), in: &kernel, staleAfter: 60)
        let awake = PluginInstant(
            wall     : start.wall.addingTimeInterval(120),
            monotonic: start.monotonic + .seconds(1)
        )

        #expect(kernel.setVisible(true, for: activity, at: awake) == [.dispatch(music, .refresh, token: 2)])
    }

    @Test
    func anUnchangedSourceStateWakesNoPlugin() throws {
        let song   = try Fixtures.nowPlaying("Song")
        var kernel = Fixtures.kernel()
        try playing(Fixtures.text("Song"), in: &kernel)
        _ = kernel.receive(song, at: start)
        _ = kernel.complete(music, token: 2, result: Fixtures.result(try PluginOutput()), at: start)

        #expect(kernel.receive(song, at: start).isEmpty)
    }

    @Test
    func aRefreshAnsweredWithNothingNewIsNotAskedAgainOnTheNextOpening() throws {
        var kernel = Fixtures.kernel()
        try playing(Fixtures.text("Song"), in: &kernel, staleAfter: 60)
        _ = kernel.setVisible(true, for: activity, at: start.advanced(by: 61))
        _ = kernel.complete(music, token: 2, result: Fixtures.result(try PluginOutput()), at: start.advanced(by: 61))
        _ = kernel.setVisible(false, for: activity, at: start.advanced(by: 62))

        #expect(kernel.setVisible(true, for: activity, at: start.advanced(by: 63)).isEmpty)
    }

    @Test
    func aSurfaceWithNoContentAsksForNothing() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)
        _ = kernel.complete(music, token: 1, result: Fixtures.result(try PluginOutput()), at: start)

        #expect(kernel.setVisible(true, for: activity, at: start.advanced(by: 1)).isEmpty)
    }

    @Test
    func theWakeIsReportedApartFromTheDeadlines() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.clock(), grants: [], at: start)
        let output = try PluginOutput(
            publications: [PluginPublication(feature: "time", surface: .widget, document: Fixtures.text("12:00"), staleAfter: 1)],
            wake        : start.wall.addingTimeInterval(5)
        )
        _ = kernel.complete(clock, token: 1, result: Fixtures.result(output), at: start)

        #expect(kernel.wakeDelay(at: start) == .seconds(5))

        let later = start.advanced(by: 2)
        _ = kernel.setVisible(true, for: PluginPublicationKey(plugin: clock, feature: "time", surface: .widget), at: later)

        #expect(kernel.nextDelay(at: later) == .milliseconds(250))
        #expect(kernel.wakeDelay(at: later) == .seconds(3))
    }

    @Test
    func nothingIsDispatchedLeasedOrDueWhileTheHostIsUnavailable() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.hostUnavailable()

        let effects = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)

        #expect(effects == [.start(music, entryPoint: "MusicPlugin")])
        #expect(kernel.nextDelay(at: start) == nil)
    }

    @Test
    func aLostHostReleasesEverySourceAndAReturningOneLeasesThemAgain() throws {
        let song   = try Fixtures.nowPlaying("Song")
        var kernel = Fixtures.kernel()
        try playing(Fixtures.text("Song"), in: &kernel)
        _ = kernel.receive(song, at: start)
        _ = kernel.complete(music, token: 2, result: Fixtures.result(try PluginOutput()), at: start)

        #expect(kernel.hostUnavailable() == [.stopSource("media.nowPlaying")])
        #expect(kernel.receive(song, at: start).isEmpty)
        #expect(kernel.hostAvailable(at: start) == [.startSource("media.nowPlaying"), .dispatch(music, .refresh, token: 3)])
    }

    @Test
    func aLostDispatchPrimesThePluginWithoutBlame() throws {
        var kernel = Fixtures.kernel(policy: FixedHealthPolicy(answer: .quarantine))
        _ = kernel.register(try Fixtures.clock(), grants: [], at: start)

        #expect(kernel.complete(clock, token: 1, result: .lost, at: start) == [.dispatch(clock, .refresh, token: 2)])
        #expect(kernel.state(of: clock) == .active)
    }

    @Test
    func aSwitchedOffPluginShowsNothingAndHoldsNoSource() throws {
        var kernel = Fixtures.kernel()
        try playing(try Fixtures.text("Song"), in: &kernel)

        let off = kernel.setEnabled(false, for: music, at: start)

        #expect(off.contains(.stopSource("media.nowPlaying")))
        #expect(off.contains { effect in
            guard case .deliver(let changes) = effect else { return false }

            return changes.map(\.key) == [activity] && changes.allSatisfy { $0.content == nil }
        })
        #expect(kernel.receive(try Fixtures.nowPlaying("Next"), at: start).isEmpty)
        #expect(kernel.invoke("next", value: nil, feature: "now-playing", of: music, at: start).isEmpty)
    }

    @Test
    func aSwitchedOnPluginLeasesItsSourcesAndIsAskedForItsContent() throws {
        var kernel = Fixtures.kernel()
        try playing(try Fixtures.text("Song"), in: &kernel)
        _ = kernel.setEnabled(false, for: music, at: start)

        let on = kernel.setEnabled(true, for: music, at: start)

        #expect(on.contains(.startSource("media.nowPlaying")))
        #expect(on.contains(.dispatch(music, .refresh, token: 2)))
        #expect(kernel.setEnabled(true, for: music, at: start).isEmpty)
    }

    @Test
    func anAnswerArrivingAfterTheSwitchIsDropped() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)
        _ = kernel.setEnabled(false, for: music, at: start)

        let late = kernel.complete(
            music,
            token : 1,
            result: Fixtures.result(try Fixtures.output("now-playing", .activity, Fixtures.text("Song"))),
            at    : start
        )

        #expect(!late.contains { if case .deliver = $0 { true } else { false } })
    }

    @Test
    func aHostActionReachesThePluginOnlyWhenItsFeatureDeclaresIt() throws {
        var kernel = Fixtures.kernel()
        try playing(try Fixtures.text("Song"), in: &kernel)
        let next = try PluginActionEvent(feature: "now-playing", action: "next")

        #expect(kernel.invoke("eject", value: nil, feature: "now-playing", of: music, at: start).isEmpty)
        #expect(kernel.invoke("next", value: nil, feature: "elsewhere", of: music, at: start).isEmpty)
        #expect(kernel.invoke("next", value: nil, feature: "now-playing", of: music, at: start) == [.dispatch(music, .action(next), token: 2)])
    }

    @Test
    func aSwitchedOffPluginIsNotRetried() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.music(), grants: ["automation.music"], at: start)
        _ = kernel.complete(music, token: 1, result: PluginExecutionResult(outcome: .failed, cpuTime: .zero), at: start)
        _ = kernel.setEnabled(false, for: music, at: start)

        let later = kernel.tick(at: start.advanced(by: 60))

        #expect(!later.contains { if case .dispatch = $0 { true } else { false } })
    }

    /// noticer is a plugin that shows a notice for every volume state, as the volume plugin does.
    private func noticer() throws -> PluginManifest {
        try Fixtures.manifest(
            PluginID(rawValue: "com.cascade.volume")!,
            entryPoint: "VolumePlugin",
            features  : [PluginFeature(id: "volume", surfaces: PluginSurfaces(notice: PluginPlainSurface()), sources: ["volume"])]
        )
    }

    private func notice(_ text: String) throws -> PluginOutput {
        let document = try PluginDocument(root: PluginNode(.regions, children: [PluginNode(.text(text)), PluginNode(.text(text)), PluginNode(.text(text))]))

        return try PluginOutput(
            publications: [PluginPublication(feature: "volume", surface: .notice, document: document, notice: PluginNoticeAttributes(duration: 1.8, accessibilityLabel: text))]
        )
    }

    @Test
    func noticesKeepUpWithAHeldKey() throws {
        let volume = PluginID(rawValue: "com.cascade.volume")!
        var kernel = Fixtures.kernel(sources: ["volume"])
        _ = kernel.register(try noticer(), grants: [], at: start)
        _ = kernel.complete(volume, token: 1, result: Fixtures.result(try PluginOutput()), at: start)

        for step in 1...20 {
            let now   = start.advanced(by: Double(step) * 0.04)
            let state = try PluginSourceEvent(source: "volume", fields: ["announcement": .number(Double(step))])

            #expect(kernel.receive(state, at: now) == [.dispatch(volume, .source(state), token: UInt64(step + 1))])
            _ = kernel.complete(volume, token: UInt64(step + 1), result: Fixtures.result(try notice("\(step)"), cpuTime: .microseconds(100)), at: now)
        }
    }

    @Test
    func aSwitchedOffPluginSaysSo() throws {
        var kernel = Fixtures.kernel()
        _ = kernel.register(try Fixtures.clock(), grants: [], at: start)

        _ = kernel.setEnabled(false, for: clock, at: start)

        #expect(kernel.state(of: clock) == .switchedOff)
        #expect(kernel.states() == [clock: .switchedOff])
    }
}
