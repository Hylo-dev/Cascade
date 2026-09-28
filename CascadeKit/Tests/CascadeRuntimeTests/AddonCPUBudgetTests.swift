//
//  AddonCPUBudgetTests.swift
//  Cascade
//

import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AddonCPUBudgetTests {
    @Test func startsWithOneHundredMilliseconds() throws {
        var budget = try AddonCPUBudget(at: .zero)
        let snapshot = try budget.snapshot(at: .zero)

        #expect(snapshot.balance == .milliseconds(100))
        #expect(snapshot.available == .milliseconds(100))
        #expect(snapshot.debt == .zero)
        #expect(!snapshot.exceeded)
    }

    @Test func chargeThenRefillAtFiveMillisecondsPerSecond() throws {
        var budget = try AddonCPUBudget(at: .zero)
        _ = try budget.charge(
            cpuNanoseconds: 100_000_000,
            at            : .zero
        )

        let snapshot = try budget.snapshot(at: .seconds(1))
        #expect(snapshot.balance == .milliseconds(5))
    }

    @Test func idleRefillCapsAtCapacity() throws {
        var budget = try AddonCPUBudget(at: .zero)
        _ = try budget.charge(
            cpuNanoseconds: 100_000_000,
            at            : .zero
        )
        let snapshot = try budget.snapshot(at: .nanoseconds(Int64.max))

        #expect(snapshot.balance == .milliseconds(100))
    }

    @Test func initializationRejectsInvalidInstants() {
        #expect(throws: AddonCPUBudget.Failure.invalidMonotonicInstant) {
            _ = try AddonCPUBudget(at: .seconds(-1))
        }
        #expect(throws: AddonCPUBudget.Failure.invalidMonotonicInstant) {
            _ = try AddonCPUBudget(at: .seconds(Int64.max) + .seconds(1))
        }
    }

    @Test func twoChargesAtOneInstantDoNotRefillTwice() throws {
        var budget = try AddonCPUBudget(at: .zero)
        _ = try budget.charge(
            cpuNanoseconds: 100_000_000,
            at            : .zero
        )
        _ = try budget.charge(
            cpuNanoseconds: 1_000_000,
            at            : .seconds(1)
        )
        let snapshot = try budget.charge(
            cpuNanoseconds: 1_000_000,
            at            : .seconds(1)
        )

        #expect(snapshot.balance == .milliseconds(3))
    }

    @Test func exactZeroIsExhaustedButNotExceeded() throws {
        var budget = try AddonCPUBudget(at: .zero)
        let snapshot = try budget.charge(
            cpuNanoseconds: 100_000_000,
            at            : .zero
        )

        #expect(snapshot.balance == .zero)
        #expect(snapshot.available == .zero)
        #expect(snapshot.debt == .zero)
        #expect(!snapshot.exceeded)
    }

    @Test func overspendCreatesDebtThatFutureRefillsRepay() throws {
        var budget = try AddonCPUBudget(at: .zero)
        let overspent = try budget.charge(
            cpuNanoseconds: 150_000_000,
            at            : .zero
        )
        let repaid = try budget.snapshot(at: .seconds(10))

        #expect(overspent.balance == .milliseconds(-50))
        #expect(overspent.available == .zero)
        #expect(overspent.debt == .milliseconds(50))
        #expect(overspent.exceeded)
        #expect(repaid.balance == .zero)
        #expect(!repaid.exceeded)
    }

    @Test func oneValueAggregatesMultipleJobsWithoutResetting() throws {
        var budget = try AddonCPUBudget(at: .zero)
        _ = try budget.charge(
            cpuNanoseconds: 60_000_000,
            at            : .zero
        )
        let secondJob = try budget.charge(
            cpuNanoseconds: 50_000_000,
            at            : .zero
        )

        #expect(secondJob.balance == .milliseconds(-10))
        #expect(secondJob.exceeded)
    }

    @Test func fractionalElapsedTimeRefillsWithoutDoubleConversion() throws {
        var budget = try AddonCPUBudget(at: .zero)
        _ = try budget.charge(
            cpuNanoseconds: 100_000_000,
            at            : .zero
        )
        let snapshot = try budget.snapshot(at: .nanoseconds(1))

        #expect(snapshot.balance == Duration(
            secondsComponent    : 0,
            attosecondsComponent: 5_000_000
        ))
    }

    @Test func invalidTimesLeaveThePriorStateUnchanged() throws {
        var budget = try AddonCPUBudget(at: .seconds(1))
        _ = try budget.charge(
            cpuNanoseconds: 50_000_000,
            at            : .seconds(2)
        )
        let before = try budget.snapshot(at: .seconds(2))

        #expect(throws: AddonCPUBudget.Failure.invalidMonotonicInstant) {
            try budget.snapshot(at: .seconds(2) - Duration(
                secondsComponent    : 0,
                attosecondsComponent: 1
            ))
        }
        #expect(throws: AddonCPUBudget.Failure.invalidMonotonicInstant) {
            try budget.snapshot(at: .seconds(-1))
        }
        #expect(throws: AddonCPUBudget.Failure.invalidMonotonicInstant) {
            try budget.snapshot(at: .seconds(Int64.max) + .seconds(1))
        }

        #expect(try budget.snapshot(at: .seconds(2)) == before)
    }

    @Test func largestSingleChargeAndAccountingOverflowAreExplicitAndAtomic() throws {
        var budget = try AddonCPUBudget(at: .zero)
        let charged = try budget.charge(
            cpuNanoseconds: .max,
            at            : .zero
        )
        let bounded = try budget.charge(
            cpuNanoseconds: 100_000_000,
            at            : .zero
        )
        let beforeOverflow = try budget.snapshot(at: .zero)

        #expect(charged.debt + .milliseconds(100) == AddonCPUBudget.maximumDebt)
        #expect(bounded.debt == AddonCPUBudget.maximumDebt)
        #expect(throws: AddonCPUBudget.Failure.accountingOverflow) {
            try budget.charge(
                cpuNanoseconds: 1,
                at            : .zero
            )
        }
        #expect(try budget.snapshot(at: .zero) == beforeOverflow)
    }

    @Test func laterOverflowDoesNotCommitRefillOrClock() throws {
        var budget = try AddonCPUBudget(at: .zero)
        _ = try budget.charge(
            cpuNanoseconds: .max,
            at            : .zero
        )
        _ = try budget.charge(
            cpuNanoseconds: 100_000_000,
            at            : .zero
        )
        let beforeOverflow = try budget.snapshot(at: .zero)

        #expect(throws: AddonCPUBudget.Failure.accountingOverflow) {
            try budget.charge(
                cpuNanoseconds: 5_000_001,
                at            : .seconds(1)
            )
        }
        #expect(try budget.snapshot(at: .zero) == beforeOverflow)
    }
}
