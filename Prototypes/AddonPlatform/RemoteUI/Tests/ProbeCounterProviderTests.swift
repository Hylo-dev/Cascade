import Combine
import Foundation

private let session = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let otherSession = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

private final class ControlledReceiver: NSObject, ProbeEventReceiver {
    private(set) var events: [Data] = []
    private var replies: [(Data) -> Void] = []
    private var deliveries: [@MainActor () -> Void] = []

    func enqueue(_ action: @escaping @MainActor () -> Void) {
        deliveries.append(action)
    }

    func receive(_ data: Data, reply: @escaping (Data) -> Void) {
        events.append(data)
        replies.append(reply)
    }

    func event(at index: Int) -> ProbeCounterEvent {
        try! JSONDecoder().decode(ProbeCounterEvent.self, from: events[index])
    }

    @MainActor func reply(at index: Int, with data: Data) {
        replies[index](data)
        let pending = deliveries
        deliveries.removeAll()
        for delivery in pending { delivery() }
    }
}

private func ack(sessionID: UUID = session, sequence: Int,
                 accepted: Bool = true, terminal: Bool = false) -> Data {
    try! JSONEncoder().encode(ProbeCounterAck(
        sessionID: sessionID, sequence: sequence, accepted: accepted, terminal: terminal
    ))
}

@MainActor
private func activate(_ model: ProbeCounterModel, receiver: ControlledReceiver,
                      sessionID: UUID = session, replyingWith data: Data? = nil,
                      beforeReply: () -> Void = {}) async -> Bool {
    await withCheckedContinuation { continuation in
        model.activate(sessionID: sessionID, receiver: receiver) {
            continuation.resume(returning: $0)
        }
        beforeReply()
        if let data {
            receiver.reply(at: 0, with: data)
        }
    }
}

@MainActor
private func performAndAwait<Value: Equatable>(
    _ publisher: Published<Value>.Publisher,
    value expected: Value,
    action: () -> Void
) async {
    await withCheckedContinuation { continuation in
        var subscription: AnyCancellable?
        subscription = publisher.sink { value in
            guard value == expected else { return }
            subscription?.cancel()
            continuation.resume()
        }
        action()
    }
}

@main
@MainActor
enum ProbeCounterProviderTests {
    static func main() async {
        await testInitialAckAndCountSemantics()
        await testOnlyOneActionCanBeInFlight()
        await testInvalidAcknowledgementsFailClosed()
        await testMissingAckTimesOutAndLateReplyIsIgnored()
        testSubscriptionGateClaimsOnce()
        await testRepeatedActivationIsRejected()
        await testInvalidationCompletesActivationOnce()
        print("ProbeCounterProviderTests: PASS")
    }

    private static func testInitialAckAndCountSemantics() async {
        let receiver = ControlledReceiver()
        let model = ProbeCounterModel(deliverAcknowledgement: receiver.enqueue)
        let accepted = await activate(model, receiver: receiver, replyingWith: ack(sequence: 0)) {
            precondition(!model.enabled && !model.canIncrement && model.count == 0)
            precondition(receiver.event(at: 0).action == .initial)
        }
        precondition(accepted && model.enabled && model.canIncrement)

        await performAndAwait(model.$count, value: 1) {
            model.increment()
            precondition(!model.enabled && receiver.events.count == 2)
            let event = receiver.event(at: 1)
            precondition(event.sequence == 1 && event.action == .increment && event.count == 1)
            receiver.reply(at: 1, with: ack(sequence: 1))
        }
        precondition(model.enabled && model.canIncrement)

        await performAndAwait(model.$count, value: 0) {
            model.reset()
            precondition(!model.enabled && receiver.events.count == 3)
            let event = receiver.event(at: 2)
            precondition(event.sequence == 2 && event.action == .reset && event.count == 0)
            receiver.reply(at: 2, with: ack(sequence: 2))
        }
        precondition(model.enabled && model.canIncrement)
    }

