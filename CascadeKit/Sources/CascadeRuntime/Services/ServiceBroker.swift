import CascadeContracts
import Foundation
import OSLog

public enum ServiceDecision: Equatable, Sendable {
    case startSource(UUID)
    case stopSource(UUID)
    case wakeConsumer(VerifiedAddonIdentity)
}

public enum ServiceRequestOutcome: Equatable, Sendable {
    case pending, dispatched, completed(ServiceResponse), unknown, unsent
}

public struct ServiceAcquisition: Sendable {
    public let grant: Grant
    public let interestID: UUID
    public let sourceID: UUID
    public let decisions: [ServiceDecision]
    let effectiveDeadline: Duration
    fileprivate let createdInterest: Bool
    fileprivate let createdSource: Bool
    fileprivate let rearmedSource: Bool
    // Immutable canonical identity for disposition after the initiating interest is gone.
    fileprivate let sourceKey: ServiceRegistry.SourceKey

    /// createdNewConsumerInterest reports whether this acquisition established a
    /// new canonical consumer relationship rather than reusing an existing one.
    var createdNewConsumerInterest: Bool {
        createdInterest
    }
}

public struct ServiceWork: Equatable, Sendable {
    public let id: UUID
    public let sourceID: UUID
    public let invocation: ServiceInvocation
    let effectiveDeadline: Duration
}

public struct ServicePathAdmission: Sendable {
    public let id: UUID
    public let providers: [VerifiedAddonIdentity]
}

public struct ServiceInvalidation: Sendable {
    public let affectedFeatures: Set<ResolvedFeature>
    public let decisions: [ServiceDecision]
}

public struct ServiceSourceDescriptor: Equatable, Sendable {
    public let provider: VerifiedAddonIdentity
    public let digest: String
    public let contractVersion: String
    public let serviceID: String
    public let partition: String
    public let featureID: String
    public let operation: String
}

/// Value projections only. Callers must ask the broker again after suspension.
struct ServiceSubscriptionBinding: Sendable {
    let grant: Grant
    let permissionID: UUID
    let interestID: UUID
    let sourceID: UUID
    let key: ServiceRegistry.SourceKey
    let deadline: Duration
}

struct ServiceSourceBinding: Sendable {
    let sourceID: UUID
    let key: ServiceRegistry.SourceKey
    let deadline: Duration
    let startConsumed: Bool
    let restartRequired: Bool
}

/// ServiceInvocationBinding is a one-call projection of canonically consumed work.
struct ServiceInvocationBinding: Sendable {
    let owner     : VerifiedAddonIdentity
    let source    : ServiceSourceDescriptor
    let invocation: ServiceInvocation
}

