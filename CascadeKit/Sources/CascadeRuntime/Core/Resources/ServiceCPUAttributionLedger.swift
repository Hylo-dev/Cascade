//
//  ServiceCPUAttributionLedger.swift
//  CascadeKit
//

import Foundation

/// ServiceCPUAttributionLedger retains the union of consumers reachable while
/// each physical process interval is open. The host supplies only canonical,
/// authorized interests; this ledger neither grants access nor measures CPU.
final class ServiceCPUAttributionLedger: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case invalidOwnerDomain, invalidOwner, conflictingInterest, interestCapacityReached
        case invalidBinding, bindingConflict, tokenConflict, pidConflict, bindingCapacityReached
        case unregisteredBinding
    }

    private struct Interest {
        let consumer: Int
        let provider: Int
    }

    private struct Row {
        let binding      : ProcessMetricBinding
        let physicalOwner: Int
        var pending      : UInt32
    }

    private let lock = NSLock()
    let authorizedOwners: [VerifiedAddonIdentity]
    private let ownerIndexes   : [VerifiedAddonIdentity: Int]
    private let maximumBindings: Int
    private let maximumInterests: Int
    private var interests: [UUID: Interest] = [:]
    private var rows: [Row] = []

    /// init fixes a small verified identity domain. Repeated addon IDs cannot
    /// appear in the canonical catalog, even with the same publisher.
    init(
        authorizedOwners: [VerifiedAddonIdentity],
        maximumBindings: Int = 32,
        maximumInterests: Int = 256
    ) throws {
        guard authorizedOwners.count <= 32 else { throw Failure.invalidOwnerDomain }
        var owners: [VerifiedAddonIdentity] = []
        var indexes: [VerifiedAddonIdentity: Int] = [:]
        var addonIDs: Set<String> = []
        for owner in authorizedOwners {
            let publisher = owner.publisher
            let bytes = publisher.utf8.count
            guard bytes > 0, bytes <= 512, !publisher.allSatisfy(\.isWhitespace) else {
                throw Failure.invalidOwnerDomain
            }
            let addonID = owner.addonID.rawValue
            guard addonIDs.insert(addonID).inserted else { throw Failure.invalidOwnerDomain }
            indexes[owner] = owners.count
            owners.append(owner)
        }
        self.authorizedOwners  = owners
        ownerIndexes          = indexes
        self.maximumBindings  = min(max(0, maximumBindings), 32)
        self.maximumInterests = min(max(0, maximumInterests), 256)
    }

    /// addInterest commits one canonical directed provider-to-consumer edge.
    /// Exact duplicate IDs are idempotent; an ID cannot change its endpoints.
    @discardableResult
    func addInterest(
        _ id    : UUID,
        consumer: VerifiedAddonIdentity,
        provider: VerifiedAddonIdentity
    ) throws -> Bool {
        try lock.withLock {
            guard let consumerIndex = ownerIndexes[consumer],
                  let providerIndex = ownerIndexes[provider] else {
                throw Failure.invalidOwner
            }
            if let existing = interests[id] {
                guard existing.consumer == consumerIndex, existing.provider == providerIndex else {
                    throw Failure.conflictingInterest
                }
                return false
            }
            guard interests.count < maximumInterests else {
                throw Failure.interestCapacityReached
            }
            interests[id] = Interest(consumer: consumerIndex, provider: providerIndex)
            captureCurrentReachability()
            return true
        }
    }

    /// removeInterest retires one canonical interest, preserving other IDs for
    /// the same edge and all recipient history from the open interval.
    @discardableResult
    func removeInterest(_ id: UUID) -> Bool {
        lock.withLock {
            guard interests.removeValue(forKey: id) != nil else { return false }
            captureCurrentReachability()
            return true
        }
    }

    /// register seeds a new physical interval from the currently active graph.
    /// An exact duplicate preserves pending recipients and cannot change owner.
    @discardableResult
    func register(
        _ binding      : ProcessMetricBinding,
        physicalOwner: VerifiedAddonIdentity
    ) throws -> Bool {
        try lock.withLock {
            guard valid(binding) else { throw Failure.invalidBinding }
            guard let ownerIndex = ownerIndexes[physicalOwner] else {
                throw Failure.invalidOwner
            }
            if let row = rows.first(where: { $0.binding == binding }) {
                guard row.physicalOwner == ownerIndex else { throw Failure.bindingConflict }
                return false
            }
            guard !rows.contains(where: { $0.binding.token == binding.token }) else {
                throw Failure.tokenConflict
            }
            guard !rows.contains(where: { $0.binding.pid == binding.pid }) else {
                throw Failure.pidConflict
            }
            guard rows.count < maximumBindings else { throw Failure.bindingCapacityReached }
            rows.append(Row(
                binding      : binding,
                physicalOwner: ownerIndex,
                pending      : reachability(from: ownerIndex)
            ))
            return true
        }
    }

    /// unregister removes only the exact physical incarnation. Canonical
    /// interests remain even when a provider process exits or restarts.
    @discardableResult
    func unregister(_ binding: ProcessMetricBinding) -> Bool {
        lock.withLock {
            guard let index = rows.firstIndex(where: { $0.binding == binding }) else { return false }
            rows.remove(at: index)
            return true
        }
    }

    /// resetAfterWake discards pre-wake interval overlap but retains the live
    /// graph, so the next baseline begins with current consumers only.
    func resetAfterWake() {
        lock.withLock {
            for index in rows.indices {
                rows[index].pending = reachability(from: rows[index].physicalOwner)
            }
        }
    }

    /// withObservation holds the membership lock over one synchronous native
    /// read and reducer commit. The body must never await or reenter the ledger.
    /// A throw leaves recipient history intact; a consumed unavailable result
    /// is a successful observation and starts the next interval at the live graph.
    func withObservation<T>(
        for binding: ProcessMetricBinding,
        body       : ([VerifiedAddonIdentity]) throws -> T
    ) throws -> T {
        try lock.withLock {
            guard let index = rows.firstIndex(where: { $0.binding == binding }) else {
                throw Failure.unregisteredBinding
            }
            let pending = rows[index].pending
            let recipients = authorizedOwners.indices.compactMap { ownerIndex in
                pending & bit(ownerIndex) == 0 ? nil : authorizedOwners[ownerIndex]
            }
            let result = try body(recipients)
            rows[index].pending = reachability(from: rows[index].physicalOwner)
            return result
        }
    }

    private func valid(_ binding: ProcessMetricBinding) -> Bool {
        binding.isValid && binding.token != ProcessMetricBinding.zeroUUID &&
            binding.clockDomain != ProcessMetricBinding.zeroUUID
    }

    private func bit(_ index: Int) -> UInt32 { UInt32(1) << UInt32(index) }

    /// captureCurrentReachability unions instantaneous closures, never the
    /// closure of every edge seen during the interval; that would invent a
    /// chain whose two edges were never active together.
    private func captureCurrentReachability() {
        for index in rows.indices {
            rows[index].pending |= reachability(from: rows[index].physicalOwner)
        }
    }

    private func reachability(from origin: Int) -> UInt32 {
        var edges = Array(repeating: UInt32(0), count: authorizedOwners.count)
        for interest in interests.values {
            edges[interest.provider] |= bit(interest.consumer)
        }
        var reachable = bit(origin)
        var previous: UInt32
        repeat {
            previous = reachable
            for ownerIndex in authorizedOwners.indices where reachable & bit(ownerIndex) != 0 {
                reachable |= edges[ownerIndex]
            }
        } while reachable != previous
        return reachable & ~bit(origin)
    }
}
