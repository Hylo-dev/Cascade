//
//  TimerPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct TimerPluginTests {

    private let context = PluginContext(plugin: TimerPlugin.id)
    private let start   = Date(timeIntervalSince1970: 1_800_000_000)

    private func action(_ name: String) throws -> PluginEvent {
        .action(try PluginActionEvent(feature: TimerPlugin.feature, action: name))
    }

    private func widget(in output: PluginOutput) throws -> PluginNode {
        let publication = try #require(output.publications.first { $0.surface == .widget })

        #expect(publication.feature == TimerPlugin.feature)

        return try #require(publication.document).root
    }

    private func actions(in root: PluginNode) -> Set<String> {
        Set(PluginNodeSearch.actions(in: root))
    }

    /// faces lists a state's faces, largest first: the 2x2, the 2x1 and the 1x1.
    private func faces(of state: TimerState) throws -> [PluginNode] {
        let root    = try #require(try TimerFace.publication(for: state).document).root
        let smaller = try #require(root.children.last)

        return [try #require(root.children.first)] + smaller.children
    }

    private func slots(of face: PluginNode) throws -> [String?] {
        PluginNodeSearch.slots(of: try #require(PluginNodeSearch.controlRow(in: face)).row)
    }

    /// plugin is a timer whose clock stands at `start` until the test moves it.
    private func plugin() -> (TimerPlugin, TestClock) {
        let clock = TestClock(start)

        return (TimerPlugin(now: { clock.now }), clock)
    }

    // MARK: - The state

    @Test
    func addingGrowsAnIdleTimer() {
        let state = TimerState.idle(duration: 0)
            .adding(60, at: start)
            .adding(300, at: start)

        #expect(state == .idle(duration: 360))
    }

    @Test
    func addingGrowsAPausedTimersRemainingTimeAndTotal() {
        let state = TimerState.paused(remaining: 30, duration: 120).adding(60, at: start)

        #expect(state == .paused(remaining: 90, duration: 180))
    }

    /// Adding to a running timer moves its end and its total alike, so the bar keeps its start.
    @Test
    func addingFiveMinutesToARunningTimerMovesItsEndByThreeHundredSeconds() {
        let end   = start.addingTimeInterval(60)
        let state = TimerState.running(end: end, duration: 120).adding(300, at: start)

        #expect(state == .running(end: end.addingTimeInterval(300), duration: 420))
    }

    @Test
    func theTotalNeverPassesNinetyNineMinutes() {
        let cap = 99.0 * 60
        let end = start.addingTimeInterval(cap - 120)

        #expect(TimerState.idle(duration: cap - 60).adding(300, at: start) == .idle(duration: cap))
        #expect(TimerState.idle(duration: cap).adding(60, at: start) == .idle(duration: cap))
        #expect(TimerState.paused(remaining: 100, duration: cap - 60).adding(300, at: start) == .paused(remaining: 160, duration: cap))
        #expect(TimerState.running(end: end, duration: cap - 120).adding(300, at: start) == .running(end: end.addingTimeInterval(120), duration: cap))
        #expect(TimerState.running(end: end, duration: cap).adding(60, at: start) == .running(end: end, duration: cap))
    }

    @Test
    func startingAnIdleTimerRunsItForItsDuration() {
        let state = TimerState.idle(duration: 300).starting(at: start)

        #expect(state == .running(end: start.addingTimeInterval(300), duration: 300))
    }

    @Test
    func startingAnIdleTimerWithNothingSetChangesNothing() {
        #expect(TimerState.idle(duration: 0).starting(at: start) == .idle(duration: 0))
    }

    @Test
    func startingARunningTimerAgainChangesNothing() {
        let running = TimerState.idle(duration: 300).starting(at: start)

        #expect(running.starting(at: start.addingTimeInterval(10)) == running)
    }

    @Test
    func startingAPausedTimerResumesItFromWhatWasLeft() {
        let state = TimerState.paused(remaining: 45, duration: 300).starting(at: start)

        #expect(state == .running(end: start.addingTimeInterval(45), duration: 300))
    }

    @Test
    func pausingARunningTimerKeepsWhatIsLeft() {
        let state = TimerState.running(end: start.addingTimeInterval(45), duration: 300).pausing(at: start)

        #expect(state == .paused(remaining: 45, duration: 300))
    }

    @Test
    func pausingARunningTimerAfterItsEndLeavesNothing() {
        let state = TimerState.running(end: start, duration: 300).pausing(at: start.addingTimeInterval(5))

        #expect(state == .paused(remaining: 0, duration: 300))
    }

    @Test
    func pausingATimerThatIsNotRunningChangesNothing() {
        #expect(TimerState.idle(duration: 0).pausing(at: start) == .idle(duration: 0))
        #expect(TimerState.idle(duration: 60).pausing(at: start) == .idle(duration: 60))
        #expect(TimerState.paused(remaining: 10, duration: 60).pausing(at: start) == .paused(remaining: 10, duration: 60))
    }

    @Test
    func resettingAlwaysLeavesAnIdleTimerWithNothingSet() {
        let states: [TimerState] = [
            .idle(duration: 0),
            .idle(duration: 60),
            .running(end: start, duration: 60),
            .paused(remaining: 10, duration: 60),
        ]

        #expect(states.allSatisfy { $0.resetting() == .idle(duration: 0) })
    }

    @Test
    func aTimerIsFinishedOnlyWhenItRunsAndItsEndHasCome() {
        let end = start.addingTimeInterval(60)

        #expect(!TimerState.running(end: end, duration: 60).isFinished(at: start))
        #expect(TimerState.running(end: end, duration: 60).isFinished(at: end))
        #expect(TimerState.running(end: end, duration: 60).isFinished(at: end.addingTimeInterval(1)))
        #expect(!TimerState.idle(duration: 60).isFinished(at: end))
        #expect(!TimerState.paused(remaining: 0, duration: 60).isFinished(at: end))
    }

    // MARK: - The plugin

    @Test
    func anIdleTimerWithNothingSetOffersOnlyTheTwoAdditionsAndAsksForNoWake() throws {
        let (plugin, _) = plugin()

        let output = try plugin.handle(.refresh, context: context)
        let root   = try widget(in: output)

        #expect(output.publications.count == 1)
        #expect(actions(in: root) == ["add1", "add5"])
        #expect(PluginNodeSearch.texts(in: root).contains("0:00"))
        #expect(output.wake == nil)
    }

    @Test
    func anAdditionSetsTheDurationAndOffersStartWithoutStartingIt() throws {
        let (plugin, _) = plugin()

        let output = try plugin.handle(try action("add1"), context: context)
        let root   = try widget(in: output)

        #expect(actions(in: root) == ["add1", "add5", "start", "reset"])
        #expect(PluginNodeSearch.texts(in: root).contains("1:00"))
        #expect(!PluginNodeSearch.kinds(in: root).contains { $0.name == "timer" })
        #expect(output.wake == nil)
    }

    /// A running timer is the kernel's countdown and bar over the whole run, and asks to be woken
    /// at its end and not before.
    @Test
    func aRunningTimerIsTheKernelsCountdownAndBarAndAsksForItsEnd() throws {
        let (plugin, _) = plugin()
        _ = try plugin.handle(try action("add5"), context: context)

        let output = try plugin.handle(try action("start"), context: context)
        let root   = try widget(in: output)
        let end    = start.addingTimeInterval(300)
        let kinds  = PluginNodeSearch.kinds(in: root)

        #expect(kinds.contains(.timer(start: start, end: end, countsDown: true)))
        #expect(kinds.contains(.timerProgress(start: start, end: end)))
        #expect(actions(in: root) == ["pause", "add1"])
        #expect(output.wake == end)
    }

    @Test
    func addingWhileRunningMovesTheEndAndTheWake() throws {
        let (plugin, clock) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)

        clock.move(to: start.addingTimeInterval(20))
        let output = try plugin.handle(try action("add1"), context: context)
        let end    = start.addingTimeInterval(120)

        #expect(PluginNodeSearch.kinds(in: try widget(in: output)).contains(.timerProgress(start: start, end: end)))
        #expect(output.wake == end)
    }

    @Test
    func aWakeBeforeTheEndPublishesNothingAndAsksForTheEndAgain() throws {
        let (plugin, clock) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)

        clock.move(to: start.addingTimeInterval(59.5))
        let output = try plugin.handle(.wake, context: context)

        #expect(output.publications.isEmpty)
        #expect(output.wake == start.addingTimeInterval(60))
    }

    /// At its end the timer goes back to idle with nothing set and tells it is done with one
    /// notice, and asks for no further wake.
    @Test
    func theWakeAtTheEndPublishesTheIdleWidgetAndOneFinishedNotice() throws {
        let (plugin, clock) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)

        clock.move(to: start.addingTimeInterval(60))
        let output     = try plugin.handle(.wake, context: context)
        let root       = try widget(in: output)
        let notice     = try #require(output.publications.first { $0.surface == .notice })
        let document   = try #require(notice.document)
        let attributes = try #require(notice.notice)

        #expect(output.publications.count == 2)
        #expect(actions(in: root) == ["add1", "add5"])
        #expect(PluginNodeSearch.texts(in: root).contains("0:00"))
        #expect(notice.feature == TimerPlugin.finished)
        #expect(document.root.kind == .regions)
        #expect(document.root.children.map(\.kind) == [.symbol(name: "timer"), .text("Done"), .symbol(name: "timer")])
        #expect(attributes.duration == 4)
        #expect(attributes.border == .neutral)
        #expect(attributes.accessibilityLabel == "Timer finished")
        #expect(output.wake == nil)
    }

    @Test
    func aPausedTimerShowsWhatIsLeftOnAStillBarAndOffersResumeAndReset() throws {
        let (plugin, clock) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)

        clock.move(to: start.addingTimeInterval(15))
        let output = try plugin.handle(try action("pause"), context: context)
        let root   = try widget(in: output)
        let kinds  = PluginNodeSearch.kinds(in: root)

        #expect(PluginNodeSearch.texts(in: root).contains("0:45"))
        #expect(kinds.contains(.progress(value: 15, total: 60, style: .linear)))
        #expect(!kinds.contains { $0.name == "timer" || $0.name == "timerProgress" })
        #expect(actions(in: root) == ["start", "reset"])
        #expect(output.wake == nil)
    }

    /// A paused timer shows a second that has begun as a whole one, as a countdown does, so it
    /// never reads 0:00 while time is left.
    @Test
    func aPausedTimerRoundsWhatIsLeftUp() throws {
        let document = try #require(try TimerFace.publication(for: .paused(remaining: 0.4, duration: 60)).document)

        #expect(PluginNodeSearch.texts(in: document.root).contains("0:01"))
    }

    @Test
    func resumingRunsForWhatWasLeftAndResettingClearsTheTimer() throws {
        let (plugin, clock) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)
        clock.move(to: start.addingTimeInterval(15))
        _ = try plugin.handle(try action("pause"), context: context)

        clock.move(to: start.addingTimeInterval(100))
        let resumed = try plugin.handle(try action("start"), context: context)
        _ = try plugin.handle(try action("pause"), context: context)
        let reset   = try plugin.handle(try action("reset"), context: context)

        #expect(resumed.wake == start.addingTimeInterval(145))
        #expect(PluginNodeSearch.kinds(in: try widget(in: resumed)).contains(.timerProgress(start: start.addingTimeInterval(85), end: start.addingTimeInterval(145))))
        #expect(actions(in: try widget(in: reset)) == ["add1", "add5"])
        #expect(reset.wake == nil)
    }

    @Test
    func anActionThatChangesNothingPublishesNothing() throws {
        let (plugin, _) = plugin()

        let pause = try plugin.handle(try action("pause"), context: context)
        let start = try plugin.handle(try action("start"), context: context)

        #expect(pause.publications.isEmpty)
        #expect(start.publications.isEmpty)
        #expect(pause.wake == nil)
    }

    /// A press that comes after the end but before the wake finds the timer done: it tells so,
    /// and the press applies to the idle timer.
    @Test
    func aPressAfterTheEndFinishesTheTimerFirst() throws {
        let (plugin, clock) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)

        clock.move(to: start.addingTimeInterval(60.5))
        let output = try plugin.handle(try action("add5"), context: context)

        #expect(output.publications.contains { $0.surface == .notice })
        #expect(PluginNodeSearch.texts(in: try widget(in: output)).contains("5:00"))
        #expect(output.wake == nil)
    }

    /// A second wake after the end, which a restarted kernel timer could send, finds an idle
    /// timer and tells nothing again.
    @Test
    func aSecondWakeAfterTheEndTellsNothingAgain() throws {
        let (plugin, clock) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)
        clock.move(to: start.addingTimeInterval(60))
        _ = try plugin.handle(.wake, context: context)

        clock.move(to: start.addingTimeInterval(61))
        let output = try plugin.handle(.wake, context: context)

        #expect(output.publications.isEmpty)
        #expect(output.wake == nil)
    }

    /// A PluginHost restart makes a new plugin, which knows nothing of the timer it ran, so the
    /// first refresh shows the idle face and asks for no wake.
    @Test
    func aRestartedPluginShowsAnIdleTimerAndAsksForNoWake() throws {
        let (before, _) = plugin()
        _ = try before.handle(try action("add5"), context: context)
        _ = try before.handle(try action("start"), context: context)

        let (after, _) = plugin()
        let output     = try after.handle(.refresh, context: context)

        #expect(actions(in: try widget(in: output)) == ["add1", "add5"])
        #expect(PluginNodeSearch.texts(in: try widget(in: output)).contains("0:00"))
        #expect(output.wake == nil)
    }

    /// An action the plugin does not know changes nothing, and a running timer keeps its wake.
    @Test
    func anUnknownActionChangesNothingAndKeepsTheWake() throws {
        let (plugin, _) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)

        let output = try plugin.handle(try action("lap"), context: context)

        #expect(output.publications.isEmpty)
        #expect(output.wake == start.addingTimeInterval(60))
    }

    @Test
    func resettingARunningTimerShowsItIdleAndCancelsTheWake() throws {
        let (plugin, _) = plugin()
        _ = try plugin.handle(try action("add1"), context: context)
        _ = try plugin.handle(try action("start"), context: context)

        let output = try plugin.handle(try action("reset"), context: context)

        #expect(actions(in: try widget(in: output)) == ["add1", "add5"])
        #expect(!output.publications.contains { $0.surface == .notice })
        #expect(output.wake == nil)
    }

    /// A length set by mistake can be cleared without starting the timer.
    @Test
    func resettingAnIdleTimerClearsItsLength() throws {
        let (plugin, _) = plugin()
        _ = try plugin.handle(try action("add5"), context: context)

        let output = try plugin.handle(try action("reset"), context: context)
        let root   = try widget(in: output)

        #expect(PluginNodeSearch.texts(in: root).contains("0:00"))
        #expect(actions(in: root) == ["add1", "add5"])
    }

    // MARK: - The faces and the manifest

    /// Every button keeps its slot as the state changes, so a second press where the first one
    /// landed hits the control that is there now by design: start becomes pause and pause
    /// resume in one slot, +1 and +5 stay put as the length grows, and reset never takes the
    /// slot of start, pause or +1. The 2x2 face has room for reset while idle; the 2x1 face
    /// gives it the slot +5 leaves while paused, the 1x1 face the one +1 leaves, so a second
    /// press there only adds to the idle timer.
    @Test
    func everyButtonKeepsItsSlotOnEveryFace() throws {
        let states: [TimerState] = [
            .idle(duration: 0),
            .idle(duration: 60),
            .running(end: start.addingTimeInterval(60), duration: 60),
            .paused(remaining: 30, duration: 60),
        ]
        let faces = try states.map { try self.faces(of: $0) }

        #expect(try faces.map { try slots(of: $0[0]) } == [
            ["add1", "add5", nil, nil],
            ["add1", "add5", "reset", "start"],
            ["add1", nil, nil, "pause"],
            [nil, nil, "reset", "start"],
        ])
        #expect(try faces.map { try slots(of: $0[1]) } == [
            ["add1", "add5", nil],
            ["add1", "add5", "start"],
            ["add1", nil, "pause"],
            [nil, "reset", "start"],
        ])
        #expect(try faces.map { try slots(of: $0[2]) } == [
            ["add1", nil],
            ["add1", "start"],
            ["add1", "pause"],
            ["reset", "start"],
        ])

        for face in 0..<3 {
            let placements = faces.map { FacePlacement($0[face]) }

            #expect(placements[0] != nil)
            #expect(placements.allSatisfy { $0 == placements[0] })
        }
    }

    /// The button that resumes a paused timer says so to VoiceOver, though it sends `start`.
    @Test
    func thePausedStartButtonReadsResume() throws {
        let paused = try faces(of: .paused(remaining: 30, duration: 60)).flatMap(PluginNodeSearch.nodes)
        let idle   = try faces(of: .idle(duration: 60)).flatMap(PluginNodeSearch.nodes)

        #expect(Set(paused.filter { $0.kind == .button(action: "start") }.map(PluginNodeSearch.accessibilityLabel)) == ["Resume"])
        #expect(Set(idle.filter { $0.kind == .button(action: "start") }.map(PluginNodeSearch.accessibilityLabel)) == ["Start"])
    }

    /// Every button, and every empty slot that holds a button's place, is at least the 20 points
    /// macOS asks of a control.
    @Test
    func everySlotIsAtLeastTwentyPointsSquare() throws {
        let states: [TimerState] = [.idle(duration: 0), .idle(duration: 60), .paused(remaining: 30, duration: 60)]

        for state in states {
            for face in try faces(of: state) {
                let row = try #require(PluginNodeSearch.controlRow(in: face)).row

                for slot in row.children {
                    let target = slot.kind.name == "button" ? try #require(slot.children.first) : slot

                    #expect(target.modifiers.contains { modifier in
                        if case .frame(let width?, let height?, _, _, _) = modifier { return width >= 20 && height >= 20 }

                        return false
                    })
                }
            }
        }
    }

    /// Every button of every state is one the manifest declares and VoiceOver can name.
    @Test
    func everyButtonIsDeclaredAndNamed() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == TimerPlugin.id })
        let declared = Set(try #require(manifest.features.first { $0.id == TimerPlugin.feature }).actions)
        let states: [TimerState] = [
            .idle(duration: 0),
            .idle(duration: 60),
            .running(end: start.addingTimeInterval(60), duration: 60),
            .paused(remaining: 30, duration: 60),
        ]

        for state in states {
            let root    = try #require(try TimerFace.publication(for: state).document).root
            let buttons = PluginNodeSearch.nodes(in: root).filter { $0.kind.name == "button" }

            #expect(!buttons.isEmpty)
            #expect(actions(in: root).isSubset(of: declared))
            #expect(buttons.allSatisfy { button in
                button.modifiers.contains { modifier in
                    if case .accessibilityLabel(let label) = modifier { return !label.isEmpty }

                    return false
                }
            })
        }
    }

    /// The face for each tile, largest first: the 2x2 face is chosen by its fixed height, and the
    /// 2x1 face, by its fixed width, before the 1x1 one.
    @Test
    func theFacesAreChosenByTheTile() throws {
        let document = try #require(try TimerFace.publication(for: .idle(duration: 0)).document)
        let large    = try #require(document.root.children.first)
        let smaller  = try #require(document.root.children.last)
        let medium   = try #require(smaller.children.first)

        #expect(document.root.kind == .viewThatFits(axes: .vertical))
        #expect(document.root.children.count == 2)
        #expect(large.modifiers.contains { modifier in
            if case .frame(_, TimerFace.largeHeight?, _, _, _) = modifier { return true }

            return false
        })
        #expect(smaller.kind == .viewThatFits(axes: .horizontal))
        #expect(smaller.children.count == 2)
        #expect(medium.modifiers.contains { modifier in
            if case .frame(TimerFace.mediumWidth?, _, _, _, _) = modifier { return true }

            return false
        })
    }

    @Test
    func theManifestDeclaresTheWidgetItsActionsAndTheFinishedNotice() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == TimerPlugin.id })
        let timer    = try #require(manifest.features.first { $0.id == TimerPlugin.feature })
        let finished = try #require(manifest.features.first { $0.id == TimerPlugin.finished })
        let sizes    = [
            try PluginWidgetSize(columns: 1, rows: 1),
            try PluginWidgetSize(columns: 2, rows: 1),
            try PluginWidgetSize(columns: 2, rows: 2),
        ]

        #expect(manifest.execution.entryPoint == "TimerPlugin")
        #expect(manifest.features.count == 2)
        #expect(timer.surfaces.widget?.sizes == sizes)
        #expect(timer.actions == ["add1", "add5", "start", "pause", "reset"])
        #expect(timer.sources.isEmpty)
        #expect(finished.surfaces.notice != nil)
        #expect(finished.surfaces.widget == nil)
        #expect(!FirstPartyPlugins.placedByDefault.contains(TimerPlugin.id))
        #expect(FirstPartyPlugins.name(of: TimerPlugin.id) == "Timer")
    }
}
