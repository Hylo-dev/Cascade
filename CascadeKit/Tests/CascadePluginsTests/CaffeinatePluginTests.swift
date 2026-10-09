//
//  CaffeinatePluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct CaffeinatePluginTests {

    private static let now     = Date(timeIntervalSince1970: 2_000_000_000)
    private static let amber   = PluginColor(red: 1, green: 0.77, blue: 0.33)
    private static let started = now.addingTimeInterval(-600)

    private let context = PluginContext(plugin: CaffeinatePlugin.id)

    /// The tests live in UTC. 2_000_000_000 is 03:33:20 there, so the ruler's Until range runs
    /// from 04:00, the first quarter hour 15 minutes ahead, to 03:30 the next day.
    private static let utc: Calendar = {
        var calendar      = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        return calendar
    }()

    private static let rangeStart = 2_000_001_600.0
    private static let rangeEnd   = 2_000_086_200.0
    private static let sixPM      = 2_000_052_000.0

    private func plugin() -> CaffeinatePlugin {
        CaffeinatePlugin(now: { Self.now }, calendar: { Self.utc })
    }

    private func off(nextTarget: CaffeinateTarget = .duration(minutes: 90)) -> PluginCaffeinateState {
        PluginCaffeinateState(nextTarget: nextTarget)
    }

    private func timed(
        minutesLeft: Double = 24,
        glyph      : CaffeinateGlyph = .cupHeatWaves
    ) -> PluginCaffeinateState {
        PluginCaffeinateState(
            startedAt        : Self.started,
            endsAt           : Self.now.addingTimeInterval(minutesLeft * 60),
            activityStartedAt: Self.started,
            glyph            : glyph
        )
    }

    private func indefinite() -> PluginCaffeinateState {
        PluginCaffeinateState(
            startedAt        : Self.started,
            activityStartedAt: Self.started,
            nextTarget       : .indefinite
        )
    }

    private func send(
        _ state: PluginCaffeinateState,
        to plugin: CaffeinatePlugin
    ) throws -> PluginOutput {
        try plugin.handle(.source(state.event()), context: context)
    }

    private func widget(_ output: PluginOutput) -> PluginPublication? {
        output.publications.first { $0.surface == .widget }
    }

    private func activity(_ output: PluginOutput) -> PluginPublication? {
        output.publications.first { $0.surface == .activity }
    }

    private func nodes(_ publication: PluginPublication?) throws -> [PluginNodeTable.Entry] {
        PluginNodeTable(try #require(publication?.document)).entries
    }

    private func texts(_ entries: [PluginNodeTable.Entry]) -> [String] {
        entries.compactMap { entry in
            if case .text(let text) = entry.kind { text } else { nil }
        }
    }

    private func controls(_ entries: [PluginNodeTable.Entry]) -> Set<PluginNodeID> {
        Set(
            entries.filter {
                switch $0.kind {
                    case .button, .toggle: true
                    default              : false
                }
            }.map(\.id)
        )
    }

    private func symbols(_ entries: [PluginNodeTable.Entry]) -> Set<String> {
        Set(
            entries.compactMap { entry in
                if case .symbol(let name) = entry.kind { name } else { nil }
            }
        )
    }

    // MARK: - Publishing

    @Test
    func offPublishesTheWidgetAndNoActivity() throws {
        let output = try send(off(), to: plugin())

        #expect(widget(output)?.feature == CaffeinatePlugin.feature)
        #expect(activity(output)?.document == nil)
        #expect(output.publications.count == 2)
        #expect(widget(output)?.staleAfter == nil)
        #expect(widget(output)?.document?.optionsAction == "caffeinate.options")
        #expect(widget(output)?.document?.optionsRoot != nil)
    }

    @Test
    func onPublishesBothAndTheActivityHasThreeRegions() throws {
        let output   = try send(timed(), to: plugin())
        let activity = try #require(activity(output))
        let root     = try #require(activity.document?.root)

        #expect(output.publications.count == 2)
        #expect(widget(output) != nil)
        #expect(root.kind == .regions)
        #expect(root.children.count == 3)
        #expect(activity.feature == CaffeinatePlugin.feature)
        #expect(activity.activity?.relevance == 0.3)
    }

    @Test
    func stoppingWithdrawsTheActivityOnce() throws {
        let plugin = plugin()

        _ = try send(timed(), to: plugin)

        let stopped    = try send(off(), to: plugin)
        let withdrawal = try #require(activity(stopped))
        #expect(withdrawal.document == nil)
        #expect(withdrawal.activity == nil)

        let again = try send(off(nextTarget: .duration(minutes: 30)), to: plugin)
        #expect(activity(again) == nil)
        #expect(widget(again) != nil)

        _ = try send(timed(), to: plugin)
        #expect(activity(try send(off(), to: plugin))?.document == nil)
    }

    /// A restarted PluginHost has no memory, and the kernel may still hold the activity of a
    /// session that ended while it was down: the first snapshot without a session withdraws it.
    @Test
    func aFreshPluginWithdrawsAStrandedActivity() throws {
        let plugin = plugin()

        let first       = try send(off(), to: plugin)
        let withdrawals = first.publications.filter { $0.surface == .activity }
        #expect(withdrawals.count == 1)
        #expect(withdrawals.first?.document == nil)

        let second = try send(off(), to: plugin)
        #expect(second.publications.isEmpty)
        #expect(activity(try send(off(nextTarget: .duration(minutes: 30)), to: plugin)) == nil)
    }

    @Test
    func noPublicationForAnUnchangedState() throws {
        let plugin = plugin()
        let state  = timed()

        #expect(try send(state, to: plugin).publications.count == 2)
        #expect(try send(state, to: plugin).publications.isEmpty)
        #expect(try send(off(), to: plugin).publications.count == 2)
        #expect(try send(off(), to: plugin).publications.isEmpty)

        let fresh = self.plugin()
        #expect(try send(off(), to: fresh).publications.count == 2)
        #expect(try send(off(), to: fresh).publications.isEmpty)
    }

    @Test
    func aChangedEndRepublishesBothDocuments() throws {
        let plugin = plugin()

        _ = try send(timed(minutesLeft: 24), to: plugin)
        let extended = try send(timed(minutesLeft: 39), to: plugin)

        #expect(extended.publications.count == 2)
    }

    @Test
    func aRefreshRepublishesTheLastStateAndNothingBeforeOne() throws {
        let plugin = plugin()

        #expect(try plugin.handle(.refresh, context: context).publications.isEmpty)

        _ = try send(timed(), to: plugin)
        let refreshed = try plugin.handle(.refresh, context: context)
        #expect(widget(refreshed) != nil)
        #expect(activity(refreshed) != nil)

        _ = try send(off(), to: plugin)
        let afterStop = try plugin.handle(.refresh, context: context)
        #expect(afterStop.publications.count == 1)
        #expect(widget(afterStop) != nil)
    }

    @Test
    func actionsAndMalformedSourcesPublishNothing() throws {
        let plugin    = plugin()
        let malformed = try PluginSourceEvent(source: "caffeinate", fields: ["keepsDisplayAwake": .bool(true)])

        #expect(try plugin.handle(.source(malformed), context: context).publications.isEmpty)
        #expect(try plugin.handle(.wake, context: context).publications.isEmpty)
        #expect(
            try plugin.handle(
                .action(PluginActionEvent(feature: CaffeinatePlugin.feature, action: "caffeinate.start", value: .bool(true))),
                context: context
            ).publications.isEmpty
        )
    }

    @Test
    func noWakeEver() throws {
        let plugin = plugin()
        let states = [off(), timed(), indefinite(), PluginCaffeinateState(failure: .assertionRefused(-1))]

        for state in states {
            #expect(try send(state, to: plugin).wake == nil)
        }
        #expect(try plugin.handle(.refresh, context: context).wake == nil)
        #expect(try plugin.handle(.wake, context: context).wake == nil)
    }

    // MARK: - Activity

    @Test
    func timedCompactUsesTheCountdownNode() throws {
        let state    = timed()
        let output   = try send(state, to: plugin())
        let root     = try #require(activity(output)?.document?.root)
        let trailing = root.children[1]

        #expect(trailing.kind == .countdown(end: try #require(state.endsAt), style: .compact))
        #expect(trailing.modifiers.contains(.font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())))
        #expect(trailing.modifiers.contains(.foregroundStyle(.color(Self.amber))))

        let leading = root.children[0]
        #expect(leading.kind == .symbol(name: "cup.and.heat.waves.fill"))
        #expect(leading.modifiers.contains(.foregroundStyle(.color(Self.amber))))
        #expect(root.children[2].kind == .symbol(name: "cup.and.heat.waves.fill"))
    }

    @Test
    func indefiniteActivityIsTheGlyphAloneAndTheOptionsPageCountsUp() throws {
        let state   = indefinite()
        let output  = try send(state, to: plugin())
        let root    = try #require(activity(output)?.document?.root)
        let started = try #require(state.startedAt)
        let options = try nodes(PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .widget,
            document: PluginDocument(root: try #require(widget(output)?.document?.optionsRoot))
        ))

        #expect(root.children.count == 3)
        #expect(root.children[1].kind == .spacer(minLength: 0))
        #expect(options.contains { $0.kind == .timer(start: started, end: started.addingTimeInterval(365 * 86_400), countsDown: false) })
        #expect(texts(options).contains("Until you stop it"))
        #expect(!options.contains { if case .countdown = $0.kind { true } else { false } })
    }

    @Test
    func theActivityHasNoControlsAndNeverAnExpandedRegion() throws {
        for state in [timed(), indefinite()] {
            let output  = try send(state, to: plugin())
            let entries = try nodes(activity(output))

            #expect(controls(entries).isEmpty)
            #expect(!entries.contains { if case .button = $0.kind { true } else { false } })
            #expect(!entries.contains { if case .timer = $0.kind { true } else { false } })
            #expect(try #require(activity(output)?.document?.root).children.count == 3)
        }
    }

    /// kinds lists a subtree's node kinds, depth first, the node itself included.
    private func kinds(_ node: PluginNode) -> [PluginNodeKind] {
        [node.kind] + node.children.flatMap(kinds)
    }

    /// countUpLengths are the lengths of the count-up timers in a subtree.
    private func countUpLengths(_ node: PluginNode) -> [TimeInterval] {
        kinds(node).compactMap { kind in
            if case .timer(let start, let end, false) = kind { end.timeIntervalSince(start) } else { nil }
        }
    }

    /// anIndefiniteCountUpRunsPastADay keeps the elapsed time counting after 24 hours: the 2x2 and
    /// 2x1 faces and the options page all count in an interval far longer than a day.
    @Test
    func anIndefiniteCountUpRunsPastADay() throws {
        let output  = try send(indefinite(), to: plugin())
        let face    = try #require(widget(output)?.document?.root)
        let options = try #require(widget(output)?.document?.optionsRoot)
        let medium  = try #require(face.children.first)
        let large   = try #require(face.children.last?.children.first)

        for (name, node) in [("2x2", medium), ("2x1", large), ("options", options)] {
            #expect(!countUpLengths(node).isEmpty, "\(name)")
            #expect(countUpLengths(node).allSatisfy { $0 > 86_400 }, "\(name)")
        }
    }

    /// theOptionsTimeCountsDownWithTheKernelTimer: the big time is the kernel's timer node, and
    /// the font and the tint sit on that node, where the kernel reads them.
    @Test
    func theOptionsTimeCountsDownWithTheKernelTimer() throws {
        let state   = timed(minutesLeft: 110)
        let ends    = try #require(state.endsAt)
        let output  = try send(state, to: plugin())
        let options = try #require(widget(output)?.document?.optionsRoot)
        let face    = try #require(widget(output)?.document?.root)
        let entries = try nodes(PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .widget,
            document: PluginDocument(root: options)
        ))

        #expect(!kinds(options).contains(.countdown(end: ends, style: .hoursMinutes)))
        #expect(!kinds(options).contains(.countdown(end: ends, style: .compact)))
        #expect(kinds(face).contains(.countdown(end: ends, style: .compact)))

        let time = try #require(entries.first { $0.kind == .timer(start: Self.started, end: ends, countsDown: true) })
        #expect(time.modifiers.contains(.font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())))
        #expect(time.modifiers.contains(.foregroundStyle(.color(Self.amber))))
    }

    @Test
    func theOffTimeIsWhiteAndShowsTheNextDuration() throws {
        let output  = try send(off(nextTarget: .duration(minutes: 90)), to: plugin())
        let options = try #require(widget(output)?.document?.optionsRoot)
        let entries = try nodes(PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .widget,
            document: PluginDocument(root: options)
        ))
        let time    = try #require(entries.first { $0.kind == .text("1h 30m") })

        #expect(time.modifiers.contains(.font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())))
        #expect(time.modifiers.contains(.foregroundStyle(.color(.white))))
    }

    @Test
    func theOffTimeOfAnEndTimeIsTheKernelsClockAndOfInfinityTheSign() throws {
        let big = PluginFont.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()

        let until   = try nodes(optionsPublication(off(nextTarget: .until(minuteOfDay: 18 * 60))))
        let clock   = try #require(until.first { $0.kind == .date(Date(timeIntervalSince1970: Self.sixPM), style: .time) })
        #expect(clock.modifiers.contains(.font(big)))
        #expect(clock.modifiers.contains(.foregroundStyle(.color(.white))))

        let forever = try nodes(optionsPublication(off(nextTarget: .indefinite)))
        let sign    = try #require(forever.first { $0.kind == .text("∞") && $0.modifiers.contains(.font(big)) })
        #expect(sign.modifiers.contains(.foregroundStyle(.color(.white))))
    }

    /// optionsPublication wraps the options page of a state in a document of its own, so the
    /// node table can list it.
    private func optionsPublication(_ state: PluginCaffeinateState) throws -> PluginPublication {
        let output = try send(state, to: plugin())

        return try PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .widget,
            document: PluginDocument(root: try #require(widget(output)?.document?.optionsRoot))
        )
    }

    private func optionsRoot(_ state: PluginCaffeinateState) throws -> PluginNode {
        try #require(widget(try send(state, to: plugin()))?.document?.optionsRoot)
    }

    private func find(
        _ id: String,
        in node: PluginNode
    ) -> PluginNode? {
        if node.id == id { return node }

        for child in node.children + node.layers {
            if let found = find(id, in: child) { return found }
        }

        return nil
    }

    private func ids(_ node: PluginNode) -> [String] {
        (node.id.map { [$0] } ?? []) + (node.children + node.layers).flatMap(ids)
    }

    private func ruler(_ state: PluginCaffeinateState) throws -> PluginNode? {
        find("ruler", in: try optionsRoot(state))
    }

    /// theOptionsPageIsTwoBandsOfControls checks layout A by what it contains: the selector's
    /// three buttons and the two round switches on top, the ruler and the time under them, and
    /// no stepper and no captions.
    @Test
    func theOptionsPageIsTwoBandsOfControls() throws {
        let idle = try nodes(optionsPublication(off()))
        #expect(idle.contains { $0.id.rawValue == "#power.options:toggle" && $0.kind == .toggle(isOn: false, action: "caffeinate.start") })
        #expect(idle.contains { $0.id.rawValue == "#display:toggle" && $0.kind == .toggle(isOn: true, action: "caffeinate.display") })
        #expect(idle.contains { $0.id.rawValue == "#mode.duration:button" && $0.kind == .button(action: "caffeinate.mode.duration") })
        #expect(idle.contains { $0.id.rawValue == "#mode.until:button" && $0.kind == .button(action: "caffeinate.mode.until") })
        #expect(idle.contains { $0.id.rawValue == "#mode.indefinite:button" && $0.kind == .button(action: "caffeinate.mode.indefinite") })
        #expect(idle.contains { $0.id.rawValue == "#ruler:slider" })
        #expect(symbols(idle).isSuperset(of: ["play.fill", "stop.fill", "display", "moon.zzz"]))
        #expect(Set(texts(idle)).isSuperset(of: ["For", "Until", "∞"]))
        #expect(!idle.contains { $0.kind == .button(action: "caffeinate.extend") })
        #expect(!idle.contains { $0.kind == .button(action: "caffeinate.duration.up") })
        #expect(!idle.contains { $0.kind == .button(action: "caffeinate.duration.down") })
        #expect(!texts(idle).contains("Next session"))

        let running = try nodes(optionsPublication(timed()))
        #expect(running.contains { $0.id.rawValue == "#power.options:toggle" && $0.kind == .toggle(isOn: true, action: "caffeinate.stop") })
    }

    /// everyExplicitIdentityIsUnique: the options page and the faces share a document, and an
    /// identity may name only one node of it, in every state and in every mode.
    @Test
    func everyExplicitIdentityIsUniqueInEveryState() throws {
        let states = [
            off(), off(nextTarget: .indefinite), off(nextTarget: .until(minuteOfDay: 18 * 60)),
            timed(), indefinite(), PluginCaffeinateState(failure: .assertionRefused(-1)),
        ]

        for state in states {
            let document = try #require(widget(try send(state, to: plugin()))?.document)
            let all      = ids(document.root) + ids(try #require(document.optionsRoot))

            #expect(Set(all).count == all.count, "\(all)")
            #expect(Set(all).isSuperset(of: ["options.page", "mode.duration", "mode.until", "mode.indefinite", "display", "power.options"]))
        }
    }

    // MARK: - The selector

    private func selectedSegments(_ state: PluginCaffeinateState) throws -> [String] {
        let root = try optionsRoot(state)

        return ["mode.duration", "mode.until", "mode.indefinite"].filter { id in
            guard let segment = find(id, in: root) else { return false }

            return !segment.layers.isEmpty || segment.children.contains { !$0.layers.isEmpty }
        }
    }

    @Test
    func theSelectorFillsTheSegmentOfTheTarget() throws {
        #expect(try selectedSegments(off(nextTarget: .indefinite)) == ["mode.indefinite"])
        #expect(try selectedSegments(off(nextTarget: .duration(minutes: 90))) == ["mode.duration"])
        #expect(try selectedSegments(off(nextTarget: .until(minuteOfDay: 18 * 60))) == ["mode.until"])
    }

    /// While a session runs the selector shows the session: indefinite is the sign, a timed one
    /// is For or Until by the kind it was last given, and For when it was given neither.
    @Test
    func aRunningSessionSelectsItsOwnMode() throws {
        #expect(try selectedSegments(indefinite()) == ["mode.indefinite"])
        #expect(try selectedSegments(timed()) == ["mode.duration"])

        let until = PluginCaffeinateState(
            startedAt        : Self.started,
            endsAt           : Date(timeIntervalSince1970: Self.sixPM),
            activityStartedAt: Self.started,
            nextTarget       : .until(minuteOfDay: 18 * 60)
        )
        #expect(try selectedSegments(until) == ["mode.until"])

        let counted = PluginCaffeinateState(
            startedAt        : Self.started,
            endsAt           : Self.now.addingTimeInterval(3_600),
            activityStartedAt: Self.started,
            nextTarget       : .duration(minutes: 60)
        )
        #expect(try selectedSegments(counted) == ["mode.duration"])
    }

    @Test
    func theSegmentsSpeakTheirNameAndWhichOneIsSelected() throws {
        func labels(_ state: PluginCaffeinateState) throws -> [String] {
            let root = try optionsRoot(state)

            return try ["mode.duration", "mode.until", "mode.indefinite"].map { id in
                let segment = try #require(find(id, in: root))

                return try #require(segment.modifiers.compactMap { modifier -> String? in
                    if case .accessibilityLabel(let label) = modifier { label } else { nil }
                }.first)
            }
        }

        #expect(try labels(off(nextTarget: .duration(minutes: 90))) == ["For, selected", "Until", "Until you stop it"])
        #expect(try labels(off(nextTarget: .until(minuteOfDay: 0))) == ["For", "Until, selected", "Until you stop it"])
        #expect(try labels(off(nextTarget: .indefinite)) == ["For", "Until", "Until you stop it, selected"])
    }

    // MARK: - The ruler

    private func rulerKind(_ state: PluginCaffeinateState) throws -> PluginNodeKind? {
        try ruler(state)?.kind
    }

    private func durationRuler(_ minutes: Double) -> PluginNodeKind {
        .slider(
            value  : minutes,
            minimum: 15,
            maximum: 1_440,
            step   : 15,
            style  : .ruler(labelEvery: 4, labels: .duration),
            action : "caffeinate.duration.set"
        )
    }

    private func clockRuler(
        _ value: Double,
        from lower: Double = CaffeinatePluginTests.rangeStart,
        to upper  : Double = CaffeinatePluginTests.rangeEnd
    ) -> PluginNodeKind {
        .slider(
            value  : value,
            minimum: lower,
            maximum: upper,
            step   : 900,
            style  : .ruler(labelEvery: 4, labels: .clockTime),
            action : "caffeinate.until.set"
        )
    }

    @Test
    func offForRulesTheNextDurationOnTheMinuteScale() throws {
        #expect(try rulerKind(off(nextTarget: .duration(minutes: 90))) == durationRuler(90))
        #expect(try rulerKind(off(nextTarget: .duration(minutes: 15))) == durationRuler(15))
        #expect(try rulerKind(off(nextTarget: .duration(minutes: 1_440))) == durationRuler(1_440))
    }

    /// offUntil: the value is the next occurrence of the minute of the day that is 15 minutes
    /// ahead or more, as the service resolves it, and the range is the quarter hours from 15
    /// minutes ahead to a day ahead.
    @Test
    func offUntilRulesTheNextOccurrenceOnTheClockScale() throws {
        #expect(try rulerKind(off(nextTarget: .until(minuteOfDay: 18 * 60))) == clockRuler(Self.sixPM))

        // The edges of the range are on the ruler.
        #expect(try rulerKind(off(nextTarget: .until(minuteOfDay: 4 * 60))) == clockRuler(Self.rangeStart))
        #expect(try rulerKind(off(nextTarget: .until(minuteOfDay: 3 * 60 + 30))) == clockRuler(Self.rangeEnd))

        // 03:45 is twelve minutes ahead and tomorrow's is more than a day away, so the end a
        // start would get is today's, before the range starts: the range grows to hold it.
        #expect(try rulerKind(off(nextTarget: .until(minuteOfDay: 3 * 60 + 45))) == clockRuler(2_000_000_700, from: 2_000_000_700))
    }

    @Test
    func aRunningDurationRulesTheMinutesLeftRoundedUpToAQuarter() throws {
        #expect(try rulerKind(timed(minutesLeft: 24)) == durationRuler(30))
        #expect(try rulerKind(timed(minutesLeft: 30)) == durationRuler(30))
        #expect(try rulerKind(timed(minutesLeft: 30.5)) == durationRuler(45))
        #expect(try rulerKind(timed(minutesLeft: 2)) == durationRuler(15))
        #expect(try rulerKind(timed(minutesLeft: 0)) == durationRuler(15))
        #expect(try rulerKind(timed(minutesLeft: 1_440)) == durationRuler(1_440))
        #expect(try rulerKind(timed(minutesLeft: 1_500)) == durationRuler(1_440))
    }

    @Test
    func aRunningUntilRulesTheSessionsEnd() throws {
        func until(_ end: Double) -> PluginCaffeinateState {
            PluginCaffeinateState(
                startedAt        : Self.started,
                endsAt           : Date(timeIntervalSince1970: end),
                activityStartedAt: Self.started,
                nextTarget       : .until(minuteOfDay: 18 * 60)
            )
        }

        #expect(try rulerKind(until(Self.sixPM)) == clockRuler(Self.sixPM))

        // An end closer than the range starts, or off the quarter, stays on the ruler: the
        // range grows to hold it, and the end is the nearest quarter hour.
        #expect(try rulerKind(until(Self.now.timeIntervalSince1970 + 900)) == clockRuler(2_000_000_700, from: 2_000_000_700))
        #expect(try rulerKind(until(Self.sixPM + 100)) == clockRuler(Self.sixPM))
        #expect(try rulerKind(until(Self.rangeEnd + 3_000)) == clockRuler(Self.rangeEnd + 2_700, to: Self.rangeEnd + 2_700))
    }

    @Test
    func infinityHidesTheRulerAndSaysUntilYouStopIt() throws {
        for state in [off(nextTarget: .indefinite), indefinite()] {
            let root = try optionsRoot(state)

            #expect(find("ruler", in: root) == nil)
            #expect(!kinds(root).contains { if case .slider = $0 { true } else { false } })
            #expect(kinds(root).contains(.text("Until you stop it")))
        }

        #expect(!kinds(try optionsRoot(off())).contains(.text("Until you stop it")))
    }

    @Test
    func theRulerIsAmberAndFillsTheWidth() throws {
        let node = try #require(try ruler(off()))

        #expect(node.modifiers.contains(.foregroundStyle(.color(Self.amber))))
        #expect(node.modifiers.contains { modifier in
            if case .frame(_, let height?, .infinity?, _, _) = modifier { height > 30 } else { false }
        })
    }

    @Test
    func aRulerNeverGoesOutsideItsRange() throws {
        let states = [
            off(nextTarget: .until(minuteOfDay: 0)), off(nextTarget: .until(minuteOfDay: 1_425)),
            off(nextTarget: .duration(minutes: 15)), timed(minutesLeft: -5), timed(minutesLeft: 1_439),
        ]

        for state in states {
            // The document validates its sliders, so building it is the check.
            #expect(throws: Never.self) { _ = try send(state, to: plugin()) }
        }
    }

    @Test
    func theWidgetOffersA2x2FaceFirstAndThe2x1And1x1FacesAfterIt() throws {
        let face = try #require(widget(try send(timed(), to: plugin()))?.document?.root)

        #expect(face.kind == .viewThatFits(axes: .vertical))
        try #require(face.children.count == 2)

        let medium = face.children[0]
        let rest   = face.children[1]
        #expect(rest.kind == .viewThatFits(axes: .horizontal))
        #expect(rest.children.count == 2)

        let mediumEntries = PluginNodeTable(try PluginDocument(root: medium)).entries
        #expect(mediumEntries.contains { $0.id.rawValue == "#power.medium:toggle" && $0.kind == .toggle(isOn: true, action: "caffeinate.stop") })
        #expect(mediumEntries.contains { $0.id.rawValue == "#options:button" && $0.kind == .button(action: "caffeinate.options") })
        #expect(texts(mediumEntries).contains("Caffeinate"))
        #expect(!mediumEntries.contains { $0.id.rawValue == "#power.large:toggle" })
        #expect(!kinds(rest.children[1]).contains(.text("Caffeinate")))
    }

    @Test
    func the2x2FaceSaysErrorOnARefusedStartAndKeepsTheSessionOnARefusedExtension() throws {
        let refused = PluginCaffeinateState(failure: .assertionRefused(-5))
        let medium  = try #require(widget(try send(refused, to: plugin()))?.document?.root.children.first)
        let entries = PluginNodeTable(try PluginDocument(root: medium)).entries
        #expect(texts(entries).contains("Error"))
        #expect(symbols(entries).contains("exclamationmark.triangle.fill"))

        let extension_ = PluginCaffeinateState(
            startedAt        : Self.started,
            endsAt           : Self.now.addingTimeInterval(1_440),
            activityStartedAt: Self.started,
            failure          : .extensionRefused(5)
        )
        let running = try #require(widget(try send(extension_, to: plugin()))?.document?.root.children.first)
        let ends    = try #require(extension_.endsAt)
        #expect(kinds(running).contains(.countdown(end: ends, style: .compact)))
        #expect(PluginNodeTable(try PluginDocument(root: running)).entries.contains { $0.kind == .symbol(name: "exclamationmark.triangle.fill") })
        #expect(!kinds(running).contains(.text("Error")))
    }

    @Test
    func activityAttributesCarryTheRenewedStart() throws {
        let renewed = Self.now.addingTimeInterval(-30)
        let state   = PluginCaffeinateState(
            startedAt        : Self.started,
            endsAt           : Self.now.addingTimeInterval(1_440),
            activityStartedAt: renewed
        )
        let attributes = try #require(activity(try send(state, to: plugin()))?.activity)
        #expect(attributes.startedAt == renewed)
        #expect(attributes.relevance == 0.3)

        let fallback = PluginCaffeinateState(startedAt: Self.started, endsAt: Self.now.addingTimeInterval(1_440))
        let fallbackAttributes = try #require(activity(try send(fallback, to: plugin()))?.activity)
        #expect(fallbackAttributes.startedAt == Self.started)
    }

    @Test
    func theActivityLabelSaysUntilWhenOrUntilYouStopIt() throws {
        let state = timed()
        let ends  = try #require(state.endsAt)
        let clock = ends.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .current))

        let timedLabel = try #require(activity(try send(state, to: plugin()))?.activity?.accessibilityLabel)
        #expect(timedLabel.contains(clock))
        #expect(timedLabel.hasPrefix("Caffeinate"))

        let openLabel = try #require(activity(try send(indefinite(), to: plugin()))?.activity?.accessibilityLabel)
        #expect(openLabel == "Caffeinate, awake until you stop it")
    }

    // MARK: - Widget and options page

    @Test
    func controlsKeepStableIdentitiesAcrossStates() throws {
        func widgetControls(_ state: PluginCaffeinateState) throws -> Set<PluginNodeID> {
            controls(try nodes(widget(try send(state, to: plugin()))))
        }

        let idle = try widgetControls(off())

        #expect(idle == (try widgetControls(timed())))
        #expect(idle == (try widgetControls(indefinite())))
        #expect(idle == (try widgetControls(PluginCaffeinateState(failure: .assertionRefused(-1)))))
        for id in ["power.medium", "power.large", "power.small", "power.options"] {
            #expect(idle.contains(PluginNodeID(rawValue: "#\(id):toggle")))
        }
        for id in ["options", "options.large"] {
            #expect(idle.contains(PluginNodeID(rawValue: "#\(id):button")))
        }
        #expect(idle.contains(PluginNodeID(rawValue: "#display:toggle")))

        #expect(controls(try nodes(activity(try send(timed(), to: plugin())))).isEmpty)
    }

    @Test
    func theDiscIsTheSwitchWhateverTheSession() throws {
        let plugin = plugin()

        let idle = try nodes(widget(try send(off(), to: plugin)))
        #expect(idle.filter { $0.kind == .toggle(isOn: false, action: "caffeinate.start") }.count == 4)
        #expect(idle.contains { $0.kind == .button(action: "caffeinate.options") })

        let running = try nodes(widget(try send(timed(), to: plugin)))
        #expect(running.filter { $0.kind == .toggle(isOn: true, action: "caffeinate.stop") }.count == 4)
        #expect(running.contains { $0.kind == .toggle(isOn: true, action: "caffeinate.display") })
    }

    @Test
    func glyphFollowsThePreference() throws {
        let plugin = plugin()

        let outline = symbols(try nodes(widget(try send(PluginCaffeinateState(glyph: .mug), to: plugin))))
        #expect(outline.contains("mug"))
        #expect(!outline.contains("mug.fill"))

        let filled = symbols(try nodes(widget(try send(timed(glyph: .pill), to: plugin))))
        #expect(filled.contains("pill.fill"))
        #expect(!filled.contains("pill"))

        let glyphs = try nodes(widget(try send(PluginCaffeinateState(glyph: .cupHeatWaves), to: self.plugin())))
            .filter { if case .symbol("cup.and.heat.waves") = $0.kind { true } else { false } }
        #expect(!glyphs.isEmpty)
        #expect(glyphs.allSatisfy { $0.modifiers.contains(.contentTransition(.symbolEffect)) })
    }

    /// The widget's second line follows the target: the sign, the length, or "until" and the
    /// kernel's clock, each with the chevron that says the text opens more.
    @Test
    func theWidgetStatusLineFollowsTheTarget() throws {
        let sixPM = Date(timeIntervalSince1970: Self.sixPM)

        func face(_ target: CaffeinateTarget) throws -> PluginNode {
            try #require(widget(try send(off(nextTarget: target), to: plugin()))?.document?.root)
        }

        // The faces only: the options page has a ∞ and a clock of its own.
        let infinite = kinds(try face(.indefinite))
        #expect(infinite.contains(.text("∞")))
        #expect(!infinite.contains(.date(sixPM, style: .time)))

        let duration = kinds(try face(.duration(minutes: 90)))
        #expect(duration.contains(.text("1h 30m")))
        #expect(!duration.contains(.text("∞")))

        let until = kinds(try face(.until(minuteOfDay: 18 * 60)))
        #expect(until.contains(.text("until")))
        #expect(until.contains(.date(sixPM, style: .time)))
        #expect(until.contains(.symbol(name: "chevron.right")))
        #expect(!until.contains(.text("∞")))

        // Both the 2x2 and the 2x1 face say it, the 1x1 face has no line.
        let root = try face(.until(minuteOfDay: 18 * 60))
        let rest = root.children[1]
        for node in [root.children[0], rest.children[0]] {
            #expect(kinds(node).contains(.date(sixPM, style: .time)))
            #expect(kinds(node).contains(.text("until")))
        }
        #expect(!kinds(rest.children[1]).contains(.text("until")))
    }

    @Test
    func aRunningWidgetTicksWithTheKernelsCountdownAndTimer() throws {
        let state   = timed(minutesLeft: 24)
        let ends    = try #require(state.endsAt)
        let entries = try nodes(widget(try send(state, to: plugin())))

        #expect(entries.contains { $0.kind == .countdown(end: ends, style: .compact) })
        #expect(entries.contains { $0.kind == .timer(start: Self.started, end: ends, countsDown: true) })
    }

    @Test
    func aRefusedStartSaysErrorOnTheTileAndGivesTheSentenceAndCodeOnTheOptionsPage() throws {
        let state   = PluginCaffeinateState(failure: .assertionRefused(-536_870_212))
        let entries = try nodes(widget(try send(state, to: plugin())))
        let page    = texts(entries)

        #expect(page.contains("Error"))
        #expect(page.contains("Couldn't prevent sleep (error -536870212)"))
        #expect(!page.contains("Couldn't prevent sleep"))
        #expect(symbols(entries).contains("exclamationmark.triangle.fill"))
    }

    @Test
    func aRefusedExtensionKeepsTheRunningPresentationAndAddsTheWarning() throws {
        let state   = PluginCaffeinateState(
            startedAt        : Self.started,
            endsAt           : Self.now.addingTimeInterval(1_440),
            activityStartedAt: Self.started,
            failure          : .extensionRefused(5)
        )
        let ends    = try #require(state.endsAt)
        let entries = try nodes(widget(try send(state, to: plugin())))
        let page    = texts(entries)

        #expect(entries.contains { $0.kind == .countdown(end: ends, style: .compact) })
        #expect(entries.contains { $0.kind == .timer(start: Self.started, end: ends, countsDown: true) })
        #expect(!entries.contains { $0.kind == .date(ends, style: .time) })
        #expect(page.contains("Couldn't change the time (error 5)"))
        #expect(!page.contains("Error"))
        #expect(!page.contains { $0.hasPrefix("Couldn't prevent sleep") })
        #expect(symbols(entries).contains("exclamationmark.triangle.fill"))
    }

    /// A running page has no caption: the time is the kernel's countdown, and an Until
    /// session's end is the ruler's own value, so the page draws no second clock.
    @Test
    func aRunningPageCountsDownWithTheKernelAndDrawsNoCaption() throws {
        let state   = timed()
        let ends    = try #require(state.endsAt)
        let entries = try nodes(optionsPublication(state))

        #expect(entries.contains { $0.kind == .timer(start: Self.started, end: ends, countsDown: true) })
        #expect(!entries.contains { $0.kind == .date(ends, style: .time) })
        #expect(!texts(entries).contains("until"))
    }

    @Test
    func everyControlActionIsDeclared() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == CaffeinatePlugin.id })
        let feature  = try #require(manifest.features.first)
        let states   = [
            off(), timed(), indefinite(), PluginCaffeinateState(failure: .extensionRefused(5)),
            off(nextTarget: .indefinite), off(nextTarget: .until(minuteOfDay: 18 * 60)),
        ]

        #expect(feature.supportsFullscreen)
        #expect(feature.sources == [PluginCaffeinateState.source])
        #expect(feature.permissions == ["power.keepAwake"])
        #expect(feature.surfaces.widget != nil)
        #expect(feature.surfaces.activity != nil)

        for state in states {
            let output = try send(state, to: plugin())

            for publication in output.publications where publication.document != nil {
                for entry in try nodes(publication) {
                    switch entry.kind {
                        case .button(let action), .toggle(_, let action), .slider(_, _, _, _, _, let action):
                            #expect(feature.actions.contains(action))

                        default:
                            break
                    }
                }
            }
        }
    }
}

