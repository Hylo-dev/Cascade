//
//  StandardHealthPolicyTests.swift
//  CascadeKit
//

import Testing

@testable import CascadePluginEngine

@Suite
struct StandardHealthPolicyTests {

    /// react feeds the incidents, each at its second, to one history and returns the reactions.
    private func react(_ incidents: [(PluginIncident, Double)]) -> [PluginHealthReaction] {
        let policy  = StandardHealthPolicy()
        var history = PluginHealthHistory()

        return incidents.map { incident, seconds in
            policy.reaction(to: incident, history: &history, at: .seconds(seconds))
        }
    }

    @Test
    func throwsRetryAfterOneFiveAndThirtySeconds() {
        #expect(
            react([(.threw, 0), (.threw, 10), (.threw, 20)])
                == [.retry(after: .seconds(1)), .retry(after: .seconds(5)), .retry(after: .seconds(30))]
        )
    }

    @Test
    func theFourthIncidentInsideFiveMinutesQuarantines() {
        #expect(
            react([(.threw, 0), (.invalidPublication, 10), (.overBudget, 20), (.threw, 30)])
                == [.retry(after: .seconds(1)), .keep, .keep, .quarantine]
        )
    }

    @Test
    func incidentsOlderThanFiveMinutesAreForgotten() {
        #expect(
            react([(.threw, 0), (.threw, 10), (.threw, 20), (.threw, 320)])
                == [.retry(after: .seconds(1)), .retry(after: .seconds(5)), .retry(after: .seconds(30)), .retry(after: .seconds(5))]
        )
    }

    @Test
    func invalidPublicationsAndCPUDebtOnlyCount() {
        #expect(react([(.invalidPublication, 0), (.overBudget, 1)]) == [.keep, .keep])
    }

    @Test
    func theFirstHangDisablesAndTheSecondQuarantines() {
        #expect(react([(.hung, 0), (.hung, 1_000)]) == [.disable, .quarantine])
    }

    @Test
    func hangsStayOutOfTheIncidentWindow() {
        #expect(
            react([(.hung, 0), (.threw, 1), (.threw, 2), (.threw, 3)])
                == [.disable, .retry(after: .seconds(1)), .retry(after: .seconds(5)), .retry(after: .seconds(30))]
        )
    }
}
