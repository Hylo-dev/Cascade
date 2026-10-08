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

    private func plugin() -> CaffeinatePlugin {
        CaffeinatePlugin(now: { Self.now })
    }

    private func off(nextDuration: CaffeinateDuration = .minutes(90)) -> PluginCaffeinateState {
        PluginCaffeinateState(nextDuration: nextDuration)
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
            nextDuration     : .indefinite
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

        let again = try send(off(nextDuration: .minutes(30)), to: plugin)
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
        #expect(activity(try send(off(nextDuration: .minutes(30)), to: plugin)) == nil)
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
        #expect(texts(options).contains("active for"))
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

    /// anIndefiniteCountUpRunsPastADay keeps "active for" counting after 24 hours: the 2x2 and
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
        let output  = try send(off(nextDuration: .minutes(90)), to: plugin())
        let options = try #require(widget(output)?.document?.optionsRoot)
        let entries = try nodes(PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .widget,
            document: PluginDocument(root: options)
        ))
        let time    = try #require(entries.first { $0.kind == .text("1h 30m") })

        #expect(time.modifiers.contains(.font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())))
        #expect(time.modifiers.contains(.foregroundStyle(.color(.white))))
        #expect(texts(entries).contains("Next session"))
        #expect(!texts(entries).contains("until"))
    }

    /// theOptionsPageIsOneRowOfTwoRoundButtonsAndAStepper checks the Timer-style layout by what
    /// it contains: Start/Stop and Display captions, the two switches, − and +, and no ＋15m.
    @Test
    func theOptionsPageIsOneRowOfTwoRoundButtonsAndAStepper() throws {
        func optionsEntries(_ state: PluginCaffeinateState) throws -> [PluginNodeTable.Entry] {
            let output = try send(state, to: plugin())

            return try nodes(PluginPublication(
                feature : CaffeinatePlugin.feature,
                surface : .widget,
                document: PluginDocument(root: try #require(widget(output)?.document?.optionsRoot))
            ))
        }

        let idle = try optionsEntries(off())
        #expect(idle.contains { $0.id.rawValue == "#power.options:toggle" && $0.kind == .toggle(isOn: false, action: "caffeinate.start") })
        #expect(idle.contains { $0.id.rawValue == "#display:toggle" && $0.kind == .toggle(isOn: true, action: "caffeinate.display") })
        #expect(idle.contains { $0.id.rawValue == "#duration.down:button" })
        #expect(idle.contains { $0.id.rawValue == "#duration.up:button" })
        #expect(symbols(idle).isSuperset(of: ["play.fill", "stop.fill", "display", "moon.zzz"]))
        #expect(Set(texts(idle)).isSuperset(of: ["Start", "Stop", "Display"]))
        #expect(!idle.contains { $0.kind == .button(action: "caffeinate.extend") })

        let running = try optionsEntries(timed())
        #expect(running.contains { $0.id.rawValue == "#power.options:toggle" && $0.kind == .toggle(isOn: true, action: "caffeinate.stop") })
        #expect(!running.contains { $0.kind == .button(action: "caffeinate.extend") })
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
        for id in ["duration.down", "duration.up", "options", "options.large"] {
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

    @Test
    func theStepperShowsTheNextDurationWhileOffAndDimsAtTheLimits() throws {
        func dimmed(
            _ state: PluginCaffeinateState,
            _ action: String
        ) throws -> Bool {
            let entries = try nodes(widget(try send(state, to: plugin())))
            let button  = try #require(entries.first { $0.kind == .button(action: action) })

            return button.modifiers.contains(.opacity(0.35))
        }

        let middle = try nodes(widget(try send(off(nextDuration: .minutes(90)), to: plugin())))
        #expect(texts(middle).contains("1h 30m"))
        #expect(try dimmed(off(nextDuration: .minutes(90)), "caffeinate.duration.down") == false)
        #expect(try dimmed(off(nextDuration: .minutes(90)), "caffeinate.duration.up") == false)

        let infinite = try nodes(widget(try send(off(nextDuration: .indefinite), to: plugin())))
        #expect(texts(infinite).contains("∞"))
        #expect(try dimmed(off(nextDuration: .indefinite), "caffeinate.duration.down"))
        #expect(try dimmed(off(nextDuration: .minutes(1_440)), "caffeinate.duration.up"))

        #expect(try dimmed(indefinite(), "caffeinate.duration.down"))
        #expect(try dimmed(indefinite(), "caffeinate.duration.up") == false)
        #expect(try dimmed(timed(minutesLeft: 1_430), "caffeinate.duration.up"))
        #expect(try dimmed(timed(minutesLeft: 60), "caffeinate.duration.up") == false)
    }

    @Test
    func aRunningWidgetTicksWithTheKernelsCountdownAndTimer() throws {
        let state   = timed(minutesLeft: 24)
        let ends    = try #require(state.endsAt)
        let entries = try nodes(widget(try send(state, to: plugin())))

        #expect(entries.contains { $0.kind == .countdown(end: ends, style: .compact) })
        #expect(entries.contains { $0.kind == .timer(start: Self.started, end: ends, countsDown: true) })
        #expect(entries.contains { $0.kind == .date(ends, style: .time) })
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
        #expect(page.contains("Couldn't extend (error 5)"))
        #expect(!page.contains("Error"))
        #expect(!page.contains { $0.hasPrefix("Couldn't prevent sleep") })
        #expect(symbols(entries).contains("exclamationmark.triangle.fill"))
    }

    @Test
    func theOptionsPageDrawsTheEndTimeWithTheKernel() throws {
        let state   = timed()
        let ends    = try #require(state.endsAt)
        let entries = try nodes(widget(try send(state, to: plugin())))

        #expect(texts(entries).contains("until"))
        #expect(entries.filter { $0.kind == .date(ends, style: .time) }.count == 1)
    }

    @Test
    func everyControlActionIsDeclared() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == CaffeinatePlugin.id })
        let feature  = try #require(manifest.features.first)
        let states   = [off(), timed(), indefinite(), PluginCaffeinateState(failure: .extensionRefused(5))]

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
                        case .button(let action), .toggle(_, let action):
                            #expect(feature.actions.contains(action))

                        default:
                            break
                    }
                }
            }
        }
    }
}
