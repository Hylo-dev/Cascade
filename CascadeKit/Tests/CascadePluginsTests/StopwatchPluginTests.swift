//
//  StopwatchPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct StopwatchPluginTests {

    private let context = PluginContext(plugin: StopwatchPlugin.id)
    private let start   = Date(timeIntervalSince1970: 1_800_000_000)

    private func action(_ name: String) throws -> PluginEvent {
        .action(try PluginActionEvent(feature: StopwatchPlugin.feature, action: name))
    }

    private func widget(in output: PluginOutput) throws -> PluginNode {
        let publication = try #require(output.publications.first)

        #expect(output.publications.count == 1)
        #expect(publication.feature == StopwatchPlugin.feature)
        #expect(publication.surface == .widget)

        return try #require(publication.document).root
    }

    private func actions(in root: PluginNode) -> Set<String> {
        Set(PluginNodeSearch.actions(in: root))
    }

    // MARK: - The state

    @Test
    func startingAnIdleStopwatchRunsItFromNothing() {
        #expect(StopwatchState.idle.starting(at: start) == .running(since: start, before: 0))
    }

    @Test
    func startingAPausedStopwatchCarriesWhatItHadCounted() {
        #expect(StopwatchState.paused(elapsed: 75).starting(at: start) == .running(since: start, before: 75))
    }

    @Test
    func startingARunningStopwatchAgainChangesNothing() {
        let running = StopwatchState.running(since: start, before: 10)

        #expect(running.starting(at: start.addingTimeInterval(30)) == running)
    }

    @Test
    func pausingARunningStopwatchKeepsAllItCounted() {
        let state = StopwatchState.running(since: start, before: 10).pausing(at: start.addingTimeInterval(65))

        #expect(state == .paused(elapsed: 75))
    }

    @Test
    func pausingAStopwatchThatIsNotRunningChangesNothing() {
        #expect(StopwatchState.idle.pausing(at: start) == .idle)
        #expect(StopwatchState.paused(elapsed: 5).pausing(at: start) == .paused(elapsed: 5))
    }

    @Test
    func resettingAlwaysLeavesAnIdleStopwatch() {
        let states: [StopwatchState] = [.idle, .running(since: start, before: 3), .paused(elapsed: 9)]

        #expect(states.allSatisfy { $0.resetting() == .idle })
    }

    // MARK: - The plugin

    @Test
    func anIdleStopwatchShowsNothingCountedAndOffersStart() throws {
        let start  = self.start
        let plugin = StopwatchPlugin(now: { start })

        let output = try plugin.handle(.refresh, context: context)
        let root   = try widget(in: output)

        #expect(PluginNodeSearch.texts(in: root).contains("0:00"))
        #expect(actions(in: root) == ["start"])
        #expect(output.wake == nil)
    }

    /// A running stopwatch is the kernel's timer counting up from when it would have started had
    /// it never paused, so the plugin never runs while it counts.
    @Test
    func aRunningStopwatchIsTheKernelsTimerFromItsFirstStart() throws {
        let clock  = TestClock(start)
        let plugin = StopwatchPlugin(now: { clock.now })
        _ = try plugin.handle(try action("start"), context: context)
        clock.move(to: start.addingTimeInterval(75))
        _ = try plugin.handle(try action("pause"), context: context)

        clock.move(to: start.addingTimeInterval(200))
        let output = try plugin.handle(try action("start"), context: context)
        let root   = try widget(in: output)
        let lower  = start.addingTimeInterval(125)

        #expect(PluginNodeSearch.kinds(in: root).contains(.timer(start: lower, end: .distantFuture, countsDown: false)))
        #expect(actions(in: root) == ["pause"])
        #expect(output.wake == nil)
    }

    @Test
    func aPausedStopwatchShowsWhatItCountedAndOffersResumeAndReset() throws {
        let clock  = TestClock(start)
        let plugin = StopwatchPlugin(now: { clock.now })
        _ = try plugin.handle(try action("start"), context: context)

        clock.move(to: start.addingTimeInterval(75))
        let paused = try plugin.handle(try action("pause"), context: context)
        let reset  = try plugin.handle(try action("reset"), context: context)

        #expect(PluginNodeSearch.texts(in: try widget(in: paused)).contains("1:15"))
        #expect(!PluginNodeSearch.kinds(in: try widget(in: paused)).contains { $0.name == "timer" })
        #expect(actions(in: try widget(in: paused)) == ["start", "reset"])
        #expect(actions(in: try widget(in: reset)) == ["start"])
    }

    @Test
    func aPausedStopwatchPastAnHourShowsTheHours() throws {
        let document = try #require(try StopwatchFace.publication(for: .paused(elapsed: 3_725)).document)

        #expect(PluginNodeSearch.texts(in: document.root).contains("1:02:05"))
    }

    @Test
    func anActionThatChangesNothingPublishesNothing() throws {
        let start  = self.start
        let plugin = StopwatchPlugin(now: { start })

        let pause = try plugin.handle(try action("pause"), context: context)
        let wake  = try plugin.handle(.wake, context: context)

        #expect(pause.publications.isEmpty)
        #expect(wake.publications.isEmpty)
    }

    @Test
    func anUnknownActionChangesNothing() throws {
        let start  = self.start
        let plugin = StopwatchPlugin(now: { start })

        let output = try plugin.handle(try action("lap"), context: context)

        #expect(output.publications.isEmpty)
        #expect(output.wake == nil)
    }

    // MARK: - The faces and the manifest

    /// Start, pause and resume share one slot and reset has its own, empty until there is
    /// something to reset, so the press that resumes a paused stopwatch never lands on reset.
    @Test
    func everyButtonKeepsItsSlotOnBothFaces() throws {
        let states: [StopwatchState] = [.idle, .running(since: start, before: 0), .paused(elapsed: 30)]
        let faces  = try states.map { state in try #require(try StopwatchFace.publication(for: state).document).root.children }

        for face in 0..<2 {
            let slots      = try faces.map { PluginNodeSearch.slots(of: try #require(PluginNodeSearch.controlRow(in: $0[face])).row) }
            let placements = faces.map { FacePlacement($0[face]) }

            #expect(slots == [[nil, "start"], [nil, "pause"], ["reset", "start"]])
            #expect(placements[0] != nil)
            #expect(placements.allSatisfy { $0 == placements[0] })
        }
    }

    /// The button that resumes a paused stopwatch says so to VoiceOver, though it sends `start`.
    @Test
    func thePausedStartButtonReadsResume() throws {
        let paused = PluginNodeSearch.nodes(in: try #require(try StopwatchFace.publication(for: .paused(elapsed: 30)).document).root)
        let idle   = PluginNodeSearch.nodes(in: try #require(try StopwatchFace.publication(for: .idle).document).root)

        #expect(Set(paused.filter { $0.kind == .button(action: "start") }.map(PluginNodeSearch.accessibilityLabel)) == ["Resume"])
        #expect(Set(idle.filter { $0.kind == .button(action: "start") }.map(PluginNodeSearch.accessibilityLabel)) == ["Start"])
    }

    /// Every button, and every empty slot that holds a button's place, is at least the 20 points
    /// macOS asks of a control.
    @Test
    func everySlotIsAtLeastTwentyPointsSquare() throws {
        let states: [StopwatchState] = [.idle, .running(since: start, before: 0), .paused(elapsed: 30)]

        for state in states {
            for face in try #require(try StopwatchFace.publication(for: state).document).root.children {
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
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == StopwatchPlugin.id })
        let declared = Set(try #require(manifest.features.first).actions)
        let states: [StopwatchState] = [.idle, .running(since: start, before: 0), .paused(elapsed: 30)]

        for state in states {
            let root    = try #require(try StopwatchFace.publication(for: state).document).root
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

    @Test
    func theWiderFaceIsChosenByItsFixedWidth() throws {
        let document = try #require(try StopwatchFace.publication(for: .idle).document)
        let medium   = try #require(document.root.children.first)

        #expect(document.root.kind == .viewThatFits(axes: .horizontal))
        #expect(document.root.children.count == 2)
        #expect(medium.modifiers.contains { modifier in
            if case .frame(StopwatchFace.mediumWidth?, _, _, _, _) = modifier { return true }

            return false
        })
    }

    @Test
    func theManifestDeclaresTheSmallAndTheShortTileAndTheActions() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == StopwatchPlugin.id })
        let feature  = try #require(manifest.features.first)
        let sizes    = [try PluginWidgetSize(columns: 1, rows: 1), try PluginWidgetSize(columns: 2, rows: 1)]

        #expect(manifest.execution.entryPoint == "StopwatchPlugin")
        #expect(manifest.features.count == 1)
        #expect(feature.id == StopwatchPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == sizes)
        #expect(feature.actions == ["start", "pause", "reset"])
        #expect(!FirstPartyPlugins.placedByDefault.contains(StopwatchPlugin.id))
        #expect(FirstPartyPlugins.name(of: StopwatchPlugin.id) == "Stopwatch")
    }
}