    private static func testOnlyOneActionCanBeInFlight() async {
        let receiver = ControlledReceiver()
        let model = ProbeCounterModel(deliverAcknowledgement: receiver.enqueue)
        let accepted = await activate(model, receiver: receiver, replyingWith: ack(sequence: 0))
        precondition(accepted)

        model.increment()
        model.increment()
        model.reset()
        precondition(receiver.events.count == 2)
        await performAndAwait(model.$count, value: 1) {
            receiver.reply(at: 1, with: ack(sequence: 1))
        }
    }

    private static func testInvalidAcknowledgementsFailClosed() async {
        let invalidAcks = [
            ack(sequence: 0, accepted: false, terminal: true),
            ack(sessionID: otherSession, sequence: 0),
            ack(sequence: 1),
            Data(repeating: 0, count: ProbeCounterReducer.maximumBytes + 1),
            Data("{".utf8),
            ack(sequence: -1),
        ]

        for invalidAck in invalidAcks {
            let receiver = ControlledReceiver()
            let model = ProbeCounterModel(deliverAcknowledgement: receiver.enqueue)
            let accepted = await activate(model, receiver: receiver, replyingWith: invalidAck)
            precondition(!accepted)
            precondition(!model.enabled && !model.canIncrement && model.count == 0)
            model.increment()
            model.reset()
            precondition(receiver.events.count == 1)
        }
    }

    private static func testMissingAckTimesOutAndLateReplyIsIgnored() async {
        let receiver = ControlledReceiver()
        let model = ProbeCounterModel(deliverAcknowledgement: receiver.enqueue)
        var completions = 0
        let clock = ContinuousClock()
        let started = clock.now
        let accepted = await withCheckedContinuation { continuation in
            model.activate(sessionID: session, receiver: receiver) { accepted in
                completions += 1
                continuation.resume(returning: accepted)
            }
        }
        let elapsed = started.duration(to: clock.now)
        precondition(!accepted && elapsed >= .seconds(2) && completions == 1)
        precondition(!model.enabled && model.count == 0)

        receiver.reply(at: 0, with: ack(sequence: 0))
        precondition(completions == 1 && !model.enabled && model.count == 0)
    }

    private static func testSubscriptionGateClaimsOnce() {
        let gate = ProbeChannelGate()
        precondition(gate.claim())
        precondition(!gate.claim())
    }

    private static func testRepeatedActivationIsRejected() async {
        let receiver = ControlledReceiver()
        let model = ProbeCounterModel(deliverAcknowledgement: receiver.enqueue)
        var firstResult: Bool?
        model.activate(sessionID: session, receiver: receiver) { firstResult = $0 }

        var secondResult: Bool?
        model.activate(sessionID: otherSession, receiver: receiver) { secondResult = $0 }
        precondition(secondResult == false && receiver.events.count == 1)
        receiver.reply(at: 0, with: ack(sequence: 0))
        precondition(firstResult == true && model.enabled)

        var thirdResult: Bool?
        model.activate(sessionID: otherSession, receiver: receiver) { thirdResult = $0 }
        precondition(thirdResult == false && receiver.events.count == 1)
    }

    private static func testInvalidationCompletesActivationOnce() async {
        let invalidBeforeActivation = ProbeCounterModel()
        invalidBeforeActivation.deactivateFromChannel()
        var beforeResult: Bool?
        invalidBeforeActivation.activate(sessionID: session, receiver: ControlledReceiver()) {
            beforeResult = $0
        }
        precondition(beforeResult == false)

        let receiver = ControlledReceiver()
        let model = ProbeCounterModel(deliverAcknowledgement: receiver.enqueue)
        var results: [Bool] = []
        model.activate(sessionID: session, receiver: receiver) { results.append($0) }
        model.deactivateFromChannel()
        precondition(results == [false] && !model.enabled)

        receiver.reply(at: 0, with: ack(sequence: 0))
        model.deactivateFromChannel()
        precondition(results == [false] && !model.enabled && model.count == 0)
    }
}
