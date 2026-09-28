//
//  AddonCPUBudget.swift
//  CascadeKit
//

import Foundation

/// AddonCPUBudget accounts one addon's observed CPU across jobs and provider
/// restarts. It is arithmetic only: advancing time accrues credit but does not
/// establish that any CPU measurement was available or authentic.
struct AddonCPUBudget: Sendable {
    enum Failure: Error, Equatable {
        case invalidMonotonicInstant, accountingOverflow
    }

    /// Snapshot describes the signed accounting balance at one accepted instant.
    struct Snapshot: Equatable, Sendable {
        let balance : Duration
        let available: Duration
        let debt    : Duration

        var exceeded: Bool { balance < .zero }
    }

    private static let capacity       = Duration.milliseconds(100)
    private static let refillDivisor  = 200
    private static let maximumInstant = Duration.nanoseconds(Int64.max)

    /// maximumDebt bounds debt at the largest exact CPU charge this value accepts.
    static let maximumDebt = Duration(
        secondsComponent    : Int64(UInt64.max / 1_000_000_000),
        attosecondsComponent: Int64(UInt64.max % 1_000_000_000) * 1_000_000_000
    )

    private var balance        : Duration = Self.capacity
    private var lastObservation: Duration

    /// init starts a shared budget fully credited at a trusted monotonic instant.
    init(at instant: Duration) throws {
        guard instant >= .zero, instant <= Self.maximumInstant else {
            throw Failure.invalidMonotonicInstant
        }
        lastObservation = instant
    }

    /// snapshot lazily accrues credit at an observation instant without charging CPU.
    mutating func snapshot(at instant: Duration) throws -> Snapshot {
        try advance(to: instant)
        return currentSnapshot()
    }

    /// charge first accrues elapsed credit, then debits the known CPU measurement.
    /// Overspend remains debt so later jobs cannot receive forgiven CPU time.
    @discardableResult
    mutating func charge(
        cpuNanoseconds: UInt64,
        at instant: Duration
    ) throws -> Snapshot {
        let now = try validated(instant)
        let creditedBalance = refilledBalance(at: now)
        let candidateBalance = creditedBalance - Self.duration(nanoseconds: cpuNanoseconds)
        guard candidateBalance + Self.maximumDebt >= .zero else {
            throw Failure.accountingOverflow
        }
        balance = candidateBalance
        lastObservation = now
        return currentSnapshot()
    }

    /// advance commits a validated refill with no implied CPU measurement.
    private mutating func advance(to instant: Duration) throws {
        let now = try validated(instant)
        balance = refilledBalance(at: now)
        lastObservation = now
    }

    /// validated rejects values before arithmetic so failures leave the account intact.
    private func validated(_ instant: Duration) throws -> Duration {
        guard instant >= .zero,
              instant <= Self.maximumInstant,
              instant >= lastObservation else {
            throw Failure.invalidMonotonicInstant
        }
        return instant
    }

    /// refilledBalance preserves Duration precision; division rounds down only below
    /// one attosecond, so it never creates credit that elapsed time did not earn.
    private func refilledBalance(at instant: Duration) -> Duration {
        min(
            Self.capacity,
            balance + ((instant - lastObservation) / Self.refillDivisor)
        )
    }

    /// duration converts an unsigned nanosecond measurement exactly without a
    /// narrowing conversion, including UInt64.max.
    private static func duration(nanoseconds: UInt64) -> Duration {
        Duration(
            secondsComponent    : Int64(nanoseconds / 1_000_000_000),
            attosecondsComponent: Int64(nanoseconds % 1_000_000_000) * 1_000_000_000
        )
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(
            balance  : balance,
            available: max(
                .zero,
                balance
            ),
            debt     : max(
                .zero,
                .zero - balance
            )
        )
    }
}
