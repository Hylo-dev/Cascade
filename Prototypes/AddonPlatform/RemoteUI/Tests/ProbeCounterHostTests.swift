import Foundation

@main
enum ProbeCounterHostTests {
    static let session = UUID()
    static func event(_ sequence: Int, _ action: ProbeCounterAction, _ count: Int,
                      sessionID: UUID = session) -> Data {
        try! JSONEncoder().encode(ProbeCounterEvent(sessionID: sessionID, sequence: sequence,
                                                   action: action, count: count))
    }
    static func receive(_ service: ProbeEventReceiverService, _ data: Data) -> ProbeCounterAck? {
        var replies = 0
        var ack: ProbeCounterAck?
        service.receive(data) { bytes in
            replies += 1
            assert(bytes.count <= ProbeCounterReducer.maximumBytes)
            ack = try? JSONDecoder().decode(ProbeCounterAck.self, from: bytes)
        }
        assert(replies == 1)
        return ack
    }
    static func main() {
        var invalidations = 0
        var observations: [[String: Any]] = []
        let service = ProbeEventReceiverService { observations.append($0) }
        assert(service.configure(sessionID: session, invalidate: { invalidations += 1 }))
        assert(!service.configure(sessionID: UUID(), invalidate: { assertionFailure("replacement") }))
        for (sequence, action, count) in [(0, ProbeCounterAction.initial, 0), (1, .increment, 1), (2, .reset, 0)] {
            let ack = receive(service, event(sequence, action, count))!
            assert(ack.accepted && !ack.terminal && ack.sessionID == session && ack.sequence == sequence)
            assert(observations.last?["count"] as? Int == count)
            assert(observations.last?["sequence"] as? Int == sequence)
            assert(observations.last?["sessionID"] as? String == session.uuidString)
            assert(observations.last?["action"] as? String == action.rawValue)
        }
        assert(observations.count == 3 && invalidations == 0)
        let rejected = receive(service, event(2, .reset, 0))!
        assert(!rejected.accepted && rejected.terminal)
        assert(receive(service, event(3, .increment, 1)) == nil)
        assert(invalidations == 1, "terminal receiver must invalidate its channel only once")
        service.failClosed()
        assert(invalidations == 1 && observations.count == 3)

        for invalid in [Data("{".utf8), Data(repeating: 0, count: 1025),
                        event(0, .initial, 0, sessionID: UUID()), event(1, .initial, 0)] {
            var stops = 0
            let bad = ProbeEventReceiverService { _ in assertionFailure("invalid observation") }
            assert(bad.configure(sessionID: session, invalidate: { stops += 1 }))
            assert(receive(bad, invalid)?.accepted != true)
            assert(receive(bad, event(0, .initial, 0)) == nil)
            bad.failClosed()
            assert(stops == 1)
        }
        let early = ProbeEventReceiverService { _ in assertionFailure("early event") }
        assert(receive(early, event(0, .initial, 0)) == nil)
        assert(!early.configure(sessionID: session, invalidate: {}))
        var closedCount = 0
        let closed = ProbeEventReceiverService { _ in assertionFailure("late event") }
        assert(closed.configure(sessionID: session, invalidate: { closedCount += 1 }))
        DispatchQueue.concurrentPerform(iterations: 32) { _ in closed.failClosed() }
        closed.failClosed()
        assert(receive(closed, event(0, .initial, 0)) == nil)
        assert(!closed.configure(sessionID: UUID(), invalidate: {}))
        assert(closedCount == 1)
        print("ProbeCounterHostTests: PASS")
    }
}
