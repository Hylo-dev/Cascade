//
//  AudioHostProtocolTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@Suite
struct AudioHostProtocolTests {

    /// A conforming type proves the protocols are implementable with their `@objc` signatures.
    private final class RecordingClient: NSObject, AudioHostClientProtocol {

        nonisolated(unsafe) private(set) var published: [Data] = []

        func publish(_ snapshot: Data) { published.append(snapshot) }
    }

    @Test
    func aSnapshotCrossesTheClientProtocolAsWireData() throws {
        let client   = RecordingClient()
        let snapshot = try AudioHostSnapshot(generation: 3, apps: [], captureAllowed: nil)

        client.publish(try AudioHostWire.encode(snapshot))

        let received = try #require(client.published.first)
        #expect(try AudioHostWire.decode(AudioHostSnapshot.self, from: received) == snapshot)
    }
}
