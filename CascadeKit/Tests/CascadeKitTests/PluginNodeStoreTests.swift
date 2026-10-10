//
//  PluginNodeStoreTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Observation
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct PluginNodeStoreTests {

    private typealias Fixtures = PluginRenderFixtures

    private let play   = PluginNodeID(rawValue: "#play:toggle")
    private let volume = PluginNodeID(rawValue: "#volume:slider")
    private let next   = PluginNodeID(rawValue: "#next:button")

    private func store(
        sent     : SentRequests? = nil,
        scheduler: ManualScheduler? = nil
    ) -> PluginNodeStore {
        let sent      = sent ?? SentRequests()
        let scheduler = scheduler ?? ManualScheduler()

        return PluginNodeStore(
            key     : Fixtures.key,
            submit  : { sent.requests.append($0) },
            schedule: { scheduler.schedule($0, $1) }
        )
    }

    @Test
    func theFirstPublicationBuildsAModelPerNode() throws {
        var publisher = Fixtures.Publisher()
        let store     = store()

        store.apply(publisher.publish(try Fixtures.face()))

        #expect(store.revision == 1)
        #expect(store.root?.id == PluginNodeID(rawValue: "root:hStack"))
        #expect(store.root?.children.count == 5)
        #expect(store.model(PluginNodeID(rawValue: "#title:text"))?.kind == .text("One"))
    }

    @Test
    func aKindChangeReplacesTheModelAndItsParentsChildren() throws {
        var publisher = Fixtures.Publisher()
        let store     = store()
        store.apply(publisher.publish(try Fixtures.face()))
        let text = PluginNodeID(rawValue: "root:hStack/0:text")

        store.apply(publisher.publish(try Fixtures.face(art: .symbol(name: "music.note"))))

        let symbol = PluginNodeID(rawValue: "root:hStack/0:symbol")
        #expect(store.model(text) == nil)
        #expect(store.model(symbol)?.kind == .symbol(name: "music.note"))
        #expect(store.root?.children.first == symbol)
    }

    @Test
    func aDiffNotifiesOnlyTheModelsOfChangedNodes() throws {
        var publisher = Fixtures.Publisher()
        let store     = store()
        let log       = NotificationLog()
        store.apply(publisher.publish(try Fixtures.face()))

        let change = publisher.publish(try Fixtures.face(title: "Two"))
        for id in change.content?.table.entries.map(\.id) ?? [] {
            guard let model = store.model(id) else { continue }

            withObservationTracking {
                _ = (model.kind, model.modifiers, model.children, model.layers, model.optimistic)
            } onChange: {
                log.record(id.rawValue)
            }
        }
        withObservationTracking {
            _ = (store.root, store.glassLights)
        } onChange: {
            log.record("store")
        }

        store.apply(change)

        #expect(log.names == ["#title:text"])
    }

    @Test
    func aWithdrawalEmptiesTheStore() throws {
        var publisher = Fixtures.Publisher()
        let store     = store()
        store.apply(publisher.publish(try Fixtures.face()))

        let withdrawal = publisher.withdraw()

        store.apply(try #require(withdrawal))

        #expect(store.root == nil)
        #expect(store.model(play) == nil)
    }

    @Test
    func aToggleShowsItsNewValueAtOnceAndSendsTheAction() throws {
        var publisher = Fixtures.Publisher()
        let sent      = SentRequests()
        let store     = store(sent: sent)
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(play))

        store.set(.bool(false), on: model)

        #expect(model.optimistic == .bool(false))
        #expect(sent.requests == [PluginActionRequest(key: Fixtures.key, node: play, revision: 1, value: .bool(false))])
    }

    @Test
    func theNextPublicationWinsOverTheOptimisticValue() throws {
        var publisher = Fixtures.Publisher()
        let store     = store()
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(play))
        store.set(.bool(false), on: model)

        store.apply(publisher.publish(try Fixtures.face(title: "Two")))

        #expect(model.optimistic == nil)
    }

    @Test
    func anUnconfirmedValueRevertsAfterTheTimeout() throws {
        var publisher = Fixtures.Publisher()
        let scheduler = ManualScheduler()
        let store     = store(scheduler: scheduler)
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(play))
        store.set(.bool(false), on: model)

        scheduler.run(0)

        #expect(scheduler.delays == [.milliseconds(1_500)])
        #expect(model.optimistic == nil)
    }

    @Test
    func anOlderTapsTimeoutDoesNotRevertANewerOne() throws {
        var publisher = Fixtures.Publisher()
        let scheduler = ManualScheduler()
        let store     = store(scheduler: scheduler)
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(play))
        store.set(.bool(false), on: model)
        store.set(.bool(true), on: model)

        scheduler.run(0)
        #expect(model.optimistic == .bool(true))

        scheduler.run(1)
        #expect(model.optimistic == nil)
    }

    @Test
    func aRemovedModelsTimeoutCannotCancelItsReplacementConfirmation() throws {
        var publisher = Fixtures.Publisher()
        let scheduler = ManualScheduler()
        let store = store(scheduler: scheduler)
        store.apply(publisher.publish(try Fixtures.face()))
        let old = try #require(store.model(play))
        store.set(.bool(false), on: old)
        store.apply(publisher.publish(try PluginDocument(root: PluginNode(.text("Removed")))))
        store.apply(publisher.publish(try Fixtures.face()))
        let current = try #require(store.model(play))
        store.set(.bool(false), on: current)

        scheduler.run(0)
        #expect(current.optimistic == .bool(false))
        scheduler.run(1)
        #expect(current.optimistic == nil)
    }

    @Test
    func aRefusedActionReverts() throws {
        var publisher = Fixtures.Publisher()
        let sent      = SentRequests()
        let store     = store(sent: sent)
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(play))
        store.set(.bool(false), on: model)

        store.reject(try #require(sent.requests.first))

        #expect(model.optimistic == nil)
    }

    @Test
    func aDraggedSliderIgnoresPublicationsAndSendsOnRelease() throws {
        var publisher = Fixtures.Publisher()
        let sent      = SentRequests()
        let store     = store(sent: sent)
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(volume))

        store.drag(0.2, on: model)
        store.drag(0.3, on: model)
        store.apply(publisher.publish(try Fixtures.face(volume: 0.9)))

        #expect(model.optimistic == .number(0.3))
        #expect(sent.requests.isEmpty)

        store.release(model)

        #expect(sent.requests == [PluginActionRequest(key: Fixtures.key, node: volume, revision: 2, value: .number(0.3))])
    }

    @Test
    func anEarlierReleasesTimeoutDoesNotTouchANewDrag() throws {
        var publisher = Fixtures.Publisher()
        let sent      = SentRequests()
        let scheduler = ManualScheduler()
        let store     = store(sent: sent, scheduler: scheduler)
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(volume))
        store.drag(0.3, on: model)
        store.release(model)
        store.drag(0.6, on: model)

        scheduler.run(0)
        #expect(model.optimistic == .number(0.6))

        store.release(model)
        #expect(sent.requests.map(\.value) == [.number(0.3), .number(0.6)])
    }

    @Test
    func anEarlierRefusalDoesNotTouchANewDrag() throws {
        var publisher = Fixtures.Publisher()
        let sent      = SentRequests()
        let store     = store(sent: sent)
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(volume))
        store.drag(0.3, on: model)
        store.release(model)
        store.drag(0.6, on: model)

        store.reject(try #require(sent.requests.first))

        #expect(model.optimistic == .number(0.6))
    }

    @Test
    func aButtonSendsItsActionAndHoldsNoState() throws {
        var publisher = Fixtures.Publisher()
        let sent      = SentRequests()
        let store     = store(sent: sent)
        store.apply(publisher.publish(try Fixtures.face()))
        let model = try #require(store.model(next))

        store.press(model)

        #expect(sent.requests == [PluginActionRequest(key: Fixtures.key, node: next, revision: 1)])
        #expect(model.optimistic == nil)
    }

    // MARK: - A slider's live value

    private func valueDocument(
        _ style : PluginSliderStyle,
        value   : Double,
        minimum : Double,
        maximum : Double,
        step    : Double?,
        caption : String = ""
    ) throws -> PluginDocument {
        try PluginDocument(
            root: PluginNode(
                .hStack(alignment: .center, spacing: nil),
                children: [
                    PluginNode(.text(caption), id: "caption"),
                    PluginNode(.sliderValue(id: "ruler")),
                    PluginNode(
                        .slider(value: value, minimum: minimum, maximum: maximum, step: step, style: style, action: "set"),
                        id: "ruler"
                    ),
                ]
            )
        )
    }

    /// aSliderValueFollowsItsRulerWithoutAPublication: a drag moves the number, snapped to the
    /// ruler's step, with no publication and no action; the release sends one; the publication
    /// that confirms it leaves the number where it is.
    @Test
    func aSliderValueFollowsItsRulersDragWithoutAPublication() throws {
        var publisher = Fixtures.Publisher()
        let sent      = SentRequests()
        let store     = store(sent: sent)
        let cache     = RulerLabelCache()
        let ruler     = PluginNodeID(rawValue: "#ruler:slider")
        store.apply(publisher.publish(try valueDocument(.ruler(labelEvery: 4, labels: .duration), value: 90, minimum: 15, maximum: 1_440, step: 15)))
        let model = try #require(store.model(ruler))

        #expect(store.sliderReading("ruler")?.text(cache: cache) == RulerLabel.text(value: 90, labels: .duration))

        store.drag(128, on: model)

        #expect(store.revision == 1)
        #expect(store.sliderReading("ruler")?.value == 135)
        #expect(store.sliderReading("ruler")?.text(cache: cache) == RulerLabel.text(value: 135, labels: .duration))
        #expect(sent.requests.isEmpty)

        store.drag(1_000_000, on: model)
        #expect(store.sliderReading("ruler")?.value == 1_440)

        store.drag(128, on: model)
        store.release(model)
        #expect(sent.requests.count == 1)
        #expect(store.sliderReading("ruler")?.value == 135)

        store.apply(publisher.publish(try valueDocument(.ruler(labelEvery: 4, labels: .duration), value: 135, minimum: 15, maximum: 1_440, step: 15)))
        #expect(store.sliderReading("ruler")?.value == 135)
        #expect(model.optimistic == nil)
    }

    @Test
    func aSliderValueIsFormattedByItsSlidersStyle() throws {
        var publisher = Fixtures.Publisher()
        let store     = store()
        let cache     = RulerLabelCache()
        let instant   = 2_000_052_000.0

        store.apply(publisher.publish(try valueDocument(.ruler(labelEvery: 4, labels: .clockTime), value: instant, minimum: instant - 900, maximum: instant + 86_400, step: 900)))
        let clock = Date(timeIntervalSince1970: instant).formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .current, timeZone: .current))
        #expect(store.sliderReading("ruler")?.text(cache: cache) == clock)
        #expect(store.sliderReading("ruler")?.labels == .clockTime)

        store.apply(publisher.publish(try valueDocument(.standard, value: 0.5, minimum: 0, maximum: 1, step: nil)))
        #expect(store.sliderReading("ruler")?.labels == nil)
        #expect(store.sliderReading("ruler")?.text(cache: cache) == 0.5.formatted(.number.precision(.fractionLength(0...2))))

        store.drag(0.3333, on: try #require(store.model(PluginNodeID(rawValue: "#ruler:slider"))))
        #expect(store.sliderReading("ruler")?.text(cache: cache) == 0.33.formatted(.number.precision(.fractionLength(0...2))))
        #expect(store.sliderReading("missing") == nil)
    }

    /// aSliderValueRedrawsOnlyWhenItsSlidersValueChanges: a view that reads the reading is
    /// invalidated by a drag and by nothing else.
    @Test
    func aSliderValueIsInvalidatedByItsSlidersValueAndNothingElse() throws {
        var publisher = Fixtures.Publisher()
        let store     = store()
        store.apply(publisher.publish(try valueDocument(.ruler(labelEvery: 4, labels: .duration), value: 90, minimum: 15, maximum: 1_440, step: 15)))
        let model = try #require(store.model(PluginNodeID(rawValue: "#ruler:slider")))
        let log   = NotificationLog()

        withObservationTracking {
            _ = store.sliderReading("ruler")
        } onChange: {
            log.record("reading")
        }

        store.apply(publisher.publish(try valueDocument(.ruler(labelEvery: 4, labels: .duration), value: 90, minimum: 15, maximum: 1_440, step: 15, caption: "Other")))
        #expect(log.names.isEmpty)

        store.drag(120, on: model)
        #expect(log.names == ["reading"])
    }
}

/// SentRequests records what the store submitted to the engine.
@MainActor
final class SentRequests {

    var requests: [PluginActionRequest] = []
}
