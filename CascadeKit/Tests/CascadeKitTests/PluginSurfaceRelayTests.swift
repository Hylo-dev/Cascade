//
//  PluginSurfaceRelayTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct PluginSurfaceRelayTests {

    /// Hops records every hop the relay made and what it carried.
    @MainActor
    final class Hops {

        var changes : [[PluginPublicationChange]] = []
        var rejected: [[PluginActionRequest]] = []
    }

    private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    @Test
    func aBurstOfDeliveriesIsOneHop() async throws {
        var publisher = PluginRenderFixtures.Publisher()
        let hops      = Hops()
        let relay     = PluginSurfaceRelay { changes, rejected in
            hops.changes.append(changes)
            hops.rejected.append(rejected)
        }
        let first  = publisher.publish(try PluginRenderFixtures.face(title: "One"))
        let second = publisher.publish(try PluginRenderFixtures.face(title: "Two"))
        let refused = PluginActionRequest(key: PluginRenderFixtures.key, node: PluginNodeID(rawValue: "#next:button"), revision: 1)

        relay.deliver([first])
        relay.reject(refused)
        relay.deliver([second])
        try await settle { !hops.changes.isEmpty }
        try await Task.sleep(for: .milliseconds(20))

        #expect(hops.changes == [[first, second]])
        #expect(hops.rejected == [[refused]])
    }

    @Test
    func aDeliveryAfterTheHopStartsAnother() async throws {
        var publisher = PluginRenderFixtures.Publisher()
        let hops      = Hops()
        let relay     = PluginSurfaceRelay { changes, _ in hops.changes.append(changes) }
        let first     = publisher.publish(try PluginRenderFixtures.face(title: "One"))
        let second    = publisher.publish(try PluginRenderFixtures.face(title: "Two"))

        relay.deliver([first])
        try await settle { hops.changes.count == 1 }
        relay.deliver([second])
        try await settle { hops.changes.count == 2 }

        #expect(hops.changes == [[first], [second]])
    }

    @Test
    func deliveriesFromAnotherThreadReachTheMainActor() async throws {
        var publisher = PluginRenderFixtures.Publisher()
        let hops      = Hops()
        let relay     = PluginSurfaceRelay { changes, _ in
            MainActor.assertIsolated()
            hops.changes.append(changes)
        }
        let change = publisher.publish(try PluginRenderFixtures.face())

        await Task.detached { relay.deliver([change]) }.value
        try await settle { !hops.changes.isEmpty }

        #expect(hops.changes == [[change]])
    }
}
