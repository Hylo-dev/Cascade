//
//  PluginDocumentTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginDocumentTests {

    @Test
    func optionsControlsShareTheDocumentBudgetAndAuthorizationTable() throws {
        let json = #"{"schema":2,"root":{"kind":{"button":{"action":"open"}},"id":"open"},"optionsAction":"open","optionsRoot":{"kind":{"button":{"action":"stop"}},"id":"stop"}}"#
        let document = try PluginDocument.decode(Data(json.utf8))
        #expect(PluginNodeTable(document).entries.contains { $0.id.rawValue == "#stop:button" })
        let duplicate = json.replacingOccurrences(of: #""id":"stop""#, with: #""id":"open""#)
        #expect(throws: AddonFailure.self) { try PluginDocument.decode(Data(duplicate.utf8)) }
    }

    @Test
    func optionsCannotExceedTheAggregateNodeOrWireBudgetOrInventAnOpener() throws {
        let full = PluginNodeFixtures.stack(of: PluginDocument.maximumNodes - 1)
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: full, optionsRoot: PluginNode(.text("One more")))
        }
        let large = PluginNode(.vStack(alignment: .leading, spacing: nil), children: Array(repeating: PluginNode(.text(String(repeating: "a", count: 4_000))), count: 17))
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: PluginNode(.text("Widget")), optionsRoot: large)
        }
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: PluginNode(.text("Widget")), optionsRoot: PluginNode(.text("Options")), optionsAction: "missing")
        }
    }

    @Test
    func legacyFeaturesDoNotAcquireFullscreenPermission() throws {
        let base = #"{"id":"test","surfaces":{"widget":{"sizes":["1x1"]}}}"#
        let legacy = try JSONDecoder().decode(PluginFeature.self, from: Data(base.utf8))
        let explicit = try JSONDecoder().decode(PluginFeature.self, from: Data(base.dropLast().appending(",\"supportsFullscreen\":false}").utf8))
        #expect(legacy == explicit)
        #expect(!String(decoding: try JSONEncoder().encode(legacy), as: UTF8.self).contains("supportsFullscreen"))
        let enabled = try JSONDecoder().decode(PluginFeature.self, from: Data(base.dropLast().appending(",\"supportsFullscreen\":true}").utf8))
        #expect(enabled != legacy)
    }

    @Test
    func roundTripsTheClockAndTheMusicRow() throws {
        for root in [PluginNodeFixtures.clock(), PluginNodeFixtures.musicRow()] {
            let document = try PluginDocument(root: root)
            let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

            #expect(decoded == document)
        }
    }

    @Test
    func roundTripsACountdown() throws {
        let end      = Date(timeIntervalSince1970: 1_800_000_000)
        let document = try PluginDocument(root: PluginNode(.countdown(end: end, style: .compact)))
        let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

        #expect(decoded == document)
    }

    @Test
    func leavesUndeclaredNodeListsEmpty() throws {
        let json = #"{"schema":2,"root":{"kind":{"spacer":{}}}}"#
        let root = try PluginDocument.decode(Data(json.utf8)).root

        #expect(root.modifiers.isEmpty && root.children.isEmpty && root.layers.isEmpty && root.id == nil)
    }

    @Test(arguments: [
        #"{"schema":2,"root":{"kind":{"marquee":{"_0":"x"}}}}"#,
        #"{"schema":2,"root":{"kind":{"spacer":{}},"modifiers":[{"blur":{"_0":2}}]}}"#,
        #"{"schema":2,"root":{"kind":{"spacer":{}},"style":"plain"}}"#,
        #"{"schema":1,"root":{"kind":{"spacer":{}}}}"#,
    ])
    func rejectsUnknownNodesModifiersFieldsAndSchemas(_ json: String) {
        #expect(throws: (any Error).self) { try PluginDocument.decode(Data(json.utf8)) }
    }

    @Test
    func rejectsOversizedDataBeforeDecoding() {
        let data = Data(repeating: 32, count: PluginDocument.maximumBytes + 1)

        #expect(throws: AddonFailure.self) { try PluginDocument.decode(data) }
    }

    @Test
    func acceptsTheNodeBudgetExactlyAndRejectsOneMore() throws {
        let largest = PluginNodeFixtures.stack(of: PluginDocument.maximumNodes - 1)
        let tooMany = PluginNodeFixtures.stack(of: PluginDocument.maximumNodes)

        #expect(throws: Never.self) { try PluginDocument(root: largest) }
        #expect(throws: AddonFailure.self) { try PluginDocument(root: tooMany) }
    }

    @Test
    func layersCountTowardTheNodeBudget() throws {
        let full    = PluginNodeFixtures.stack(of: PluginDocument.maximumNodes - 1)
        let layered = PluginNode(full.kind, modifiers: [.overlay(alignment: .center)], children: full.children, layers: [PluginNode(.text("badge"))])

        #expect(throws: AddonFailure.self) { try PluginDocument(root: layered) }
    }

    @Test
    func acceptsTheDepthLimitExactlyAndRejectsOneMore() throws {
        #expect(throws: Never.self) { try PluginDocument(root: PluginNodeFixtures.nested(depth: PluginDocument.maximumDepth)) }
        #expect(throws: AddonFailure.self) { try PluginDocument(root: PluginNodeFixtures.nested(depth: PluginDocument.maximumDepth + 1)) }
    }

    @Test
    func rejectsDocumentsPastSixtyFourKibibytes() {
        let text = String(repeating: "a", count: 4_000)
        let root = PluginNode(.vStack(alignment: .center, spacing: nil), children: Array(repeating: PluginNode(.text(text)), count: 17))

        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test
    func rejectsDuplicateExplicitIDs() {
        let root = PluginNode(
            .hStack(alignment: .center, spacing: nil),
            children: [PluginNode(.text("a"), id: "title"), PluginNode(.text("b"), id: "title")]
        )

        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test(arguments: [
        PluginNode(.text("leaf"), children: [PluginNode(.text("child"))]),
        PluginNode(.spacer(minLength: nil), modifiers: [.overlay(alignment: .center)]),
        PluginNode(.spacer(minLength: nil), layers: [PluginNode(.text("orphan"))]),
    ])
    func rejectsStructureThatCannotRender(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test(arguments: [
        PluginNode(.spacer(minLength: nil), modifiers: [.opacity(.nan)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.frame(width: .infinity, height: nil, maxWidth: nil, maxHeight: nil, alignment: .center)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.frame(width: nil, height: nil, maxWidth: .points(.nan), maxHeight: nil, alignment: .center)]),
        PluginNode(.date(Date(timeIntervalSinceReferenceDate: .infinity), style: .time)),
        PluginNode(.progress(value: .nan, total: 1, style: .linear)),
        PluginNode(.spacer(minLength: nil), modifiers: [.foregroundStyle(.color(PluginColor(red: .infinity, green: 0, blue: 0)))]),
    ])
    func rejectsNonFiniteNumbers(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test(arguments: [
        PluginNode(.progress(value: 2, total: 1, style: .circular)),
        PluginNode(.slider(value: 5, minimum: 0, maximum: 1, step: nil, action: "volume")),
        PluginNode(.slider(value: 0.5, minimum: 0, maximum: 1, step: 0, action: "volume")),
        PluginNode(.timer(start: PluginNodeFixtures.now, end: PluginNodeFixtures.now - 1, countsDown: true)),
        PluginNode(.spacer(minLength: nil), modifiers: [.opacity(1.5)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.lineLimit(0)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.minimumScaleFactor(0)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.padding(.all, length: -1)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.transition(.move(.horizontal))]),
        PluginNode(.spacer(minLength: nil), modifiers: [.foregroundStyle(.gradient([.white]))]),
        PluginNode(.text("x"), modifiers: [.font(PluginFont(style: .body, size: 12))]),
        PluginNode(.text("x"), modifiers: [.font(PluginFont())]),
        PluginNode(.shape(.roundedRectangle(cornerRadius: -2))),
    ])
    func rejectsValuesOutOfRange(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test(arguments: [
        PluginNode(.button(action: "skip forward")),
        PluginNode(.symbol(name: "")),
        PluginNode(.asset(id: "art work")),
        PluginNode(.text("x"), id: "has space"),
        PluginNode(.component(id: "audio.spectrum", version: 0, parameters: [:])),
        PluginNode(.component(id: "audio.spectrum", version: 1, parameters: ["bad key": .bool(true)])),
    ])
    func rejectsMalformedIdentifiers(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test
    func rejectsMoreGlassLightsThanTheRendererDraws() throws {
        let light  = try GlassLight(x: 0.5, y: 0.5, radius: 0.2, red: 1, green: 1, blue: 1, intensity: 0.5)
        let lights = Array(repeating: light, count: GlassLight.maximumCount + 1)

        #expect(throws: AddonFailure.self) { try PluginDocument(root: PluginNodeFixtures.clock(), glassLights: lights) }
    }

    @Test
    func listsTheComponentsADocumentShows() throws {
        let root = PluginNode(
            .vStack(alignment: .center, spacing: nil),
            children: [
                PluginNode(.component(id: "audio.spectrum", version: 1, parameters: ["bars": .number(12)])),
                PluginNode(.text("x"), layers: []),
            ],
            layers: []
        )
        let document = try PluginDocument(root: root)
        let spectrum = try PluginComponentReference(id: "audio.spectrum", version: 1)

        #expect(document.componentReferences == [spectrum])
    }

    @Test
    func rejectsADeepDocumentWhileDecodingWithoutExhaustingTheStack() {
        let levels = 200
        let node   = String(repeating: #"{"kind":{"vStack":{"alignment":"center"}},"children":["#, count: levels)
            + #"{"kind":{"spacer":{}}}"#
            + String(repeating: "]}", count: levels)
        let data   = Data((#"{"schema":2,"root":"# + node + "}").utf8)

        let rejected = onSmallStack {
            do {
                _ = try PluginDocument.decode(data)
                return false
            } catch {
                return error is AddonFailure
            }
        }

        #expect(rejected)
    }

    @Test
    func rejectsInProcessDocumentsThatWouldNotFitOnTheWire() {
        let modified = PluginNode(
            .vStack(alignment: .center, spacing: nil),
            children: (0..<200).map { index in
                PluginNode(
                    .text("\(index)"),
                    modifiers: [
                        .font(PluginFont(style: .subheadline, weight: .ultraLight, design: .monospaced, monospacedDigit: true)),
                        .frame(width: 1.2345678901234567, height: 2.345678901234567, maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing),
                        .foregroundStyle(.gradient([.white, .black, .white, .black])),
                        .padding(.horizontal, length: 3.456789012345678),
                    ]
                )
            }
        )
        let quoted   = PluginNode(
            .vStack(alignment: .center, spacing: nil),
            children: Array(repeating: PluginNode(.text(String(repeating: "\"", count: 4_000))), count: 12)
        )

        #expect(throws: AddonFailure.self) { try PluginDocument(root: modified) }
        #expect(throws: AddonFailure.self) { try PluginDocument(root: quoted) }
    }

    @Test
    func acceptsSixteenModifiersOnANodeAndRejectsSeventeen() {
        let sixteen   = PluginNode(.spacer(minLength: nil), modifiers: Array(repeating: .opacity(1), count: 16))
        let seventeen = PluginNode(.spacer(minLength: nil), modifiers: Array(repeating: .opacity(1), count: 17))

        #expect(throws: Never.self) { try PluginDocument(root: sixteen) }
        #expect(throws: AddonFailure.self) { try PluginDocument(root: seventeen) }
    }

    @Test
    func aClockNodeRoundTripsAndValidates() throws {
        let document = try PluginDocument(root: PluginNode(.clock))
        let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

        #expect(decoded == document)
        #expect(decoded.root.kind.name == "clock")
        #expect(!decoded.root.kind.takesChildren)
    }

    @Test
    func aTodayNodeRoundTripsAndTakesNoChildren() throws {
        let document = try PluginDocument(root: PluginNode(.today))
        let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

        #expect(decoded == document)
        #expect(decoded.root.kind.name == "today")
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: PluginNode(.today, children: [PluginNode(.text("x"))]))
        }
    }

    @Test(
        arguments: [
            PluginSliderStyle.standard,
            PluginSliderStyle.ruler(labelEvery: 4, labels: .duration),
            PluginSliderStyle.ruler(labelEvery: 1, labels: .clockTime),
            PluginSliderStyle.ruler(labelEvery: 96, labels: .clockTime),
        ]
    )
    func aSliderRoundTripsItsStyle(_ style: PluginSliderStyle) throws {
        let slider   = PluginNode(
            .slider(value: 60, minimum: 15, maximum: 1_440, step: 15, style: style, action: "set"),
            id: "ruler"
        )
        let document = try PluginDocument(root: slider)
        let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

        #expect(decoded == document)
        #expect(decoded.root.kind == .slider(value: 60, minimum: 15, maximum: 1_440, step: 15, style: style, action: "set"))
    }

    /// everyKind has one value of each of the vocabulary's cases, so a case added to
    /// `PluginNodeKind` and forgotten in the decoder's mirror fails the round trip below.
    private static let everyKind: [PluginNodeKind] = [
        .vStack(alignment: .leading, spacing: 4),
        .hStack(alignment: .center, spacing: nil),
        .zStack(alignment: .center),
        .viewThatFits(axes: .vertical),
        .spacer(minLength: 2),
        .text("Title"),
        .symbol(name: "star.fill"),
        .asset(id: "artwork"),
        .shape(.roundedRectangle(cornerRadius: 6)),
        .date(Date(timeIntervalSince1970: 1_800_000_000), style: .time),
        .clock,
        .today,
        .timer(start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_000_060), countsDown: true),
        .timerProgress(start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_000_060)),
        .countdown(end: Date(timeIntervalSince1970: 1_800_000_060), style: .hoursMinutes),
        .progress(value: 0.5, total: 1, style: .circular),
        .button(action: "next"),
        .toggle(isOn: true, action: "play"),
        .slider(value: 0.5, minimum: 0, maximum: 1, step: 0.1, style: .ruler(labelEvery: 4, labels: .clockTime), action: "seek"),
        .sliderValue(id: "ruler"),
        .component(id: "audio.spectrum", version: 1, parameters: ["bars": .number(12), "live": .bool(true)]),
        .regions,
    ]

    /// caseNumber numbers each case of the vocabulary with an exhaustive `switch` and no
    /// `default`: a case added to `PluginNodeKind` fails to compile here until it is numbered, which
    /// sends whoever adds it to this test to give it a sample in `everyKind` and to raise `caseCount`.
    private static func caseNumber(_ kind: PluginNodeKind) -> Int {
        switch kind {
            case .vStack       : 0
            case .hStack       : 1
            case .zStack       : 2
            case .viewThatFits : 3
            case .spacer       : 4
            case .text         : 5
            case .symbol       : 6
            case .asset        : 7
            case .shape        : 8
            case .date         : 9
            case .clock        : 10
            case .today        : 11
            case .timer        : 12
            case .timerProgress: 13
            case .countdown    : 14
            case .progress     : 15
            case .button       : 16
            case .toggle       : 17
            case .slider       : 18
            case .sliderValue  : 21
            case .component    : 19
            case .regions      : 20
        }
    }

    private static let caseCount = 22

    @Test
    func everyNodeKindRoundTripsThroughJSON() throws {
        #expect(Set(Self.everyKind.map(Self.caseNumber)) == Set(0..<Self.caseCount))

        for kind in Self.everyKind {
            let decoded = try JSONDecoder().decode(PluginNodeKind.self, from: JSONEncoder().encode(kind))

            #expect(decoded == kind, "\(kind.name) did not round-trip")
        }
    }

    @Test
    func aSliderWithoutAStyleDecodesAsStandard() throws {
        let json     = #"{"schema":2,"root":{"kind":{"slider":{"value":0.5,"minimum":0,"maximum":1,"action":"volume"}}}}"#
        let document = try PluginDocument.decode(Data(json.utf8))

        #expect(document.root.kind == .slider(value: 0.5, minimum: 0, maximum: 1, step: nil, style: .standard, action: "volume"))
    }

    /// aSliderValueNamesASliderOfTheSameDocument: the node round-trips, takes no children, and
    /// the id it names must be a slider's explicit id, before or after it, on either page.
    @Test
    func aSliderValueRoundTripsAndNamesASliderOfTheDocument() throws {
        let slider = PluginNode(
            .slider(value: 60, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 4, labels: .duration), action: "set"),
            id: "ruler"
        )
        let value  = PluginNode(.sliderValue(id: "ruler"))

        for order in [[slider, value], [value, slider]] {
            let document = try PluginDocument(root: PluginNode(.hStack(alignment: .center, spacing: nil), children: order))
            let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

            #expect(decoded == document)
            #expect(decoded.root.children.contains { $0.kind == .sliderValue(id: "ruler") })
        }

        let split = try PluginDocument(root: slider, optionsRoot: value, optionsAction: nil)
        #expect(split.optionsRoot?.kind == .sliderValue(id: "ruler"))

        #expect(PluginNode(.sliderValue(id: "ruler")).kind.name == "sliderValue")
        #expect(!PluginNodeKind.sliderValue(id: "ruler").takesChildren)
        #expect(throws: AddonFailure.self) {
            try PluginDocument(
                root: PluginNode(
                    .hStack(alignment: .center, spacing: nil),
                    children: [slider, PluginNode(.sliderValue(id: "ruler"), children: [PluginNode(.text("x"))])]
                )
            )
        }
    }

    @Test
    func aSliderValueNeedsASliderOfTheSameDocument() {
        let slider  = PluginNode(
            .slider(value: 60, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 4, labels: .duration), action: "set"),
            id: "ruler"
        )
        let unnamed = PluginNode(.slider(value: 60, minimum: 15, maximum: 1_440, step: 15, action: "set"))
        let button  = PluginNode(.button(action: "go"), id: "go", children: [PluginNode(.text("Go"))])
        let stack   = { (children: [PluginNode]) in PluginNode(.vStack(alignment: .leading, spacing: nil), children: children) }

        let unknown = stack([slider, PluginNode(.sliderValue(id: "missing"))])
        let nothing = stack([PluginNode(.sliderValue(id: "ruler"))])
        let notOne  = stack([slider, button, PluginNode(.sliderValue(id: "go"))])
        let anon    = stack([unnamed, PluginNode(.sliderValue(id: "ruler"))])
        let badID   = stack([slider, PluginNode(.sliderValue(id: "not valid!"))])

        for root in [unknown, nothing, notOne, anon, badID] {
            #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
        }
    }

    @Test
    func theBuilderDefaultsASlidersStyleToStandard() {
        let plain = PluginNode(.slider(value: 0.5, minimum: 0, maximum: 1, step: nil, action: "volume"))

        #expect(plain.kind == .slider(value: 0.5, minimum: 0, maximum: 1, step: nil, style: .standard, action: "volume"))
    }

    @Test(
        arguments: [
            PluginNode(.slider(value: 60, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 0, labels: .duration), action: "set")),
            PluginNode(.slider(value: 60, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 97, labels: .duration), action: "set")),
            PluginNode(.slider(value: 60, minimum: 15, maximum: 1_440, step: nil, style: .ruler(labelEvery: 4, labels: .duration), action: "set")),
            PluginNode(.slider(value: 60, minimum: 0, maximum: 2_049, step: 1, style: .ruler(labelEvery: 4, labels: .duration), action: "set")),
        ]
    )
    func aRulerNeedsALabelCadenceAStepAndABoundedNumberOfTicks(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test
    func aRulerAcceptsItsLimits() {
        let widest = PluginNode(.slider(value: 60, minimum: 0, maximum: 2_048, step: 1, style: .ruler(labelEvery: 96, labels: .duration), action: "set"))
        let finest = PluginNode(.slider(value: 60, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 1, labels: .clockTime), action: "set"))

        #expect(throws: Never.self) { try PluginDocument(root: widest) }
        #expect(throws: Never.self) { try PluginDocument(root: finest) }
    }

    @Test
    func aTimeZoneRoundTripsAndMustNameAKnownZone() throws {
        let document = try PluginDocument(root: PluginNode(.clock, modifiers: [.timeZone("Asia/Tokyo")]))
        let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

        #expect(decoded == document)
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: PluginNode(.clock, modifiers: [.timeZone("Mars/Olympus")]))
        }
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: PluginNode(.clock, modifiers: [.timeZone("")]))
        }
    }

    @Test
    func aViewThatFitsRoundTripsAndNeedsAnAlternative() throws {
        let document = try PluginDocument(root: PluginNode(.viewThatFits(axes: .vertical), children: [PluginNode(.text("large")), PluginNode(.text("small"))]))
        let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

        #expect(decoded == document)
        #expect(decoded.root.kind.name == "viewThatFits")
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: PluginNode(.viewThatFits(axes: .both)))
        }
    }
}
