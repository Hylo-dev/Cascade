//
//  RulerInteractionTests.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI
import Testing

@testable import CascadeKit
@testable import CascadePluginEngine

@Suite
struct RulerInteractionTests {

    private let scale = RulerScale(minimum: 15, maximum: 1_440, step: 15, spacing: 13)

    private func interaction() -> RulerInteraction {
        RulerInteraction()
    }

    @Test
    func aTouchUnderAPointIsATap() {
        var ruler = interaction()

        let right = ruler.change(translation: 0.9, current: 90, scale: scale)
        let left  = ruler.change(translation: -0.9, current: 90, scale: scale)
        let end   = ruler.end(current: 90, scale: scale)

        #expect(right == nil)
        #expect(left == nil)
        #expect(!ruler.isDragging)
        #expect(end == nil)
    }

    @Test
    func aDragFollowsTheFingerAndEndsOnTheNearestStep() {
        var ruler = interaction()

        let shown = ruler.change(translation: -19.5, current: 90, scale: scale)
        let held  = ruler.isDragging
        let later = ruler.change(translation: -26, current: shown ?? 0, scale: scale)
        let end   = ruler.end(current: shown ?? 0, scale: scale)

        #expect(shown == 112.5)
        #expect(held)
        #expect(later == 120)
        #expect(end == 120)
    }

    @Test
    func theStartOfTheDragIsRememberedNotTheLatestValue() {
        var ruler = interaction()

        _ = ruler.change(translation: -13, current: 90, scale: scale)
        let shown = ruler.change(translation: -26, current: 105, scale: scale)

        #expect(shown == 120)
    }

    @Test
    func aDragIsClampedToTheRangeAndSnapsInside() {
        var ruler = interaction()

        let shown = ruler.change(translation: 100_000, current: 90, scale: scale)
        let end   = ruler.end(current: shown ?? 0, scale: scale)

        #expect(shown == 15)
        #expect(end == 15)
    }

    @Test
    func endingTwiceSendsOnce() {
        var ruler = interaction()
        _ = ruler.change(translation: -13, current: 90, scale: scale)

        let first  = ruler.end(current: 105, scale: scale)
        let second = ruler.end(current: 105, scale: scale)

        #expect(first == 105)
        #expect(second == nil)
    }

    @Test
    func aStepMovesByOneStepAndStopsAtTheEnds() {
        let ruler = interaction()

        #expect(ruler.adjust(1, current: 90, scale: scale) == 105)
        #expect(ruler.adjust(-1, current: 90, scale: scale) == 75)
        #expect(ruler.adjust(1, current: 1_440, scale: scale) == nil)
        #expect(ruler.adjust(-1, current: 15, scale: scale) == nil)
        #expect(ruler.adjust(1, current: 1_430, scale: scale) == 1_440)
    }

    @Test
    func cancellingForgetsTheDragAndSaysSo() {
        var ruler = interaction()

        let idle = ruler.cancel()
        _ = ruler.change(translation: -13, current: 90, scale: scale)
        let held = ruler.cancel()

        #expect(!idle)
        #expect(held)
        #expect(!ruler.isDragging)
    }
}

/// RulerGestureTests drives a real `PluginNodeStore` with the ruler's gestures, through the
/// same `RulerGestureDriver` the view uses, and reads what the plugin would be sent.
@MainActor
struct RulerGestureTests {

    private let ruler = PluginNodeID(rawValue: "#ruler:slider")

    private final class Box {

        var interaction = RulerInteraction()
        var scale       = RulerScale(minimum: 15, maximum: 1_440, step: 15, spacing: 13)
        var animations  = [Animation?]()
        var cancels     = 0
        var deferred    = [() -> Void]()

        /// runDeferred runs the checks the driver put off, as the next main turn would.
        func runDeferred() {
            let pending = deferred
            deferred    = []
            pending.forEach { $0() }
        }
    }

    private struct Harness {

        let store: PluginNodeStore
        let model: PluginNodeModel
        let sent : SentRequests
        let box  : Box

        var driver: RulerGestureDriver {
            RulerGestureDriver(
                interaction: Binding(get: { box.interaction }, set: { box.interaction = $0 }),
                value      : Binding(
                    get: { model.optimistic?.number ?? 90 },
                    set: { store.drag($0, on: model) }
                ),
                scale      : box.scale,
                animation  : nil,
                released   : { animation in
                    box.animations.append(animation)
                    store.release(model, animation: animation)
                },
                cancelled  : {
                    box.cancels += 1
                    store.cancelDrag(model)
                },
                deferCheck : { box.deferred.append($0) }
            )
        }
    }

    private func harness() throws -> Harness {
        var publisher = PluginRenderFixtures.Publisher()
        let sent      = SentRequests()
        let store     = PluginNodeStore(
            key     : PluginRenderFixtures.key,
            submit  : { sent.requests.append($0) },
            schedule: { _, _ in }
        )
        let document  = try PluginDocument(
            root: PluginNode(
                .slider(value: 90, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 4, labels: .duration), action: "set"),
                id: "ruler"
            )
        )
        store.apply(publisher.publish(document))

