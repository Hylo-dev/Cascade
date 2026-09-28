//
//  ProbeCounterTests.swift
//  Cascade Addon Platform Probe
//

import Foundation

let session = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

func encoded(_ sequence: Int, _ action: ProbeCounterAction, _ count: Int,
             sessionID: UUID = session) -> Data {
    try! JSONEncoder().encode(ProbeCounterEvent(
        sessionID: sessionID, sequence: sequence, action: action, count: count
    ))
}

func accepted(_ reducer: inout ProbeCounterReducer, _ data: Data) {
    let ack = reducer.accept(data)
    assert(ack?.accepted == true && ack?.terminal == false)
}

@main
enum ProbeCounterTests {
    static func main() {
        var success = ProbeCounterReducer(sessionID: session)
        accepted(&success, encoded(0, .initial, 0))
        accepted(&success, encoded(1, .increment, 1))
        accepted(&success, encoded(2, .reset, 0))

        var malformed = ProbeCounterReducer(sessionID: session)
        assert(malformed.accept(Data("{".utf8)) == nil)
        assert(malformed.isTerminal)
        assert(malformed.accept(encoded(0, .initial, 0)) == nil)

        var oversized = ProbeCounterReducer(sessionID: session)
        assert(oversized.accept(Data(repeating: 0, count: 1_025)) == nil)
        assert(oversized.isTerminal)

        var stale = ProbeCounterReducer(sessionID: session)
        let staleAck = stale.accept(encoded(0, .initial, 0,
            sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!))
        assert(staleAck?.accepted == false && staleAck?.terminal == true)

        var duplicate = ProbeCounterReducer(sessionID: session)
        accepted(&duplicate, encoded(0, .initial, 0))
        assert(duplicate.accept(encoded(0, .initial, 0))?.accepted == false)

        var reordered = ProbeCounterReducer(sessionID: session)
        accepted(&reordered, encoded(0, .initial, 0))
        assert(reordered.accept(encoded(2, .increment, 1))?.accepted == false)

        var badReset = ProbeCounterReducer(sessionID: session)
        accepted(&badReset, encoded(0, .initial, 0))
        accepted(&badReset, encoded(1, .increment, 1))
        assert(badReset.accept(encoded(2, .reset, 1))?.accepted == false)

        var capped = ProbeCounterReducer(sessionID: session)
        accepted(&capped, encoded(0, .initial, 0))
        for sequence in 1...ProbeCounterReducer.maximumActions {
            accepted(&capped, encoded(sequence, .reset, 0))
        }
        assert(capped.accept(encoded(ProbeCounterReducer.maximumActions + 1, .reset, 0))?.accepted == false)
        assert(capped.isTerminal)

        for data in [encoded(0, .increment, 1), encoded(0, .initial, -1),
                     encoded(-1, .initial, 0), Data("{\"action\":\"unknown\"}".utf8)] {
            var invalidInitial = ProbeCounterReducer(sessionID: session)
            assert(invalidInitial.accept(data)?.accepted != true)
            assert(invalidInitial.isTerminal)
            assert(invalidInitial.accept(encoded(0, .initial, 0)) == nil)
        }
        var invalidIncrement = ProbeCounterReducer(sessionID: session)
        accepted(&invalidIncrement, encoded(0, .initial, 0))
        assert(invalidIncrement.accept(encoded(1, .increment, Int.max))?.accepted == false)
        assert(invalidIncrement.isTerminal)

        print("ProbeCounterTests: PASS")
    }
}