/// CaffeinateStringsTests checks the words of the options page in both languages the app ships:
/// every phrase the faces use is in the catalog, translated, and keeps the placeholders of its
/// English form.
@Suite
struct CaffeinateStringsTests {

    /// The phrases the selector, the ruler's empty state and the status line speak, with the
    /// translation Italian users read.
    private static let italian: [(english: String, italian: String)] = [
        ("For", "Per"),
        ("Until", "Fino a"),
        ("Until you stop it", "Finché non lo fermi"),
        ("until", "fino alle"),
        ("%@, selected", "%@, selezionato"),
    ]

    private func catalog() throws -> [String: [String: Any]] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        url.append(path: "Sources/CascadePlugins/Resources/CaffeinateWidget.xcstrings")

        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])

        return try #require(root["strings"] as? [String: [String: Any]])
    }

    private func translation(
        of key: String,
        in catalog: [String: [String: Any]]
    ) -> String? {
        let localizations = catalog[key]?["localizations"] as? [String: [String: Any]]
        let unit          = localizations?["it"]?["stringUnit"] as? [String: String]

        return unit?["state"] == "translated" ? unit?["value"] : nil
    }

    @Test
    func theRulerPagesPhrasesAreTranslatedIntoItalian() throws {
        let catalog = try catalog()

        for (english, italian) in Self.italian {
            #expect(translation(of: english, in: catalog) == italian, "\(english)")
        }
    }

    @Test
    func everyPhraseOfTheCatalogIsTranslatedAndKeepsItsPlaceholders() throws {
        let catalog = try catalog()

        for key in catalog.keys {
            let italian = try #require(translation(of: key, in: catalog), "\(key) has no Italian")

            #expect(italian.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count, "\(key)")
        }
    }

    @Test
    func theCompiledBundleSpeaksBothLanguages() throws {
        let path = try #require(Bundle.module.path(forResource: "it", ofType: "lproj"))
        let it   = try #require(Bundle(path: path))

        #expect(it.localizedString(forKey: "For", value: nil, table: "CaffeinateWidget") == "Per")
        #expect(it.localizedString(forKey: "Until you stop it", value: nil, table: "CaffeinateWidget") == "Finché non lo fermi")
        #expect(Bundle.module.localizedString(forKey: "For", value: "For", table: "CaffeinateWidget") == "For")
    }
}