/// Bounded host rules and decisions. An adapter must authenticate sessions, execute decisions,
/// and report observed process exit separately. No addon code runs in this actor.
public actor ServiceBroker {
    struct CompletionPreparation: Sendable {
        fileprivate let workID: UUID
        fileprivate let token: UUID
    }

    private struct PendingCompletion: Sendable {
        let token: UUID
        let response: ServiceResponse
    }

    private static let logger = Logger(
        subsystem: "Cascade",
        category: "ServiceBroker"
    )
    let governor: ResourceGovernor
    private let resourceAccess: any RuntimeResourceAccess
    private let cpuAttributionLedger: ServiceCPUAttributionLedger?
    let limits: ServiceBrokerLimits
    var registry = ServiceRegistry()
    var permissions = PermissionStore()
    var bindings = ServiceBindingStore()
    var leases = LeaseStore()
    var paths: [UUID: [ResourceReservation]] = [:]
    // Admission never queues tasks. Concurrent admissions receive bounded backpressure.
    var admitting = false
    var revision: UInt64 = 0
    private var isRevisionExhausted = false
    private var pendingCompletions: [UUID: PendingCompletion] = [:]

    public init(
        governor: ResourceGovernor = ResourceGovernor(),
        limits  : ServiceBrokerLimits = .init()
    ) {
        self.governor = governor
        resourceAccess = governor
        cpuAttributionLedger = nil
        self.limits = limits
    }

    /// init accepts a forwarding seam only when it targets the same canonical governor.
    /// AddonRuntime uses this to test suspension after real accounting has completed.
    init(
        governor                : ResourceGovernor,
        limits                  : ServiceBrokerLimits = .init(),
        resourceAccess          : any RuntimeResourceAccess,
        cpuAttributionLedger    : ServiceCPUAttributionLedger? = nil,
        initialAuthorityRevision: UInt64 = 0
    ) {
        precondition(resourceAccess.resourceGovernorTarget === governor)
        self.governor = governor
        self.resourceAccess = resourceAccess
        self.cpuAttributionLedger = cpuAttributionLedger
        self.limits = limits
        revision = initialAuthorityRevision
    }

    static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(code: code, reason: "The host service policy rejected this operation.")
    }

    private func startAdmission() throws -> UInt64 {
        guard !admitting, !isRevisionExhausted else { throw Self.failure(.resourceDenied) }
        admitting = true
        return revision
    }

    private func checkRevision(_ expected: UInt64) throws {
        guard !isRevisionExhausted, revision == expected else { throw Self.failure(.sessionRevoked) }
        try Task.checkCancellation()
    }

    static func nextAuthorityRevision(after current: UInt64) -> UInt64? {
        guard current < UInt64.max else { return nil }
        return current + 1
    }

    static func advancedAuthorityState(
        revision   : UInt64,
        isExhausted: Bool
    ) -> (revision: UInt64, isExhausted: Bool) {
        guard !isExhausted, let next = nextAuthorityRevision(after: revision) else {
            return (revision, true)
        }
        return (next, false)
    }

    private func advanceRevision() {
        let state = Self.advancedAuthorityState(
            revision   : revision,
            isExhausted: isRevisionExhausted
        )
        revision = state.revision
        isRevisionExhausted = state.isExhausted
    }

    private func release(_ reservations: [ResourceReservation]) async {
        for value in reservations {
            do {
                try await resourceAccess.release(
                    value.id,
                    owner: value.owner
                )
            }
            catch {
                let message = String(describing: error)
                Self.logger.error("Canonical service reservation release failed: \(message, privacy: .public)")
            }
        }
        await reclaimTerminalResultCapacity()
    }

    /// takeResultReduction consumes a flag before suspension and returns only bounded refund metadata.
    /// The record's response is not captured across the governor await, and removed records stay removed.
    private func takeResultReduction(_ key: LeaseStore.RequestKey) -> (ResourceReservation, Int)? {
        guard var record = leases.requests[key], record.needsResultReduction else { return nil }
        let resultBytes: Int
        switch record.outcome {
        case .completed(let response): resultBytes = response.payload.count
        case .unknown, .unsent: resultBytes = 0
        case .pending, .dispatched: return nil
        }
        record.needsResultReduction = false
        leases.requests[key] = record
        return (record.reservation, record.invocation.payload.count + 8_192 + resultBytes)
    }

    /// reclaimTerminalResultCapacity drains flags on existing events, never through another task or timer.
    /// The snapshot contains at most one key per retained request, covered by its 8 KiB metadata allowance.
    private func reclaimTerminalResultCapacity() async {
        let keys = leases.requests.compactMap { key, record in record.needsResultReduction ? key : nil }
        for key in keys {
            guard let (reservation, bytes) = takeResultReduction(key) else { continue }
            // Expiry/shutdown can release this ID during the await. False safely leaves canonical state alone.
            _ = await resourceAccess.reduceStateReservation(
                reservation.id,
                owner: reservation.owner,
                toBytes: bytes
            )
        }
    }

    public func authorize(_ permission: HostServicePermission) async throws -> UUID {
        try permission.validate()
        let key = ServiceBindingStore.key(permission)
        guard bindings.permissions[key] == nil else { throw Self.failure(.permissionDenied) }
        guard permissions.entries.count < limits.permissions else { throw Self.failure(.resourceDenied) }
        let expected = try startAdmission()
        defer { admitting = false }
        let reservation = try await resourceAccess.admit(
            .state(bytes: 4_096),
            owner: permission.consumer.addonID
        )
        do { try checkRevision(expected) } catch { await release([reservation]); throw error }
        let id = UUID()
        permissions.entries[id] = .init(value: permission, reservation: reservation)
        bindings.permissions[key] = id
        return id
    }

    public func registerSession(identity: VerifiedAddonIdentity) async throws -> ServiceSession {
        try await registerSession(identity: identity, generation: ConnectionGeneration())
    }

    /// Trusted composition for a fresh canonical 1.3 publication connection only.
    func registerSession(identity: VerifiedAddonIdentity, generation: ConnectionGeneration) async throws -> ServiceSession {
        try ServiceRegistry.validateIdentity(identity)
        guard !registry.sessions.values.contains(where: { $0.identity == identity }) else {
            throw Self.failure(.permissionDenied)
        }
        guard registry.sessions.count < limits.sessions else { throw Self.failure(.resourceDenied) }
        let expected = try startAdmission()
        defer { admitting = false }
        let reservation = try await resourceAccess.admit(
            .state(bytes: 1_024),
            owner: identity.addonID
        )
        do { try checkRevision(expected) } catch { await release([reservation]); throw error }
        let session = ServiceSession()
        registry.sessions[session] = .init(identity: identity, generation: generation,
            reservation: reservation)
        registry.pendingWakes.remove(identity)
        return session
    }

    private func validTime(_ now: RuntimeInstant) throws {
        guard now.wall.timeIntervalSince1970.isFinite, now.monotonic >= .zero,
              now.monotonic <= .seconds(315_360_000) else { throw Self.failure(.invalidPayload) }
    }

    public func acquire(session: ServiceSession, requirementID: String, scope: ServiceScope,
        now: RuntimeInstant, lifetime: Duration) async throws -> ServiceAcquisition {
        try await acquire(
            session            : session,
            requirementID      : requirementID,
            scope              : scope,
            now                : now,
            lifetime           : lifetime,
            allowNewSourceStart: true,
            allowNewConsumerInterest: true
        )
    }

    /// acquire permits a paused host owner to reuse a fully started source while
    /// refusing the broker's fresh or rearmed provider start before any reservation.
    func acquire(
        session            : ServiceSession,
        requirementID      : String,
        scope              : ServiceScope,
        now                : RuntimeInstant,
        lifetime           : Duration,
        allowNewSourceStart: Bool,
        allowNewConsumerInterest: Bool = true
    ) async throws -> ServiceAcquisition {
        try validTime(now)
        try scope.validate()
        guard lifetime >= .nanoseconds(1), lifetime <= .seconds(3_600) else {
            throw Self.failure(.invalidPayload)
        }
        guard let connection = registry.sessions[session] else { throw Self.failure(.sessionRevoked) }
        let key = ServiceBindingStore.Key(consumer: connection.identity, requirementID: requirementID,
            featureID: scope.featureID, operation: scope.operation)
        guard let permissionID = bindings.permissions[key], let entry = permissions.entries[permissionID] else {
            throw Self.failure(.permissionDenied)
        }
        guard leases.grants.count < 1_024,
              leases.grants.values.filter({ $0.lease.grant.owner == connection.identity.addonID }).count
                < limits.grantsPerOwner else { throw Self.failure(.resourceDenied) }
        let oldInterest = registry.interests.values.first { $0.permissionID == permissionID }
        if let oldInterest, oldInterest.deadline <= now.monotonic { throw Self.failure(.deadlineExceeded) }
        guard oldInterest != nil || registry.interests.count < limits.interests else {
            throw Self.failure(.resourceDenied)
        }
        guard oldInterest != nil || allowNewConsumerInterest else {
            throw Self.failure(.resourceDenied)
        }
        let sourceKey = ServiceRegistry.SourceKey(entry.value)
        let oldSource = registry.sources.values.first { $0.key == sourceKey }
        guard oldSource != nil || registry.sources.count < limits.sources else {
            throw Self.failure(.resourceDenied)
        }
        guard allowNewSourceStart ||
              (oldSource?.startConsumed == true && oldSource?.restartRequired == false) else {
            throw Self.failure(.resourceDenied)
        }
        let expected = try startAdmission()
        defer { admitting = false }
        var reserved: [ResourceReservation] = []
        do {
            let sourceReservation: ResourceReservation?
            if oldSource == nil {
                sourceReservation = try await resourceAccess.admit(
                    .state(bytes: 2_048),
                    owner: sourceKey.provider.addonID
                )
                reserved.append(sourceReservation!)
            } else { sourceReservation = nil }
            let interestReservation: ResourceReservation?
            if oldInterest == nil {
                interestReservation = try await resourceAccess.admit(
                    .state(bytes: 2_048),
                    owner: connection.identity.addonID
                )
                reserved.append(interestReservation!)
            } else { interestReservation = nil }
            // Every connection grant carries its own governor charge, including repeated requests.
            let grantReservation = try await resourceAccess.admit(
                .state(bytes: 1_024),
                owner: connection.identity.addonID
            )
            reserved.append(grantReservation)
            try checkRevision(expected)
            let deadline = min(now.monotonic + lifetime, oldInterest?.deadline ?? (now.monotonic + lifetime))
            let seconds = Double((deadline - now.monotonic).components.seconds)
                + Double((deadline - now.monotonic).components.attoseconds) / 1e18
            let grant = try Grant(id: UUID(), owner: connection.identity.addonID, serviceID: entry.value.serviceID,
                scope: scope, expiresAt: now.wall.addingTimeInterval(seconds), generation: connection.generation,
                cost: AddonResourceRequest(profile: .eventDriven, requestedMemoryMiB: 0,
                    maximumConcurrentWork: 1, background: .none))
            let nanoseconds = UInt64(deadline.components.seconds) * 1_000_000_000
                + UInt64(deadline.components.attoseconds / 1_000_000_000)
            let lease = try Lease(id: UUID(), grant: grant, monotonicDeadlineNanoseconds: nanoseconds)
            let sourceID = oldSource?.id ?? UUID()
            let interestID = oldInterest?.id ?? UUID()
            if oldInterest == nil, let cpuAttributionLedger {
                do {
                    _ = try cpuAttributionLedger.addInterest(
                        interestID,
                        consumer: connection.identity,
                        provider: sourceKey.provider
                    )
                } catch {
                    throw Self.failure(.resourceDenied)
                }
            }
            // The existing 2 KiB interest reservation covers this UUID/index ledger edge.
            // No await or fallible operation may separate it from canonical publication.
            if let sourceReservation {
                registry.sources[sourceID] = .init(id: sourceID, key: sourceKey, reservation: sourceReservation)
            }
            if let interestReservation {
                registry.interests[interestID] = .init(id: interestID, permissionID: permissionID,
                    sourceID: sourceID, consumer: connection.identity, deadline: deadline,
                    reservation: interestReservation)
            }
            leases.grants[grant.id] = .init(lease: lease, session: session, permissionID: permissionID,
                interestID: interestID, deadline: deadline, reservation: grantReservation)
            let shouldStart = oldSource == nil || oldSource?.restartRequired == true
            if shouldStart, var source = registry.sources[sourceID] {
                source.restartRequired = false
                registry.sources[sourceID] = source
            }
            return ServiceAcquisition(
                grant            : grant,
                interestID       : interestID,
                sourceID         : sourceID,
                decisions        : shouldStart ? [.startSource(sourceID)] : [],
                effectiveDeadline: deadline,
                createdInterest  : oldInterest == nil,
                createdSource    : oldSource == nil,
                rearmedSource    : oldSource?.restartRequired == true,
                sourceKey        : sourceKey
            )
        } catch { await release(reserved); throw error }
    }

    /// revokePermission removes one exact permission returned to a stale runtime operation.
    func revokePermission(_ id: UUID) async {
        let (reservations, _) = invalidatePermissions([id])
        await release(reservations)
    }

    /// rollbackAcquisition returns one unexposed acquisition to its exact prior source state.
    func rollbackAcquisition(_ acquisition: ServiceAcquisition) async {
        var reservations = removeGrants([acquisition.grant.id])
        if acquisition.createdInterest,
           let interest = registry.interests.removeValue(forKey: acquisition.interestID) {
            _ = cpuAttributionLedger?.removeInterest(interest.id)
            reservations.append(interest.reservation)
        }
        if acquisition.createdSource,
           !registry.interests.values.contains(where: { $0.sourceID == acquisition.sourceID }),
           let source = registry.sources.removeValue(forKey: acquisition.sourceID) {
            reservations.append(source.reservation)
        } else if acquisition.rearmedSource {
            registry.sources[acquisition.sourceID]?.restartRequired = true
            registry.sources[acquisition.sourceID]?.startConsumed = false
        }
        advanceRevision()
        await release(reservations)
    }

    /// Called only by the runtime's current paid pending-start owner under its
    /// outer drain. That owner proves no source handoff/execution exists; a revoked
    /// initiating interest is not the authority for disposing the surviving source.
    /// False leaves ownership with the caller; absence is a conclusive disposition.
    func abandonUnhandedAcquisition(_ acquisition: ServiceAcquisition, startTransferred: Bool) async -> Bool {
        guard var source = registry.sources[acquisition.sourceID] else { return true }
        guard !isRevisionExhausted, source.key == acquisition.sourceKey else { return false }
        if let grant = leases.grants[acquisition.grant.id] {
            guard grant.interestID == acquisition.interestID, grant.lease.grant == acquisition.grant else { return false }
        }
        advanceRevision()
        source.startConsumed = false
        source.restartRequired = !startTransferred
        registry.sources[acquisition.sourceID] = source
        await release(removeGrants([acquisition.grant.id]))
        return true
    }

    /// activeGrantIDs projects bounded canonical grant authority for runtime cleanup.
    func activeGrantIDs() -> Set<UUID> {
        Set(leases.grants.keys)
    }

    /// activeSourceIDs projects the bounded canonical sources still backed by interests.
    func activeSourceIDs() -> Set<UUID> {
        Set(registry.sources.keys)
    }

    /// hasCurrentDemand reads only canonical, unexpired service interest for an
    /// exact verified provider. Callers must revalidate after suspension.
    func hasCurrentDemand(
        for provider: VerifiedAddonIdentity,
        at now: RuntimeInstant
    ) throws -> Bool {
        try currentDemandDeadline(for: provider, at: now) != nil
    }

    /// The latest exact canonical interest deadline lets the runtime reject
    /// demand that expires while this actor hop is suspended.
    func currentDemandDeadline(
        for provider: VerifiedAddonIdentity,
        at now: RuntimeInstant
    ) throws -> Duration? {
        try validTime(now)
        guard !isRevisionExhausted else { return nil }
        return registry.interests.values.compactMap { interest -> Duration? in
            guard interest.deadline > now.monotonic,
                  let permission = permissions.entries[interest.permissionID]?.value,
                  permission.binding.providerIdentity == provider,
                  bindings.permissions[ServiceBindingStore.key(permission)] == interest.permissionID,
                  let source = registry.sources[interest.sourceID],
                  source.key.provider == provider,
                  source.key == ServiceRegistry.SourceKey(permission) else {
                return nil
            }
            return interest.deadline
        }.max()
    }

    private func validateGrant(
        _ grantID: UUID, session: ServiceSession, now: RuntimeInstant
    ) throws -> LeaseStore.Entry {
        guard !isRevisionExhausted else { throw Self.failure(.sessionRevoked) }
        try validTime(now)
        guard let connection = registry.sessions[session], let grant = leases.grants[grantID],
              grant.session == session, grant.lease.grant.owner == connection.identity.addonID,
              grant.lease.grant.generation == connection.generation,
              let permission = permissions.entries[grant.permissionID]?.value,
              permission.consumer == connection.identity,
              bindings.permissions[ServiceBindingStore.key(permission)] == grant.permissionID,
              let interest = registry.interests[grant.interestID],
              let source = registry.sources[interest.sourceID],
              source.key == ServiceRegistry.SourceKey(permission) else {
            throw Self.failure(.permissionDenied)
        }
        guard now.monotonic < grant.deadline else { throw Self.failure(.deadlineExceeded) }
        return grant
    }

    func permissionID(session: ServiceSession, requirementID: String,
                      scope: ServiceScope, now: RuntimeInstant) throws -> UUID {
        try validTime(now)
        try scope.validate()
        guard !isRevisionExhausted, let connection = registry.sessions[session] else {
            throw Self.failure(.sessionRevoked)
        }
        let key = ServiceBindingStore.Key(consumer: connection.identity, requirementID: requirementID,
                                         featureID: scope.featureID, operation: scope.operation)
        guard let id = bindings.permissions[key], let permission = permissions.entries[id]?.value,
              ServiceBindingStore.key(permission) == key else { throw Self.failure(.permissionDenied) }
        if let interest = registry.interests.values.first(where: { $0.permissionID == id }),
           interest.deadline <= now.monotonic { throw Self.failure(.deadlineExceeded) }
        return id
    }

    func bindSubscription(session: ServiceSession, grantID: UUID, requirementID: String,
                          now: RuntimeInstant) throws -> ServiceSubscriptionBinding {
        let grant = try validateGrant(grantID, session: session, now: now)
        guard let permission = permissions.entries[grant.permissionID]?.value,
              permission.binding.requirementID == requirementID,
              let interest = registry.interests[grant.interestID], interest.deadline > now.monotonic,
              let source = registry.sources[interest.sourceID] else { throw Self.failure(.permissionDenied) }
        return ServiceSubscriptionBinding(grant: grant.lease.grant, permissionID: grant.permissionID,
            interestID: grant.interestID, sourceID: source.id, key: source.key,
            deadline: min(grant.deadline, interest.deadline))
    }

    func sourceBinding(sourceID: UUID, now: RuntimeInstant) throws -> ServiceSourceBinding {
        try validTime(now)
        guard !isRevisionExhausted, let source = registry.sources[sourceID],
              let deadline = registry.interests.values.filter({ $0.sourceID == sourceID && $0.deadline > now.monotonic })
                .map(\.deadline).max() else { throw Self.failure(.permissionDenied) }
        return ServiceSourceBinding(sourceID: sourceID, key: source.key, deadline: deadline,
                                    startConsumed: source.startConsumed, restartRequired: source.restartRequired)
    }

    func pendingWakeIsCurrent(consumer: VerifiedAddonIdentity, now: RuntimeInstant) -> Bool {
        !isRevisionExhausted && (try? validTime(now)) != nil && registry.pendingWakes.contains(consumer)
            && registry.interests.values.contains { $0.consumer == consumer && $0.deadline > now.monotonic }
    }

    public func beginInvocation(session: ServiceSession, grantID: UUID, invocation: ServiceInvocation,
        now: RuntimeInstant) async throws -> ServiceWork {
        let grant = try validateGrant(grantID, session: session, now: now)
        try invocation.validate()
        guard invocation.contractID == grant.lease.grant.serviceID,
              invocation.operation == grant.lease.grant.scope.operation else {
            throw Self.failure(.permissionDenied)
        }
        let permission = permissions.entries[grant.permissionID]!.value
        let key = LeaseStore.RequestKey(consumer: permission.consumer, requestID: invocation.requestID)
        let source = ServiceRegistry.SourceKey(permission)
        if let previous = leases.requests[key] {
            guard previous.invocation == invocation, previous.source == source,
                  previous.requirementID == permission.binding.requirementID else {
                throw Self.failure(.invalidPayload)
            }
            // Recovery uses requestOutcome with fresh authority. No duplicate begin emits work.
            throw AddonFailure(code: .invalidPayload, reason: "This logical service request was already admitted.")
        }
        let interval = invocation.deadline.timeIntervalSince(now.wall)
        guard interval.isFinite, interval > 0, interval <= 30 else { throw Self.failure(.deadlineExceeded) }
        guard leases.operations.count < limits.operations, leases.requests.count < limits.requests,
              leases.requests.keys.filter({ $0.consumer.addonID == permission.consumer.addonID }).count
                < limits.requestsPerOwner else { throw Self.failure(.resourceDenied) }
        let expected = try startAdmission()
        defer { admitting = false }
        // Reserve canonical request + maximum response + metadata before any dispatch. No eviction on pressure.
        let reservation = try await resourceAccess.admit(
            .state(bytes: invocation.payload.count + 8_192 + 65_536),
            owner: grant.lease.grant.owner
        )
        do { try checkRevision(expected) } catch { await release([reservation]); throw error }
        let id = UUID()
        leases.requests[key] = .init(invocation: invocation, requirementID: permission.binding.requirementID,
            source: source, workID: id, retainUntil: now.monotonic + .seconds(600), reservation: reservation,
            outcome: .pending)
        let effectiveDeadline = min(
            grant.deadline,
            now.monotonic + .seconds(interval)
        )
        leases.operations[id] = .init(id: id, grantID: grantID, requestKey: key, contractID: invocation.contractID,
            operation: invocation.operation, deadline: effectiveDeadline)
        return ServiceWork(
            id               : id,
            sourceID         : registry.interests[grant.interestID]!.sourceID,
            invocation       : invocation,
            effectiveDeadline: effectiveDeadline
        )
    }

    private func finishOperation(_ id: UUID, response: ServiceResponse? = nil) {
        pendingCompletions.removeValue(forKey: id)
        guard let operation = leases.operations.removeValue(forKey: id),
              var record = leases.requests[operation.requestKey] else { return }
        record.outcome = response.map(ServiceRequestOutcome.completed) ?? (operation.consumed ? .unknown : .unsent)
        record.needsResultReduction = true
        leases.requests[operation.requestKey] = record
    }

    public func completeInvocation(_ id: UUID, response: ServiceResponse,
        now: RuntimeInstant) async throws -> ServiceResponse {
        guard leases.operations[id] != nil else { throw Self.failure(.sessionRevoked) }
        do {
            return try await completeInvocation(
                id,
                response  : response,
                receivedAt: now
            )
        } catch {
            // The public broker API owns invalid terminal events. A competing result
            // cannot displace the first prepared result while its reduction is pending.
            if pendingCompletions[id] == nil {
                finishOperation(id)
                await reclaimTerminalResultCapacity()
            }
            throw error
        }
    }

    /// Commits one host-timestamped terminal event without reinterpreting a timely
    /// receipt at a later owned-drain time. Missing or revoked authority never revives.
    func completeInvocation(
        _ id       : UUID,
        response   : ServiceResponse,
        receivedAt : RuntimeInstant
    ) async throws -> ServiceResponse {
        let preparation = try prepareInvocationCompletion(
            id,
            response  : response,
            receivedAt: receivedAt
        )
        return try await commitInvocationCompletion(preparation)
    }

    func prepareInvocationCompletion(
        _ id       : UUID,
        response   : ServiceResponse,
        receivedAt : RuntimeInstant
    ) throws -> CompletionPreparation {
        guard let operation = leases.operations[id] else { throw Self.failure(.sessionRevoked) }
        guard let grant = leases.grants[operation.grantID] else {
            throw Self.failure(.sessionRevoked)
        }
        _ = try validateGrant(operation.grantID, session: grant.session, now: receivedAt)
        guard receivedAt.monotonic < operation.deadline else { throw Self.failure(.deadlineExceeded) }
        guard operation.consumed else { throw Self.failure(.invalidPayload) }
        try response.validate()
        guard response.contractID == operation.contractID,
              response.operation == operation.operation else {
            throw Self.failure(.invalidPayload)
        }
        if let pending = pendingCompletions[id] {
            guard pending.response == response else { throw Self.failure(.invalidPayload) }
            return CompletionPreparation(
                workID: id,
                token : pending.token
            )
        }
        let pending = PendingCompletion(
            token   : UUID(),
            response: response
        )
        pendingCompletions[id] = pending
        return CompletionPreparation(
            workID: id,
            token : pending.token
        )
    }

    func commitInvocationCompletion(
        _ preparation: CompletionPreparation
    ) async throws -> ServiceResponse {
        guard let pending = pendingCompletions[preparation.workID],
              pending.token == preparation.token,
              leases.operations[preparation.workID] != nil else {
            throw Self.failure(.sessionRevoked)
        }
        finishOperation(
            preparation.workID,
            response: pending.response
        )
        await reclaimTerminalResultCapacity()
        return pending.response
    }

    func cancelInvocationCompletion(_ preparation: CompletionPreparation) {
        guard pendingCompletions[preparation.workID]?.token == preparation.token else { return }
        pendingCompletions.removeValue(forKey: preparation.workID)
    }

    // Mutate canonical state before awaiting resource release. In-flight admissions observe revision changes.
    private func removeGrants(_ ids: Set<UUID>) -> [ResourceReservation] {
        var reservations: [ResourceReservation] = []
        for id in ids {
            if let grant = leases.grants.removeValue(forKey: id) { reservations.append(grant.reservation) }
        }
        for (id, operation) in leases.operations where ids.contains(operation.grantID) {
            finishOperation(id)
        }
        return reservations
    }

    private func removeInterests(_ ids: Set<UUID>) -> ([ResourceReservation], [ServiceDecision]) {
        var reservations = removeGrants(Set(leases.grants.filter { ids.contains($0.value.interestID) }.keys))
        var decisions: [ServiceDecision] = []
        for id in ids {
            guard let interest = registry.interests.removeValue(forKey: id) else { continue }
            _ = cpuAttributionLedger?.removeInterest(id)
            reservations.append(interest.reservation)
            if !registry.interests.values.contains(where: { $0.sourceID == interest.sourceID }),
               let source = registry.sources.removeValue(forKey: interest.sourceID) {
                reservations.append(source.reservation)
                decisions.append(.stopSource(source.id))
            }
            if !registry.interests.values.contains(where: { $0.consumer == interest.consumer }) {
                registry.pendingWakes.remove(interest.consumer)
            }
        }
        return (reservations, decisions)
    }

    public func unsubscribe(session: ServiceSession, interestID: UUID) async throws -> [ServiceDecision] {
        guard let connection = registry.sessions[session],
              let interest = registry.interests[interestID], interest.consumer == connection.identity else {
            throw Self.failure(.permissionDenied)
        }
        advanceRevision()
        let (reservations, decisions) = removeInterests([interestID])
        await release(reservations)
        return decisions
    }

    public func disconnect(_ session: ServiceSession) async {
        guard let connection = registry.sessions.removeValue(forKey: session) else { return }
        advanceRevision()
        let reservations = removeGrants(Set(leases.grants.filter { $0.value.session == session }.keys))
        await release(reservations + [connection.reservation])
    }

    public func sourceChanged(_ sourceID: UUID, now: RuntimeInstant) async -> [ServiceDecision] {
        guard (try? validTime(now)) != nil else { return [] }
        var decisions: [ServiceDecision] = []
        for interest in registry.interests.values
            where interest.sourceID == sourceID && interest.deadline > now.monotonic {
            guard !registry.sessions.values.contains(where: { $0.identity == interest.consumer }),
                  registry.pendingWakes.insert(interest.consumer).inserted else { continue }
            decisions.append(.wakeConsumer(interest.consumer))
        }
        return decisions
    }

    private func invalidatePermissions(_ ids: Set<UUID>) -> ([ResourceReservation], ServiceInvalidation) {
        advanceRevision()
        var affected: Set<ResolvedFeature> = []
        var reservations: [ResourceReservation] = []
        for id in ids {
            guard let permission = permissions.entries.removeValue(forKey: id) else { continue }
            bindings.permissions.removeValue(forKey: ServiceBindingStore.key(permission.value))
            affected.insert(ResolvedFeature(addonID: permission.value.consumer.addonID,
                featureID: permission.value.binding.featureID!))
            reservations.append(permission.reservation)
        }
        let interests = Set(registry.interests.filter { ids.contains($0.value.permissionID) }.keys)
        let (removed, decisions) = removeInterests(interests)
        return (reservations + removed, ServiceInvalidation(affectedFeatures: affected, decisions: decisions))
    }

    public func revoke(permissionID: UUID) async -> [ServiceDecision] {
        let (reservations, impact) = invalidatePermissions([permissionID])
        await release(reservations)
        return impact.decisions
    }

    public func disable(consumer: VerifiedAddonIdentity, featureID: String? = nil) async -> [ServiceDecision] {
        if featureID == nil { return await disableAddon(consumer).decisions }
        let ids = Set(permissions.entries.filter {
            $0.value.value.consumer == consumer && $0.value.value.binding.featureID == featureID
        }.keys)
        let (reservations, impact) = invalidatePermissions(ids)
        await release(reservations)
        return impact.decisions
    }

    /// The authority supplies the complete resolved path, not a consumer payload. No work is emitted on failure.
    /// Reservations represent process admission; release only after all corresponding workers actually exit.
    public func admitPath(_ providers: [VerifiedAddonIdentity]) async throws -> ServicePathAdmission {
        guard !providers.isEmpty, providers.count <= 8, paths.count < 16,
              Set(providers.map(\.addonID)).count == providers.count else { throw Self.failure(.resourceDenied) }
        for provider in providers { try ServiceRegistry.validateIdentity(provider) }
        let expected = try startAdmission()
        defer { admitting = false }
        var reservations: [ResourceReservation] = []
        do {
            for provider in providers {
                reservations.append(try await resourceAccess.admit(
                    .provider,
                    owner: provider.addonID
                ))
            }
            try checkRevision(expected)
            let id = UUID()
            paths[id] = reservations
            return ServicePathAdmission(id: id, providers: providers)
        } catch { await release(reservations); throw error }
    }

    public func releasePathAfterExit(_ id: UUID) async {
        guard let reservations = paths.removeValue(forKey: id) else { return }
        await release(reservations)
    }

    /// Releases broker metadata. Outstanding process admissions stay charged until observed exit.
    @discardableResult
    public func shutdown() async -> [ServiceDecision] {
        advanceRevision()
        let (interestReservations, decisions) = removeInterests(Set(registry.interests.keys))
        let reservations = interestReservations + permissions.entries.values.map(\.reservation)
            + registry.sessions.values.map(\.reservation) + leases.requests.values.map(\.reservation)
        leases.requests.removeAll()
        permissions.entries.removeAll()
        bindings.permissions.removeAll()
        registry.sessions.removeAll()
        registry.pendingWakes.removeAll()
        await release(reservations)
        return decisions
    }

    /// Feed this into the host's one shared deadline queue; the broker creates no timers.
    public func nextDeadline() -> Duration? {
        (registry.interests.values.map(\.deadline) + leases.grants.values.map(\.deadline)
            + leases.operations.values.map(\.deadline) + leases.requests.values.map(\.retainUntil)).min()
    }

    public func expire(now: RuntimeInstant) async -> [ServiceDecision] {
        guard (try? validTime(now)) != nil else { return [] }
        let interests = Set(registry.interests.filter { $0.value.deadline <= now.monotonic }.keys)
        let (removed, decisions) = removeInterests(interests)
        var reservations = removed + removeGrants(Set(leases.grants.filter {
            $0.value.deadline <= now.monotonic
        }.keys))
        for (id, operation) in leases.operations where operation.deadline <= now.monotonic {
            finishOperation(id)
        }
        for (key, record) in leases.requests where record.retainUntil <= now.monotonic {
            finishOperation(record.workID)
            leases.requests.removeValue(forKey: key)
            reservations.append(record.reservation)
        }
        // Even a terminal transition without a resource release invalidates an in-flight admission snapshot.
        advanceRevision()
        await release(reservations)
        return decisions
    }

    /// System service-loss event: returns the precise features for resolver reevaluation.
    /// Restoration requires a newly authorized binding; this method never selects a fallback.
    public func providerUnavailable(_ identity: VerifiedAddonIdentity) async -> ServiceInvalidation {
        let ids = Set(permissions.entries.filter { $0.value.value.binding.providerIdentity == identity }.keys)
        let (reservations, impact) = invalidatePermissions(ids)
        await release(reservations)
        return impact
    }

    /// providerExitedPreservingInterests invalidates execution authority while retaining
    /// unexpired permissions, interests, source identity, reservation and deadlines.
    func providerExitedPreservingInterests(_ identity: VerifiedAddonIdentity) async {
        let sourceIDs = Set(registry.sources.compactMap { id, source in
            source.key.provider == identity ? id : nil
        })
        guard !sourceIDs.isEmpty else { return }
        advanceRevision()
        for id in sourceIDs {
            registry.sources[id]?.startConsumed = false
            registry.sources[id]?.restartRequired = true
        }
        let interestIDs = Set(registry.interests.compactMap { id, interest in
            sourceIDs.contains(interest.sourceID) ? id : nil
        })
        let grantIDs = Set(leases.grants.compactMap { id, grant in
            interestIDs.contains(grant.interestID) ? id : nil
        })
        let reservations = removeGrants(grantIDs)
        await release(reservations)
        await reclaimTerminalResultCapacity()
    }

    public func disableAddon(_ identity: VerifiedAddonIdentity) async -> ServiceInvalidation {
        let ids = Set(permissions.entries.filter {
            $0.value.value.consumer == identity || $0.value.value.binding.providerIdentity == identity
        }.keys)
        let (removed, impact) = invalidatePermissions(ids)
        var reservations = removed
        for (id, session) in registry.sessions where session.identity == identity {
            registry.sessions.removeValue(forKey: id)
            reservations.append(session.reservation)
            reservations += removeGrants(Set(leases.grants.filter { $0.value.session == id }.keys))
        }
        await release(reservations)
        return impact
    }
    public func consumeSourceStart(_ id: UUID, now: RuntimeInstant) throws -> ServiceSourceDescriptor {
        guard !isRevisionExhausted else { throw Self.failure(.sessionRevoked) }
        try validTime(now)
        guard var source = registry.sources[id], !source.startConsumed, !source.restartRequired,
              registry.interests.values.contains(where: { $0.sourceID == id && $0.deadline > now.monotonic }) else {
            throw Self.failure(.permissionDenied)
        }
        source.startConsumed = true
        registry.sources[id] = source
        return ServiceSourceDescriptor(provider: source.key.provider, digest: source.key.digest,
            contractVersion: source.key.version, serviceID: source.key.serviceID, partition: source.key.partition,
            featureID: source.key.featureID, operation: source.key.operation)
    }
    public func consumeInvocation(_ id: UUID, now: RuntimeInstant) throws -> UUID {
        guard var operation = leases.operations[id], !operation.consumed,
              let grant = leases.grants[operation.grantID] else { throw Self.failure(.permissionDenied) }
        _ = try validateGrant(operation.grantID, session: grant.session, now: now)
        guard now.monotonic < operation.deadline else { throw Self.failure(.deadlineExceeded) }
        operation.consumed = true
        leases.operations[id] = operation
        leases.requests[operation.requestKey]?.outcome = .dispatched
        return registry.interests[grant.interestID]!.sourceID
    }

    /// consumeInvocation validates an exact queued value before exposing canonical identities.
    ///
    /// This overload is for host service boundaries. The caller's `ServiceWork` is only a
    /// correlation value: every field is matched against retained broker state before the
    /// operation is marked dispatched.
    func consumeInvocation(
        _ work   : ServiceWork,
        serviceID: String,
        featureID: String,
        operation: String,
        now      : RuntimeInstant
    ) throws -> ServiceInvocationBinding {
        guard var storedOperation = leases.operations[work.id],
              !storedOperation.consumed,
              storedOperation.id == work.id,
              storedOperation.contractID == serviceID,
              storedOperation.operation == operation,
              storedOperation.deadline == work.effectiveDeadline,
              let grant = leases.grants[storedOperation.grantID],
              let permission = permissions.entries[grant.permissionID]?.value,
              permission.consumer == storedOperation.requestKey.consumer,
              permission.serviceID == serviceID,
              permission.binding.featureID == featureID,
              permission.operation == operation,
              let interest = registry.interests[grant.interestID],
              interest.consumer == permission.consumer,
              let source = registry.sources[interest.sourceID],
              source.id == work.sourceID,
              source.key == ServiceRegistry.SourceKey(permission),
              let request = leases.requests[storedOperation.requestKey],
              request.workID == work.id,
              request.invocation == work.invocation,
              request.requirementID == permission.binding.requirementID,
              request.source == source.key,
              request.outcome == .pending else {
            throw Self.failure(.permissionDenied)
        }
        _ = try validateGrant(
            storedOperation.grantID,
            session: grant.session,
            now    : now
        )
        guard now.monotonic < storedOperation.deadline else {
            throw Self.failure(.deadlineExceeded)
        }
        storedOperation.consumed = true
        leases.operations[work.id] = storedOperation
        leases.requests[storedOperation.requestKey]?.outcome = .dispatched
        return ServiceInvocationBinding(
            owner     : permission.consumer,
            source    : ServiceSourceDescriptor(
                provider       : source.key.provider,
                digest         : source.key.digest,
                contractVersion: source.key.version,
                serviceID      : source.key.serviceID,
                partition      : source.key.partition,
                featureID      : source.key.featureID,
                operation      : source.key.operation
            ),
            invocation: request.invocation
        )
    }

    /// finishConsumedInvocationAsUnknown retires work after a handler received it.
    func finishConsumedInvocationAsUnknown(_ id: UUID) async -> Bool {
        guard leases.operations[id]?.consumed == true else { return false }
        finishOperation(id)
        await reclaimTerminalResultCapacity()
        return true
    }

    /// abandonInvocation preserves replay history while making a consumed decision
    /// definitely unsent only after the synchronous adapter rejects before handoff.
    func abandonInvocation(
        _ id       : UUID,
        knownUnsent: Bool
    ) async -> Bool {
        guard knownUnsent,
              let operation = leases.operations.removeValue(forKey: id),
              var record = leases.requests[operation.requestKey],
              record.workID == id,
              record.outcome == (operation.consumed ? .dispatched : .pending) else { return false }
        record.outcome = .unsent
        record.needsResultReduction = true
        leases.requests[operation.requestKey] = record
        await reclaimTerminalResultCapacity()
        return true
    }

    /// abandonSourceStart retires a consumed source whose adapter proved no handoff.
    /// Fresh authority and acquisition are required before a later start decision.
    func abandonSourceStart(
        _ id       : UUID,
        knownUnsent: Bool
    ) async -> Bool {
        guard knownUnsent, registry.sources[id]?.startConsumed == true else { return false }
        let interests = Set(registry.interests.compactMap { key, value in
            value.sourceID == id ? key : nil
        })
        let (reservations, _) = removeInterests(interests)
        await release(reservations)
        return true
    }

    /// invocationDeadline returns the broker's effective canonical deadline projection.
    func invocationDeadline(_ id: UUID) -> Duration? {
        leases.operations[id]?.deadline
    }
    /// validatedRequestKey checks fresh authority and the complete original binding before history disclosure.
    private func validatedRequestKey(
        session: ServiceSession,
        grantID: UUID,
        requestID: UUID,
        now: RuntimeInstant
    ) throws -> LeaseStore.RequestKey? {
        let grant = try validateGrant(grantID, session: session, now: now)
        guard let permission = permissions.entries[grant.permissionID]?.value else {
            throw Self.failure(.permissionDenied)
        }
        let key = LeaseStore.RequestKey(consumer: permission.consumer, requestID: requestID)
        guard let record = leases.requests[key], record.retainUntil > now.monotonic else { return nil }
        guard record.source == ServiceRegistry.SourceKey(permission),
              record.requirementID == permission.binding.requirementID else { throw Self.failure(.permissionDenied) }
        return key
    }

    /// requestOutcome discloses history only under fresh authority for the same canonical service binding.
    /// A timeout commits synchronously; authority, binding and retention are checked again after its refund.
    public func requestOutcome(
        session: ServiceSession,
        grantID: UUID,
        requestID: UUID,
        now: RuntimeInstant
    ) async throws -> ServiceRequestOutcome? {
        guard let key = try validatedRequestKey(
            session: session,
            grantID: grantID,
            requestID: requestID,
            now: now
        ) else { return nil }
        if let workID = leases.requests[key]?.workID,
           let operation = leases.operations[workID], operation.deadline <= now.monotonic {
            finishOperation(operation.id)
        }
        await reclaimTerminalResultCapacity()
        guard let currentKey = try validatedRequestKey(
            session: session,
            grantID: grantID,
            requestID: requestID,
            now: now
        ) else { return nil }
        return leases.requests[currentKey]?.outcome
    }
}