        return Harness(
            store: store,
            model: try #require(store.model(ruler)),
            sent : sent,
            box  : Box()
        )
    }

    @Test
    func aTapSendsNothing() throws {
        let harness = try harness()

        harness.driver.changed(translation: 0.5)
        harness.driver.ended()

        #expect(harness.sent.requests.isEmpty)
        #expect(harness.model.optimistic == nil)
        #expect(!harness.model.isDragging)
    }

    @Test
    func aDragSendsNothingUntilItIsReleasedThenExactlyOnceAtTheStep() throws {
        let harness = try harness()

        harness.driver.changed(translation: -5)
        harness.driver.changed(translation: -20)
        harness.driver.changed(translation: -19.5)

        #expect(harness.sent.requests.isEmpty)
        #expect(harness.model.isDragging)
        #expect(harness.model.optimistic == .number(112.5))

        harness.driver.ended()

        #expect(harness.sent.requests.map(\.value) == [.number(120)])
        #expect(harness.model.optimistic == .number(120))
        #expect(!harness.model.isDragging)
    }

    @Test
    func theReleaseCarriesTheAnimationTheViewChose() throws {
        let harness = try harness()

        harness.driver.changed(translation: -26)
        harness.driver.ended()

        #expect(harness.box.animations.count == 1)
        #expect(harness.box.animations.first == .some(nil))
    }

    @Test
    func eachAccessibilityStepSendsOneAction() throws {
        let harness = try harness()

        harness.driver.adjust(1)
        harness.driver.adjust(1)
        harness.driver.adjust(-1)

        #expect(harness.sent.requests.map(\.value) == [.number(105), .number(120), .number(105)])
    }

    @Test
    func aStepAtTheEndOfTheRangeSendsNothing() throws {
        let harness = try harness()
        harness.store.drag(1_440, on: harness.model)

        harness.driver.adjust(1)
        #expect(harness.sent.requests.isEmpty)

        harness.store.drag(15, on: harness.model)
        harness.driver.adjust(-1)
        #expect(harness.sent.requests.isEmpty)
    }

    @Test
    func aDragInterruptedByTheViewLeavingOrTheSystemSendsNothingAndLetsGo() throws {
        let harness = try harness()

        harness.driver.changed(translation: -26)
        #expect(harness.model.isDragging)

        harness.driver.interrupted()

        #expect(harness.sent.requests.isEmpty)
        #expect(harness.box.cancels == 1)
        #expect(!harness.model.isDragging)
        #expect(harness.model.optimistic == nil)
        #expect(!harness.box.interaction.isDragging)
    }

    @Test
    func interruptingWithoutADragDoesNothing() throws {
        let harness = try harness()

        harness.driver.interrupted()

        #expect(harness.box.cancels == 0)
    }

    @Test
    func aReleaseUsesTheRangeAndGridOfTheMomentNotOfTheFirstDrag() throws {
        let harness = try harness()

        harness.driver.changed(translation: -13)
        harness.driver.ended()
        #expect(harness.sent.requests.last?.value == .number(105))

        // A publication re-anchors the range and coarsens the grid: 60 ... 600 by 30.
        harness.box.scale = RulerScale(minimum: 60, maximum: 600, step: 30, spacing: 13)
        // The value shown, 105, is off the new grid; one step of 30 later it lands on it.
        harness.driver.changed(translation: -13)
        harness.driver.ended()

        #expect(harness.sent.requests.map(\.value) == [.number(105), .number(150)])
    }

    @Test
    func aRangeThatChangesMidDragClampsAndSnapsTheReleaseToTheNewOne() throws {
        let harness = try harness()

        harness.driver.changed(translation: -13)
        harness.box.scale = RulerScale(minimum: 15, maximum: 100, step: 25, spacing: 13)
        harness.driver.changed(translation: -130)
        harness.driver.ended()

        #expect(harness.sent.requests.map(\.value) == [.number(90)])
    }

    @Test
    func aStepUsesTheCurrentGridToo() throws {
        let harness = try harness()
        harness.box.scale = RulerScale(minimum: 0, maximum: 300, step: 30, spacing: 13)

        harness.driver.adjust(1)

        #expect(harness.sent.requests.map(\.value) == [.number(120)])
    }

    @Test
    func aResetThatComesBeforeTheEndNeverEatsTheRelease() throws {
        let harness = try harness()

        harness.driver.changed(translation: -26)
        harness.driver.gestureStateReset()
        harness.driver.ended()
        harness.box.runDeferred()

        #expect(harness.sent.requests.map(\.value) == [.number(120)])
        #expect(harness.box.cancels == 0)
    }

    @Test
    func aResetThatComesAfterTheEndSchedulesNothing() throws {
        let harness = try harness()

        harness.driver.changed(translation: -26)
        harness.driver.ended()
        harness.driver.gestureStateReset()

        #expect(harness.box.deferred.isEmpty)
        #expect(harness.sent.requests.count == 1)
    }

    @Test
    func aResetWithNoEndLetsGoOfTheDragOneTurnLaterWithoutSending() throws {
        let harness = try harness()

        harness.driver.changed(translation: -26)
        harness.driver.gestureStateReset()

        #expect(harness.model.isDragging)

        harness.box.runDeferred()

        #expect(harness.box.cancels == 1)
        #expect(harness.sent.requests.isEmpty)
        #expect(!harness.model.isDragging)
        #expect(harness.model.optimistic == nil)
    }

    @Test
    func aNewDragThatBeganBeforeTheDeferredCheckIsNotCancelled() throws {
        let harness = try harness()

        harness.driver.changed(translation: -26)
        harness.driver.gestureStateReset()
        harness.driver.ended()
        harness.driver.changed(translation: -13)
        harness.box.runDeferred()

        #expect(harness.box.cancels == 0)
        #expect(harness.model.isDragging)
        #expect(harness.box.interaction.isDragging)

        harness.driver.ended()

        #expect(harness.sent.requests.count == 2)
    }

    @Test
    func aResetWhileNothingIsDraggedSchedulesNothing() throws {
        let harness = try harness()

        harness.driver.changed(translation: 0.5)
        harness.driver.gestureStateReset()

        #expect(harness.box.deferred.isEmpty)
    }
}
