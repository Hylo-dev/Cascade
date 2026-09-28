//
//  ProcessMetricsCoordinator.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricsCoordinator owns observational registrations and their interval
/// continuity. It serializes synchronous reads without creating a task or timer.
actor ProcessMetricsCoordinator {
    enum Failure: Error, Equatable {
        case invalidBinding, tokenConflict, pidConflict, capacityReached
        case invalidEventDrivenOwner, ownershipConflict, accountCapacityReached
        case invalidMonotonicTime, invalidSampleReason
        case invalidAttribution, duplicateAttribution
        case ledgerInconsistency
    }

    enum Registration: Equatable, Sendable {
        case registered, duplicate
    }

    typealias Read = @Sendable (ProcessMetricBinding) -> ProcessMetricReadResult

    private struct Row: Sendable {
        let binding         : ProcessMetricBinding
        let eventDrivenOwner: VerifiedAddonIdentity?
        var reducer         : ProcessMetricsReducer
    }

    private enum Account: Sendable {
        case active(AddonCPUBudget)
        case failed(AddonCPUBudget)
    }

    private static let maximumCapacity = 1_024
    private static let minimumCadence  = Duration.seconds(1)
    private static let maximumCadence  = Duration.nanoseconds(Int64.max / 2)
    private static let maximumInstant  = Duration.nanoseconds(Int64.max)

    private let capacity         : Int
    private let accountCapacity  : Int
    private let cadence          : Duration
    private let attributionLedger: ServiceCPUAttributionLedger?
    private let read             : Read
    private var rows           : [Row] = []
    private var deadline       : Duration?
    private var lastInstant    : Duration?
    private var accounts       : [VerifiedAddonIdentity: Account] = [:]

    /// ProcessMetricsCoordinator clamps row and retained-account capacities to
    /// 1,024 and cadence so configuration can never sample above 1 Hz.
    init(
        capacity         : Int = 4,
        accountCapacity  : Int = 32,
        cadence          : Duration = .seconds(1),
        attributionLedger: ServiceCPUAttributionLedger? = nil,
        read             : @escaping Read = { ProcessMetricsReader().read($0) }
    ) {
        self.capacity          = min(max(0, capacity), Self.maximumCapacity)
        self.accountCapacity   = min(max(0, accountCapacity), Self.maximumCapacity)
        self.cadence           = min(max(Self.minimumCadence, cadence), Self.maximumCadence)
        self.attributionLedger = attributionLedger
        self.read              = read
    }

    var registeredCount: Int { rows.count }

    /// nextDeadline exposes the common absolute monotonic wakeup. The coordinator
    /// deliberately installs no timer or task of its own.
    var nextDeadline: Duration? {
        deadline
    }

    @discardableResult
    /// register retains a valid, unconflicted binding without reading it. An
    /// exact duplicate leaves its reducer and the common deadline untouched.
    func register(
        _ binding       : ProcessMetricBinding,
        at instant      : Duration,
        eventDrivenOwner: VerifiedAddonIdentity? = nil
    ) throws -> Registration {
        let now = try validated(instant)
        guard binding.isValid,
              binding.token != ProcessMetricBinding.zeroUUID,
              binding.clockDomain != ProcessMetricBinding.zeroUUID else {
            throw Failure.invalidBinding
        }
        if let eventDrivenOwner {
            let publisher = eventDrivenOwner.publisher
            let publisherBytes = publisher.utf8.count
            guard publisherBytes > 0, publisherBytes <= 512,
                  !publisher.allSatisfy(\.isWhitespace) else {
                throw Failure.invalidEventDrivenOwner
            }
        }
        if let attributionLedger {
            guard let eventDrivenOwner,
                  attributionLedger.authorizedOwners.contains(eventDrivenOwner) else {
                throw Failure.invalidEventDrivenOwner
            }
        }
        if let row = rows.first(where: { $0.binding == binding }) {
            guard row.eventDrivenOwner == eventDrivenOwner else {
                throw Failure.ownershipConflict
            }
            if let attributionLedger, let eventDrivenOwner {
                do {
                    guard try attributionLedger.register(
                        binding,
                        physicalOwner: eventDrivenOwner
                    ) == false else { throw Failure.ledgerInconsistency }
                } catch {
                    throw Failure.ledgerInconsistency
                }
            }
            lastInstant = now
            return .duplicate
        }
        guard !rows.contains(where: { $0.binding.token == binding.token }) else {
            throw Failure.tokenConflict
        }
        guard !rows.contains(where: { $0.binding.pid == binding.pid }) else {
            throw Failure.pidConflict
        }
        guard rows.count < capacity else { throw Failure.capacityReached }
        var preparedAccounts: [VerifiedAddonIdentity: AddonCPUBudget] = [:]
        let requiredOwners: [VerifiedAddonIdentity]
        if let attributionLedger {
            requiredOwners = attributionLedger.authorizedOwners
        } else {
            requiredOwners = eventDrivenOwner.map { [$0] } ?? []
        }
        for owner in requiredOwners where accounts[owner] == nil {
            guard accounts.count + preparedAccounts.count < accountCapacity else {
                throw Failure.accountCapacityReached
            }
            preparedAccounts[owner] = try AddonCPUBudget(at: now)
        }
        if let attributionLedger, let eventDrivenOwner {
            do {
                guard try attributionLedger.register(
                    binding,
                    physicalOwner: eventDrivenOwner
                ) else { throw Failure.ledgerInconsistency }
            } catch {
                throw Failure.ledgerInconsistency
            }
        }
        for (owner, budget) in preparedAccounts {
            accounts[owner] = .active(budget)
        }

        if rows.isEmpty { deadline = now + cadence }
        rows.append(Row(
            binding         : binding,
            eventDrivenOwner: eventDrivenOwner,
            reducer         : ProcessMetricsReducer(binding: binding)
        ))
        lastInstant = now
        return .registered
    }

    /// unregister removes only the exact binding supplied by its owner.
    func unregister(_ binding: ProcessMetricBinding) -> Bool {
        guard let index = rows.firstIndex(where: { $0.binding == binding }) else { return false }
        if let attributionLedger, !attributionLedger.unregister(binding) { return false }
        rows.remove(at: index)
        if rows.isEmpty { deadline = nil }
        return true
    }

    /// sampleIfDue gates periodic work on the common deadline and advances from
    /// the current time, which prevents a catch-up burst after a delayed wakeup.
    func sampleIfDue(
        at instant  : Duration,
        attribution: [ProcessMetricDelegatedAttribution] = []
    ) throws -> ProcessMetricBatch? {
        guard attributionLedger == nil || attribution.isEmpty else {
            throw Failure.invalidAttribution
        }
        let now = try validated(instant)
        guard let deadline, !rows.isEmpty else {
            lastInstant = now
            return nil
        }
        guard now >= deadline else {
            lastInstant = now
            return nil
        }

        let recipients = try preparedRecipients(attribution, at: now)

        let batch = try sample(
            reason    : .periodic,
            instant   : instant,
            recipients: recipients
        )
        self.deadline = rows.isEmpty ? nil : now + cadence
        lastInstant = now
        return batch
    }

    /// sampleAll permits an explicit lifecycle or pressure observation without
    /// moving the already armed periodic deadline.
    func sampleAll(
        reason     : ProcessMetricSampleReason,
        at instant : Duration,
        attribution: [ProcessMetricDelegatedAttribution] = []
    ) throws -> ProcessMetricBatch {
        guard attributionLedger == nil || attribution.isEmpty else {
            throw Failure.invalidAttribution
        }
        let now = try validated(instant)
        guard reason != .periodic else { throw Failure.invalidSampleReason }
        let recipients = try preparedRecipients(attribution, at: now)
        let batch = try sample(
            reason    : reason,
            instant   : instant,
            recipients: recipients
        )
        lastInstant = now
        return batch
    }

    /// resetAfterWake breaks interval continuity and rearms one future periodic
    /// sample. Rows retired by an identity-terminal read are already absent.
    func resetAfterWake(at instant: Duration) throws {
        let now = try validated(instant)
        attributionLedger?.resetAfterWake()
        for index in rows.indices { rows[index].reducer.reset() }
        deadline = rows.isEmpty ? nil : now + cadence
        lastInstant = now
    }

    /// preparedRecipients checks every host-supplied pair before a native read or
    /// reducer mutation. New retained accounts commit together only after all
    /// exact bindings, identity bounds and budget initializers succeed.
    private func preparedRecipients(
        _ attribution: [ProcessMetricDelegatedAttribution],
        at instant  : Duration
    ) throws -> [UUID: [VerifiedAddonIdentity]] {
        guard attribution.count <= capacity else { throw Failure.invalidAttribution }
        var recipients: [UUID: [VerifiedAddonIdentity]] = [:]
        var preparedAccounts: [VerifiedAddonIdentity: AddonCPUBudget] = [:]
        for entry in attribution {
            guard entry.consumers.count <= accountCapacity,
                  rows.contains(where: { $0.binding == entry.binding }) else {
                throw Failure.invalidAttribution
            }
            guard recipients[entry.binding.token] == nil else {
                throw Failure.duplicateAttribution
            }
            var unique: [VerifiedAddonIdentity] = []
            unique.reserveCapacity(entry.consumers.count)
            for consumer in entry.consumers {
                let publisher = consumer.publisher
                let publisherBytes = publisher.utf8.count
                guard publisherBytes > 0, publisherBytes <= 512,
                      !publisher.allSatisfy(\.isWhitespace) else {
                    throw Failure.invalidEventDrivenOwner
                }
                if !unique.contains(consumer) { unique.append(consumer) }
                if accounts[consumer] == nil, preparedAccounts[consumer] == nil {
                    guard accounts.count + preparedAccounts.count < accountCapacity else {
                        throw Failure.accountCapacityReached
                    }
                    preparedAccounts[consumer] = try AddonCPUBudget(at: instant)
                }
            }
            recipients[entry.binding.token] = unique
        }
        for (owner, budget) in preparedAccounts {
            accounts[owner] = .active(budget)
        }
        return recipients
    }

    /// sample reads every row at most once and retires only identity-terminal
    /// results after including their unavailable reduction in the batch.
    private func sample(
        reason    : ProcessMetricSampleReason,
        instant   : Duration,
        recipients: [UUID: [VerifiedAddonIdentity]]
    ) throws -> ProcessMetricBatch {
        var samples: [ProcessMetricCoordinatedSample] = []
        samples.reserveCapacity(rows.count)
        var ownerOrder: [VerifiedAddonIdentity] = []
        ownerOrder.reserveCapacity(accounts.count)
        var incompleteOwners: Set<VerifiedAddonIdentity> = []
        var overspentOwners: Set<VerifiedAddonIdentity> = []
        var finalSnapshots: [VerifiedAddonIdentity: AddonCPUBudget.Snapshot] = [:]
        var index = 0
        while index < rows.count {
            let binding   = rows[index].binding
            let owner     = rows[index].eventDrivenOwner
            let observation: (ProcessMetricReadResult, ProcessMetricReduction, [VerifiedAddonIdentity])
            if let attributionLedger {
                do {
                    observation = try attributionLedger.withObservation(for: binding) { delegatedOwners in
                        let result = read(binding)
                        let reduction = rows[index].reducer.consume(result)
                        return (result, reduction, delegatedOwners)
                    }
                } catch {
                    throw Failure.ledgerInconsistency
                }
            } else {
                let result = read(binding)
                let reduction = rows[index].reducer.consume(result)
                observation = (result, reduction, recipients[binding.token] ?? [])
            }
            let (result, reduction, delegatedOwners) = observation
            var chargedOwners = delegatedOwners
            if let owner, !chargedOwners.contains(owner) { chargedOwners.insert(owner, at: 0) }
            samples.append(ProcessMetricCoordinatedSample(
                binding      : binding,
                reduction    : reduction,
                chargedOwners: chargedOwners
            ))
            for chargedOwner in chargedOwners {
                if !ownerOrder.contains(chargedOwner) { ownerOrder.append(chargedOwner) }
                if let interval = reduction.interval {
                    charge(
                        interval.cpuNanoseconds,
                        to            : chargedOwner,
                        at            : instant,
                        finalSnapshots: &finalSnapshots,
                        overspentOwners: &overspentOwners
                    )
                } else {
                    incompleteOwners.insert(chargedOwner)
                }
            }
            if result == .unavailable(.identityMismatch) || result == .unavailable(.exited) {
                if let attributionLedger, !attributionLedger.unregister(binding) {
                    throw Failure.ledgerInconsistency
                }
                rows.remove(at: index)
            } else {
                index += 1
            }
        }
        if rows.isEmpty { deadline = nil }
        let accounting = ownerOrder.map { owner in
            let result: ProcessMetricCPUAccountingResult
            switch accounts[owner] {
            case .failed, nil:
                result = .accountingFailed
            case .active:
                if incompleteOwners.contains(owner) {
                    result = .incomplete
                } else if let snapshot = finalSnapshots[owner] {
                    result = .complete(snapshot)
                } else {
                    result = .accountingFailed
                }
            }
            let classification: ProcessMetricCPUViolationResult
            switch accounts[owner] {
            case .failed, nil:
                classification = .unavailable
            case .active:
                if overspentOwners.contains(owner) {
                    classification = .moderate
                } else if incompleteOwners.contains(owner) {
                    classification = .unavailable
                } else {
                    classification = .noNewViolation
                }
            }
            return ProcessMetricCPUAccounting(
                owner         : owner,
                result        : result,
                classification: classification
            )
        }
        return ProcessMetricBatch(
            reason       : reason,
            sampledAt    : instant,
            samples      : samples,
            cpuAccounting: accounting
        )
    }

    /// charge commits one freshly reduced interval and latches arithmetic failure
    /// so a later batch cannot present an account whose missing debit was forgotten.
    private func charge(
        _ cpuNanoseconds: UInt64,
        to owner         : VerifiedAddonIdentity,
        at instant       : Duration,
        finalSnapshots   : inout [VerifiedAddonIdentity: AddonCPUBudget.Snapshot],
        overspentOwners  : inout Set<VerifiedAddonIdentity>
    ) {
        guard case .active(var budget) = accounts[owner] else { return }
        do {
            let snapshot = try budget.charge(
                cpuNanoseconds: cpuNanoseconds,
                at            : instant
            )
            accounts[owner] = .active(budget)
            finalSnapshots[owner] = snapshot
            if cpuNanoseconds > 0, snapshot.exceeded {
                overspentOwners.insert(owner)
            }
        } catch {
            accounts[owner] = .failed(budget)
            finalSnapshots[owner] = nil
        }
    }

    /// validated preserves Duration precision while bounding the value before
    /// deadline arithmetic. Reserving cadence headroom makes addition safe.
    private func validated(_ instant: Duration) throws -> Duration {
        guard instant >= .zero,
              instant <= Self.maximumInstant - cadence,
              lastInstant.map({ instant >= $0 }) ?? true else {
            throw Failure.invalidMonotonicTime
        }
        return instant
    }
}
