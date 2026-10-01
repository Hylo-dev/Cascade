//
//  PluginNodeStoreTests.swift
//  CascadeKit
//

import CascadeContracts
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
}

/// SentRequests records what the store submitted to the engine.
@MainActor
final class SentRequests {

    var requests: [PluginActionRequest] = []
}
