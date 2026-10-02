//
//  PluginBudgetTests.swift
//  CascadeKit
//

import Testing

@testable import CascadePluginEngine

@Suite
struct PluginBudgetTests {

    @Test
    func cpuDebtIsRepaidAtTheRefillRate() {
        var budget = PluginCPUBudget(at: .zero)

        #expect(budget.charge(.milliseconds(150), at: .zero) == .seconds(10))
    }

    @Test
    func cpuCreditRefillsWithElapsedTime() {
        var budget = PluginCPUBudget(at: .zero)

        #expect(budget.charge(.milliseconds(100), at: .zero) == .zero)
        #expect(budget.charge(.milliseconds(10), at: .seconds(2)) == .zero)
        #expect(budget.charge(.milliseconds(1), at: .seconds(2)) == .milliseconds(200))
    }

    @Test
    func cpuCreditNeverExceedsItsCapacity() {
        var budget = PluginCPUBudget(at: .zero)

        #expect(budget.charge(.milliseconds(150), at: .seconds(1_000)) == .seconds(10))
    }

    @Test
    func publicationsAllowABurstOfEightThenOneEveryQuarterSecond() {
        var budget = PluginPublicationBudget(at: .zero)

        for _ in 1...7 {
            #expect(budget.spend(at: .zero) == .zero)
        }
        #expect(budget.spend(at: .zero) == .milliseconds(250))
        #expect(budget.spend(at: .milliseconds(250)) == .milliseconds(250))
    }

    @Test
    func publicationTokensRefillUpToTheBurst() {
        var budget = PluginPublicationBudget(at: .zero)
        for _ in 1...8 {
            _ = budget.spend(at: .zero)
        }

        for _ in 1...7 {
            #expect(budget.spend(at: .seconds(60)) == .zero)
        }
        #expect(budget.spend(at: .seconds(60)) == .milliseconds(250))
    }

    @Test
    func noticesRefillAtTheFastestKeyRepeat() {
        var budget = PluginPublicationBudget(interval: PluginPublicationBudget.noticeInterval, at: .zero)

        for _ in 1...7 {
            #expect(budget.spend(at: .zero) == .zero)
        }
        #expect(budget.spend(at: .zero) == PluginPublicationBudget.noticeInterval)
        #expect(PluginPublicationBudget.noticeInterval <= .milliseconds(34))
    }
}
