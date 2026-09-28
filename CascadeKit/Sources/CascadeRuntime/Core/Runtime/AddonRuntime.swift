//
//  AddonRuntime.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation

/// AddonRuntime owns the canonical pure runtime state and serializes bounded admission.
/// It retains no task queue or waiting continuation; concurrent new admission fails fast.
actor AddonRuntime {
    enum ResourceRegistration: Equatable, Sendable {
        case registered, duplicate
    }

    enum ResourceOwnerStatus: Equatable, Sendable {
        case current, stale, recordingFailed
    }

    struct ResourceOwnerObservation: Equatable, Sendable {
        let owner         : VerifiedAddonIdentity
        let classification: ProcessMetricCPUViolationResult
        let decision      : AddonHealthDecision?
        let status        : ResourceOwnerStatus
    }

    enum ResourceSampleResult: Equatable, Sendable {
        case sampled([ResourceOwnerObservation])
        case notDue
        case busy
    }

    /// MetricWakeResetResult distinguishes a completed baseline reset from a wake
    /// that remains pending behind the shared resource operation gate.
    enum MetricWakeResetResult: Equatable, Sendable {
        case completed
        case deferred
    }

    enum PublicationOutputResult: Equatable, Sendable {
        case committed(PublicationAdmission)
        case pendingServiceCompletion
    }

    enum ServiceCompletionResult: Equatable, Sendable {
        case accepted(ServiceResponse)
        case pending
    }

    struct Snapshot: Sendable {
        let publications: [Publication]
        let actionCount: Int
        let providerCount: Int
        let isStopped: Bool
    }

    struct OwnerDiagnostics: Equatable, Sendable {
        let reservedStateBytes: Int
        let hasProcess: Bool
        let hasOutstandingDelivery: Bool
    }

    private struct Assignment: Sendable {
        let owner                : AddonID
        let publisher            : String
        let digest               : String
        let featureID            : String
        let assetPrivacyPartition: AssetPrivacyPartition
        let eligibility          : ActionAuthorizer.Eligibility
        let authorityRevision    : UInt64
        /// assignmentToken is immutable for the life of this assignment; repeated assignment
        /// returns it unchanged and it is never derived from the mutable authorityRevision.
        let assignmentToken      : UUID
        var hasPublished         : Bool
    }

    /// ArchiveProgress retains only current, saved and attempted significant-change markers.
    /// An unchanged failed generation remains dirty without creating a retry queue or timer.
    private struct ArchiveProgress: Sendable {
        var current  : UUID?
        var saved    : UUID?
        var attempted: UUID?
    }

    private struct OwnerPool: Sendable {
        let reservation: ResourceReservation
        let baseBytes: Int
        let storageOwnGranted: Bool
        var reservedBytes: Int
        var revision: UInt64
        var restorationSealed = false
        var archiveProgress = ArchiveProgress()
    }

    /// AdmissionPurpose grants only the exact shutdown ticket an exception to normal admission closure.
    private enum AdmissionPurpose: Sendable {
        case normal
        case archiveQuiescence(ArchiveQuiescence)
    }

    private enum ArchiveWindowClosed: Error { case closed }

    private struct AdmissionOperation: Sendable {
        let id               : UUID
        let owner            : AddonID
        let authorityRevision: UInt64
        let purpose          : AdmissionPurpose
    }

    private struct DeferredExit: Sendable {
        let owner: AddonID
        let process: ProcessRecord
        let connection: RuntimeConnection?
    }

    private enum ProcessPhase: Sendable {
        case pending
        case connected(RuntimeConnection)
        case stopping(RuntimeConnection?)
    }

    /// DeliveryCredit identifies the exact canonical work occupying the adapter payload slot.
    private enum DeliveryCredit: Equatable, Sendable {
        case action(ticketID: UUID)
        case source(sourceID: UUID)
        case service(workID: UUID)
        case serviceReserved(UUID)
        case serviceAccepted(UUID)
        // The new tagged receipt must not enlarge every legacy ProcessRecord.
        // Its box is prepaid by the owning control/source/alias metadata below.
        indirect case subscriptionAccepted(RuntimeServiceSubscriptionReceipt)
        case storageReserved(UUID)
        case storageAccepted(RuntimeStorageReceipt)
        case assetReserved(UUID)
        case assetAccepted(RuntimeAssetReceipt)
    }

    /// IngressHandle shares one scalar claim across publication, raw storage and raw asset transfers.
    private enum IngressHandle: Equatable, Sendable {
        case publication(RuntimeIngressHandle)
        case storage(RuntimeStorageIngressHandle)
        case asset(RuntimeAssetIngressHandle)
        case service(token: UUID, encodedBytes: Int, sequence: UInt64, kind: RuntimeServiceIngressKind)
    }

    /// IngressClaim distinguishes invocations even when they mention the same adapter handle.
    private struct IngressClaim: Equatable, Sendable {
        let id    : UUID
        let handle: IngressHandle
    }

    /// ProcessCreditState owns fixed scalar slots for this process incarnation, never payload history.
    private struct ProcessCreditState: Sendable {
        var ingress            : IngressClaim?
        var delivery           : DeliveryCredit?
        var lastStorageSequence: UInt64 = 0
    }

    /// AssetTransferState is the single bounded scalar binding for one process incarnation.
    private struct AssetTransferState: Sendable {
        let binding   : AssetTransferBinding
        let transferID: UUID
    }

    private enum IngressDisposition { case finish, cancel, reject }

    private struct ProcessRecord: Sendable {
        let launchID: RuntimeLaunchID
        let incarnation: RuntimeIncarnation
        let identity: VerifiedAddonIdentity
        let digest: String
        let providerReservation: ResourceReservation
        let coldStartDeadline: Duration
        /// One assembler per process prepaid with process admission; never one per begin.
        let assembler: BoundedAssetTransferAssembler
        var phase: ProcessPhase
        var credits = ProcessCreditState()
        /// Exact provider payload authority survives logical execution-row retirement.
        var servicePayloadReceipt: RuntimeServiceReceipt? = nil
        /// lastAssetSequence is per canonical connection and only meaningful for 1.2 hosts.
        var lastAssetSequence: UInt64 = 0
        var lastServiceSequence: UInt64 = 0
        var assetTransfer: AssetTransferState?
        var outputOutstanding: Bool { credits.ingress != nil }
        var deliveryOutstanding: Bool { credits.delivery != nil }
        var stopRequested: Bool
        /// Logical connection closure is independent of stop requests and physical exit.
        var connectionClosed = false
        var metricBinding: ProcessMetricBinding?
        var healthSession: AddonHealthSession?
        var pendingCrashSession: AddonHealthSession?
        var memoryEpisode = ProviderMemoryEpisode()
    }

    /// PhysicalExitCause can be `unexpected` only when a trusted host exit report selects it.
    /// Ordinary callers remain unclassified and cannot increment crash history.
    enum PhysicalExitCause: Equatable, Sendable {
        case unclassified
        case unexpected
    }

    private struct PendingCrashDecision: Sendable {
        let incarnation: RuntimeIncarnation
        let session: AddonHealthSession
        let identity: VerifiedAddonIdentity
        let digest: String
    }

    private struct MetricOwnerSnapshot: Sendable {
        let owner            : AddonID
        let identity         : VerifiedAddonIdentity
        let digest           : String
        let version          : AddonVersionIdentity
        let incarnation      : RuntimeIncarnation?
        let binding          : ProcessMetricBinding?
        let healthSession    : AddonHealthSession?
        let delegatedSession : AddonHealthSession?
        let retryTicket      : AddonRetryTicket?
        let authorityRevision: UInt64
    }

    private enum ResourceHealthEvent: Equatable {
        case moderate, severe
    }

    private struct MemoryAssessment {
        let owner: AddonID
        let identity: VerifiedAddonIdentity
        let incarnation: RuntimeIncarnation
        let footprintBytes: UInt64?
        let isCurrent: Bool
    }

    private struct ActionResources: Sendable {
        let command: ResourceReservation
        var job: ResourceReservation?
        var delivery: ActionDispatcher.Delivery?
    }

    private struct ActionKey: Hashable, Sendable {
        let owner: AddonID
        let requestID: UUID
    }

    private struct ServicePermissionRecord: Sendable {
        let owner: AddonID
        let requirementID: String
        let scope: ServiceScope
        let provider: VerifiedAddonIdentity
    }

    private struct ServiceGrantRecord: Sendable {
        let owner: AddonID
        let provider: VerifiedAddonIdentity
        let sourceID: UUID
        let deadline: Duration
    }

    private struct ServiceExecutionRecord: Sendable {
        let work: ServiceWork
        let grantID: UUID
        let consumer: AddonID
        let provider: AddonID
        let connectionToken: UUID
        let providerIncarnation: RuntimeIncarnation
        let command: ResourceReservation
        let job: ResourceReservation
        var isHandedOff: Bool
    }

    private struct DeferredServiceCompletion: Sendable {
        let response: ServiceResponse
        let requestID: UUID
        let grantID: UUID
        let consumer: AddonID
        let connectionToken: UUID
        let providerIncarnation: RuntimeIncarnation
        let authorityRevision: UInt64
        let receivedAt: RuntimeInstant
        let preparedCompletion: PublicationState.PreparedCompletion?
        let ingressClaim: IngressClaim?
        // Copied cleanup can outlive serviceExecutions; this canonical owner remains in its prepaid 4 KiB row.
        let provider: AddonID
    }

    private enum ServiceCompletionDrainOutcome: Sendable {
        case accepted(PublicationAdmission?)
        case refused
    }

    private enum CorrelatedCompletion: Sendable {
        case action(
            key: ActionKey,
            delivery: ActionDispatcher.Delivery,
            outcome: ActionOutcome
        )
        case service(
            workID: UUID,
            requestID: UUID,
            response: ServiceResponse,
            providerIncarnation: RuntimeIncarnation,
            consumer: AddonID,
            authorityRevision: UInt64
        )

        var expectation: CompletionExpectation {
            switch self {
            case .action(let key, _, _):
                return .action(requestID: key.requestID)
            case .service(_, let requestID, let response, _, _, _):
                return .service(
                    requestID: requestID,
                    contractID: response.contractID,
                    operation : response.operation
                )
            }
        }
    }

    private struct SourceExecutionRecord: Sendable {
        let provider: AddonID
        let providerIncarnation: RuntimeIncarnation
        let deadline: Duration
        let job: ResourceReservation
        var isHandedOff: Bool
    }

    private struct PreparedLaunch: Sendable {
        let owner: AddonID
        let installed: InstalledAddon
        let reservation: ResourceReservation
        let launchID: RuntimeLaunchID
        let incarnation: RuntimeIncarnation
        var isHandedOff: Bool
    }

    private static let archiveProgressBytes = max(
        256,
        4 * MemoryLayout<ArchiveProgress>.stride
    )
    private static let archiveQuiescenceBytes = max(
        256,
        4 * MemoryLayout<AdmissionPurpose>.stride
    )
    private static let ownerMetadataBytes = 16 * 1_024
    /// Each owner prepays one share of the 32-slot CPU graph, per-binding
    /// provenance and fallback-session index. Interest UUIDs retain their own
    /// existing 2 KiB broker reservations.
    private static let cpuAttributionOwnerBytes = 4 * 1_024
    private static let manifestBytes = 64 * 1_024
    private static let resolutionBytes = 128 * 1_024
    private static let assignmentBytes = 2 * 1_024
    private static let actionRowBytes = 4 * 1_024
    private static let servicePermissionBytes = 2 * 1_024
    private static let serviceGrantBytes = 2 * 1_024
    private static let serviceExecutionBytes = 4 * 1_024
    private static let sourceExecutionBytes = 4 * 1_024
    private static let processBytes = 16 * 1_024
    private static let assetAssemblerBytes = 4 * 1_024
    private static let processCreditBytes = max(
        512,
        4 * MemoryLayout<ProcessCreditState>.stride
    )
    /// processAdmissionBytes preserves ingress preparation, selects paid reply capacity and covers
    /// the final inline scalar layout for every process, including protocol 1.0 connections.
    /// Asset-enabled hosts also prepay the fixed assembler/binding bookkeeping once per process.
    private var processAdmissionBytes: Int {
        max(Self.processBytes, 4 * MemoryLayout<ProcessRecord>.stride) + maximumEnvelopeBytes + Self.ingressPreparationBytes
            + deliveryCapacity + Self.processCreditBytes
            + (assetFramesEnabled ? Self.assetAssemblerBytes : 0)
            + (serviceFramesEnabled ? Self.serviceStagingBytes : 0)
    }
    private var deliveryCapacity      : Int { storageFramesEnabled ? 256 * 1_024 : Self.deliverySlotBytes }
    private var storageIngressCapacity: Int {
        storageFramesEnabled
            ? min(
                maximumEnvelopeBytes,
                192 * 1_024
            ) : 0
    }
    private var assetIngressCapacity: Int {
        assetFramesEnabled
            ? min(
                maximumEnvelopeBytes,
                AssetTransferFrameCodec.maximumEncodedBytes
            ) : 0
    }
    private static let storageOwnerBytes = max(
        256,
        4 * MemoryLayout<Bool>.stride
    )
    private static let ingressPreparationBytes = 32 * 1_024
    private static let deliverySlotBytes       = 80 * 1_024

    private static let scratchBytes = 8 * 1_024 * 1_024

    private let governor: ResourceGovernor
    private let assetCoordinator: AssetDisposalCoordinator
    private let assetDecoder: BoundedAssetImageDecoder
    private var assetState = AssetState()
    /// pendingAssetMetadataBytes keeps prepaid import metadata protected during deferred cleanup.
    /// The single active admission supplies its owner, so this never becomes a work queue.
    private var pendingAssetMetadataBytes = 0
    /// pendingArchiveMetadataBytes protects prepaid proposal growth through deferred pool cleanup.
    /// The existing single admission supplies its owner; failed scoped helpers unwind before clearing it.
    private var pendingArchiveMetadataBytes = 0
    private let resourceAccess: any RuntimeResourceAccess
    private let broker: ServiceBroker
    private let serviceDecisionAccess: any RuntimeServiceDecisionAccess
    private let adapter: any AddonRuntimeAdapter
    private let clock: any RuntimeClock
    private let cpuAttributionLedger: ServiceCPUAttributionLedger
    private let processMetrics: ProcessMetricsCoordinator
    private var healthStore = AddonHealthStore()
    private var delegatedHealthSessions: [AddonID: AddonHealthSession] = [:]
    private var pendingCrashDecisions: [AddonID: PendingCrashDecision] = [:]
    private var cpuAdmissionPaused: Set<VerifiedAddonIdentity> = []
    /// RAM state adds one inline episode to each prepaid ProcessRecord and at most
    /// one canonical identity per fixed catalog owner; it creates no per-sample growth.
    private var memoryAdmissionPaused: Set<VerifiedAddonIdentity> = []
    private var resourceOperationInProgress = false
    private var pendingMetricWake: UUID?
    private var pendingMetricDetaches: [RuntimeIncarnation: ProcessMetricBinding] = [:]
    private weak var storageCoordinator: AddonStorageCoordinator?
    private let storageFramesEnabled: Bool
    private let assetFramesEnabled: Bool
    private let serviceFramesEnabled: Bool
    private let serviceSubscriptionsEnabled: Bool
    private var invocationExchange = RuntimeServiceInvocationExchange()
    private var serviceConnections = RuntimeServiceConnectionState()
    private var serviceSubscriptions = ServiceSubscriptionRegistry()
    private var serviceSources: [UUID: RuntimeServiceSourceBinding] = [:]
    private var serviceCache = ServiceLatestStateCache()
    private var serviceRouteDrainInProgress = false
    private var subscriptionDrainInProgress = false
    private var serviceEventDrainInProgress = false
    private var serviceEventDrainRequested = false
    private var pendingServiceMetadataBytes = 0
    // Paid process staging plus protected per-operation codec workspace, never RSS claims.
    private static let serviceStagingBytes = 512 * 1_024
    private static let serviceWorkspaceBytes = 8 * 1_024 * 1_024
    private let maximumEnvelopeBytes: Int
    private var catalog: [AddonID: InstalledAddon] = [:]
    private var resolution: Resolution?
    private var assignments: [PublicationID: Assignment] = [:]
    private var ownerPools: [AddonID: OwnerPool] = [:]
    private var processes: [AddonID: ProcessRecord] = [:]
    private var launches: [RuntimeLaunchID: AddonID] = [:]
    private var publicationReservations: [PublicationID: ResourceReservation] = [:]
    private var actionResources: [ActionKey: ActionResources] = [:]
    private var servicePermissions: [UUID: ServicePermissionRecord] = [:]
    private var serviceGrants: [UUID: ServiceGrantRecord] = [:]
    private var serviceExecutions: [UUID: ServiceExecutionRecord] = [:]
    private var sourceExecutions: [UUID: SourceExecutionRecord] = [:]
    private var publicationState: PublicationState
    private var dispatcher = ActionDispatcher()
    private var deadlines = DeadlineQueue(maximumEntries: 5)
    private let publicationDeadlineKey = UUID()
    private let actionDeadlineKey = UUID()
    private let serviceDeadlineKey = UUID()
    private let assetDeadlineKey = UUID()
    private let metricDeadlineKey = UUID()
    private var aggregateDeadlineOwner: AddonID?
    private var authorityRevision: UInt64 = 0
    private var admissionInProgress = false
    private var cleanupInProgress = false
#if DEBUG
    private var assetCleanupDrainCount: UInt64 = 0
    @TaskLocal static var cpuRegistrationCheckpoint: (@Sendable () async -> Void)?
    @TaskLocal static var cpuWakeResetCheckpoint: (@Sendable () async -> Void)?
    @TaskLocal static var cpuDisableCheckpoint: (@Sendable (AddonID) -> Void)?
    @TaskLocal static var crashDemandCheckpoint: (@Sendable () async -> Void)?
    enum ServiceInvocationCheckpoint: Sendable { case historyRead, encoded, handoff, cleanupTailBeforeAssembler }
    enum ServiceSubscriptionCheckpoint: Sendable { case acquisitionCommitted, eventWorkspaceReady, eventBindingRead }
    @TaskLocal static var serviceSubscriptionObserver: (@Sendable (ServiceSubscriptionCheckpoint) async -> Void)?
    /// Inert unless a trusted test installs it; exposes no grant, payload or handle.
    @TaskLocal static var serviceInvocationObserver: (@Sendable (ServiceInvocationCheckpoint) async -> Void)?
#endif
    private var activeOperation: AdmissionOperation?
    private var deferredDisabledProviders: [AddonID: VerifiedAddonIdentity] = [:]
    private var deferredServiceCompletions: [UUID: DeferredServiceCompletion] = [:]
    private var inFlightServiceCompletionIDs: Set<UUID> = []
    private var deferredExits: [RuntimeIncarnation: DeferredExit] = [:]
    /// One canonical session per stopping incarnation, drained through the admission barrier.
    private var deferredConnectionCloses: [RuntimeIncarnation: RuntimeConnection] = [:]
    /// deferredAssetAssemblers retains a bounded cleanup handle when a protected refund fails
    /// or when a stopped/disabled process never exits. It participates in hasDeferredCleanup
    /// and is attempted once per drain, so a failure stays observable without spinning.
    private var deferredAssetAssemblers: [RuntimeIncarnation: BoundedAssetTransferAssembler] = [:]
    private var deferredReleases: [UUID: AddonID] = [:]
    private var deferredPoolOwners: Set<AddonID> = []
    private var deferredBrokerReconcileReason: RuntimeStopReason?
    private var deferredBrokerExpiry: RuntimeInstant?
    private var deferredBrokerShutdown = false
    private var disabledOwners: Set<AddonID> = []
    private var stopped = false
    private var archiveQuiescence: ArchiveQuiescence?

    private init(
        governor              : ResourceGovernor,
        resourceAccess        : any RuntimeResourceAccess,
        serviceDecisionFactory: @Sendable (ServiceBroker) -> any RuntimeServiceDecisionAccess,
        adapter               : any AddonRuntimeAdapter,
        clock                 : any RuntimeClock,
        cpuAttributionLedger  : ServiceCPUAttributionLedger,
        metricRead            : @escaping ProcessMetricsCoordinator.Read,
        maximumEnvelopeBytes  : Int,
        storageCoordinator    : AddonStorageCoordinator?,
        storageFramesEnabled  : Bool,
        assetFramesEnabled    : Bool,
        serviceFramesEnabled  : Bool,
        serviceSubscriptionsEnabled: Bool
    ) {
        precondition(resourceAccess.resourceGovernorTarget === governor)
        self.governor = governor
        self.storageCoordinator = storageCoordinator
        self.storageFramesEnabled = storageFramesEnabled
        self.assetFramesEnabled = assetFramesEnabled
        self.serviceFramesEnabled = serviceFramesEnabled
        self.serviceSubscriptionsEnabled = serviceSubscriptionsEnabled
        let assetCoordinator = AssetDisposalCoordinator(governor: governor)
        self.assetCoordinator = assetCoordinator
        assetDecoder = BoundedAssetImageDecoder(coordinator: assetCoordinator)
        self.resourceAccess = resourceAccess
        let broker = ServiceBroker(
            governor            : governor,
            resourceAccess      : resourceAccess,
            cpuAttributionLedger: cpuAttributionLedger
        )
        let decisionAccess = serviceDecisionFactory(broker)
        precondition(decisionAccess.serviceBrokerTarget === broker)
        self.broker = broker
        serviceDecisionAccess = decisionAccess
        self.adapter = adapter
        self.clock = clock
        self.cpuAttributionLedger = cpuAttributionLedger
        self.processMetrics = ProcessMetricsCoordinator(
            capacity         : 32,
            attributionLedger: cpuAttributionLedger,
            read             : metricRead
        )
        self.maximumEnvelopeBytes = min(
            512 * 1_024,
            max(
                1,
                maximumEnvelopeBytes
            )
        )
        publicationState = PublicationState(now: { clock.now().wall })
    }

    /// make resolves and reserves the complete bounded host catalog before retaining it.
    static func make(
        catalog             : [InstalledAddon],
        environment         : HostEnvironment,
        governor            : ResourceGovernor,
        adapter             : any AddonRuntimeAdapter,
        clock               : any RuntimeClock = SystemRuntimeClock(),
        metricRead          : @escaping ProcessMetricsCoordinator.Read = { ProcessMetricsReader().read($0) },
        maximumEnvelopeBytes: Int = 512 * 1_024,
        storageCoordinator  : AddonStorageCoordinator? = nil
    ) async throws -> AddonRuntime {
        try await make(
            catalog               : catalog,
            environment           : environment,
            governor              : governor,
            resourceAccess        : governor,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock,
            metricRead            : metricRead,
            maximumEnvelopeBytes  : maximumEnvelopeBytes,
            storageCoordinator    : storageCoordinator
        )
    }

    /// make permits only identity-preserving forwarding wrappers for deterministic tests.
    static func make(
        catalog               : [InstalledAddon],
        environment           : HostEnvironment,
        governor              : ResourceGovernor,
        resourceAccess        : any RuntimeResourceAccess,
        serviceDecisionFactory: @escaping @Sendable (ServiceBroker) -> any RuntimeServiceDecisionAccess,
        adapter               : any AddonRuntimeAdapter,
        clock                 : any RuntimeClock,
        metricRead            : @escaping ProcessMetricsCoordinator.Read = { ProcessMetricsReader().read($0) },
        maximumEnvelopeBytes  : Int = 512 * 1_024,
        storageCoordinator    : AddonStorageCoordinator? = nil
    ) async throws -> AddonRuntime {
        guard
            storageCoordinator == nil
                || (adapter is any AddonRuntimeStorageAdapter
                    && storageCoordinator?.resourceGovernorTarget === governor)
        else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Storage host assembly must share its governor and adapter."
            )
        }
        let storageFramesEnabled =
            storageCoordinator != nil && environment.protocolVersion.major == 1
            && environment.protocolVersion.minor >= 1
        // Protocol 1.2 is cumulative: assets require both the keyed-storage host assembly
        // and an asset-capable adapter, advertised only when the host declares minor >= 2.
        let assetFramesEnabled =
            storageFramesEnabled && (adapter is any AddonRuntimeAssetAdapter)
            && environment.protocolVersion.minor >= 2
        let serviceFramesEnabled = assetFramesEnabled && (adapter is any AddonRuntimeServiceAdapter)
            && environment.protocolVersion.minor >= 3
            && maximumEnvelopeBytes >= ServiceFrameCodec.maximumEncodedBytes
        let serviceSubscriptionsEnabled = serviceFramesEnabled
            && (adapter is any AddonRuntimeServiceSubscriptionAdapter)
            && environment.protocolVersion.minor >= 4
            && maximumEnvelopeBytes >= ServiceSubscriptionFrameCodec.maximumEncodedBytes
        let effectiveEnvironment = HostEnvironment(
            osVersion       : environment.osVersion,
            hostCapabilities: environment.hostCapabilities,
            applications    : environment.applications,
            grants          : environment.grants,
            explicitBindings: environment.explicitBindings,
            protocolVersion : (
                environment.protocolVersion.major,
                min(
                    environment.protocolVersion.minor,
                    storageCoordinator == nil ? 0 : (assetFramesEnabled ? (serviceFramesEnabled ? (serviceSubscriptionsEnabled ? 4 : 3) : 2) : 1)
                )
            ),
            serviceAccessGrants: environment.serviceAccessGrants
        )
        guard catalog.count <= 32 else {
            throw AddonFailure(code: .resolutionTooComplex, reason: "The addon catalog exceeds the host owner limit.")
        }
        let cpuAttributionLedger: ServiceCPUAttributionLedger
        do {
            cpuAttributionLedger = try ServiceCPUAttributionLedger(
                authorizedOwners: catalog.map(\.verifiedIdentity)
            )
        } catch {
            throw AddonFailure(code: .invalidPayload, reason: "The addon catalog has invalid verified identities.")
        }
        let runtime = AddonRuntime(
            governor              : governor,
            resourceAccess        : resourceAccess,
            serviceDecisionFactory: serviceDecisionFactory,
            adapter               : adapter,
            clock                 : clock,
            cpuAttributionLedger  : cpuAttributionLedger,
            metricRead            : metricRead,
            maximumEnvelopeBytes  : maximumEnvelopeBytes,
            storageCoordinator    : storageCoordinator,
            storageFramesEnabled  : storageFramesEnabled,
            assetFramesEnabled    : assetFramesEnabled,
            serviceFramesEnabled  : serviceFramesEnabled,
            serviceSubscriptionsEnabled: serviceSubscriptionsEnabled
        )
        try await runtime.install(
            catalog    : catalog,
            environment: effectiveEnvironment
        )
        return runtime
    }

    /// registerProcessMetrics binds an exact host-observed process to CPU accounting.
    /// This dormant hook has no native caller until process binding is qualified.
    func registerProcessMetrics(
        incarnation: RuntimeIncarnation,
        binding    : ProcessMetricBinding
    ) async throws -> ResourceRegistration {
        guard !resourceOperationInProgress, !cleanupInProgress,
              pendingMetricDetaches.isEmpty else { throw failure(.resourceDenied) }
        resourceOperationInProgress = true
        defer { resourceOperationInProgress = false }
        let owner = try requireProcessOwner(incarnation)
        guard let process = eligibleMetricProcess(owner: owner, incarnation: incarnation),
              let installed = catalog[owner],
              let version = SemanticVersion(installed.manifest.version) else {
            throw failure(.sessionRevoked)
        }
        if let currentBinding = process.metricBinding {
            guard currentBinding == binding, process.healthSession != nil else {
                throw failure(.resourceDenied)
            }
            return .duplicate
        }
        let instant = try currentInstant()
        let versionIdentity = try AddonVersionIdentity(
            verifiedIdentity: process.identity,
            version         : version
        )
        let registration = try await processMetrics.register(
            binding,
            at              : instant.monotonic,
            eventDrivenOwner: process.identity
        )
#if DEBUG
        await Self.cpuRegistrationCheckpoint?()
#endif
        guard registration == .registered,
              let current = eligibleMetricProcess(owner: owner, incarnation: incarnation),
              current.metricBinding == nil,
              current.identity == process.identity,
              current.digest == process.digest else {
            _ = await processMetrics.unregister(binding)
            throw failure(.sessionRevoked)
        }
        guard let session = current.healthSession,
              session.version == versionIdentity else {
            _ = await processMetrics.unregister(binding)
            throw failure(.sessionRevoked)
        }
        delegatedHealthSessions.removeValue(forKey: owner)
        processes[owner]?.metricBinding = binding
        return .registered
    }

    /// metricOwnerSnapshot captures catalog and process authority before the
    /// coordinator awaits. A processless retained consumer is eligible only
    /// while its fixed catalog version remains accepted and enabled.
    private func metricOwnerSnapshot(
        owner    : AddonID,
        installed: InstalledAddon
    ) -> MetricOwnerSnapshot? {
        guard !stopped, archiveQuiescence == nil,
              pendingCrashDecisions[owner] == nil,
              !disabledOwners.contains(owner), installed.enabled,
              resolution?.acceptedAddons.contains(owner) == true,
              let version = SemanticVersion(installed.manifest.version),
              let versionIdentity = try? AddonVersionIdentity(
                  verifiedIdentity: installed.verifiedIdentity,
                  version         : version
              ) else { return nil }
        let process = processes[owner]
        if let process,
           eligibleMetricProcess(owner: owner, incarnation: process.incarnation) == nil {
            return nil
        }
        return MetricOwnerSnapshot(
            owner            : owner,
            identity         : installed.verifiedIdentity,
            digest           : installed.digest,
            version          : versionIdentity,
            incarnation      : process?.incarnation,
            binding          : process?.metricBinding,
            healthSession    : process?.healthSession,
            delegatedSession : delegatedHealthSessions[owner],
            retryTicket      : healthStore.pendingRetryTickets.first {
                $0.version == versionIdentity
            },
            authorityRevision: authorityRevision
        )
    }

    /// isCurrentMetricOwner checks the same exact authority after the await.
    /// Processless recipients use the global revision because they have no
    /// incarnation token; this may conservatively discard an unrelated change.
    private func isCurrentMetricOwner(_ prior: MetricOwnerSnapshot) -> Bool {
        guard let installed = catalog[prior.owner], installed.enabled,
              installed.verifiedIdentity == prior.identity,
              installed.digest == prior.digest,
              SemanticVersion(installed.manifest.version) == prior.version.version,
              !stopped, archiveQuiescence == nil,
              !disabledOwners.contains(prior.owner),
              resolution?.acceptedAddons.contains(prior.owner) == true,
              delegatedHealthSessions[prior.owner] == prior.delegatedSession else {
            return false
        }
        guard healthStore.pendingRetryTickets.first(where: {
            $0.version == prior.version
        }) == prior.retryTicket,
              pendingCrashDecisions[prior.owner] == nil else { return false }
        if let incarnation = prior.incarnation {
            guard let process = eligibleMetricProcess(
                owner      : prior.owner,
                incarnation: incarnation
            ),
                  process.identity == prior.identity,
                  process.digest == prior.digest,
                  process.metricBinding == prior.binding,
                  process.healthSession == prior.healthSession else { return false }
        } else {
            guard processes[prior.owner] == nil,
                  authorityRevision == prior.authorityRevision else { return false }
        }
        return true
    }

    /// isCurrentMetricContributor checks the physical binding even when its
    /// reduction was unavailable or terminal. A failed read does not itself
    /// revoke runtime authority; lifecycle changes do.
    private func isCurrentMetricContributor(
        _ binding: ProcessMetricBinding,
        captured : [VerifiedAddonIdentity: MetricOwnerSnapshot]
    ) -> Bool {
        guard let prior = captured.values.first(where: { $0.binding == binding }),
              let incarnation = prior.incarnation,
              let installed = catalog[prior.owner], installed.enabled,
              installed.verifiedIdentity == prior.identity,
              installed.digest == prior.digest,
              SemanticVersion(installed.manifest.version) == prior.version.version,
              let process = eligibleMetricProcess(
                  owner      : prior.owner,
                  incarnation: incarnation
              ),
              process.identity == prior.identity,
              process.digest == prior.digest,
              process.metricBinding == binding else { return false }
        return true
    }

    /// sampleResources observes one common batch and applies bounded resource health
    /// state only while the captured process authority remains current.
    func sampleResources(reason: ProcessMetricSampleReason) async throws -> ResourceSampleResult {
        guard !resourceOperationInProgress, !cleanupInProgress,
              pendingMetricWake == nil,
              pendingMetricDetaches.isEmpty else { return .busy }
        resourceOperationInProgress = true
        defer { resourceOperationInProgress = false }
        let capturedWake = pendingMetricWake
        let instant = try currentInstant()
        var captured: [VerifiedAddonIdentity: MetricOwnerSnapshot] = [:]
        for (owner, installed) in catalog {
            guard let snapshot = metricOwnerSnapshot(owner: owner, installed: installed) else { continue }
            captured[snapshot.identity] = snapshot
        }
        let batch: ProcessMetricBatch?
        if reason == .periodic {
            batch = try await processMetrics.sampleIfDue(at: instant.monotonic)
        } else {
            batch = try await processMetrics.sampleAll(
                reason: reason,
                at    : instant.monotonic
            )
        }
        guard let batch else { return .notDue }
        guard capturedWake == pendingMetricWake else {
            return .sampled(batch.cpuAccounting.map {
                ResourceOwnerObservation(
                    owner         : $0.owner,
                    classification: $0.classification,
                    decision      : nil,
                    status        : .stale
                )
            })
        }
        // Capture CPU and own-RAM authority before any health transition or stop
        // can alter a process used elsewhere in this same physical batch.
        var cpuAuthority: [VerifiedAddonIdentity: Bool] = [:]
        for assessment in batch.cpuAccounting {
            let contributing = batch.samples.filter { $0.chargedOwners.contains(assessment.owner) }
            cpuAuthority[assessment.owner] = captured[assessment.owner].map { prior in
                !contributing.isEmpty
                    && contributing.allSatisfy {
                        isCurrentMetricContributor($0.binding, captured: captured)
                    }
                    && isCurrentMetricOwner(prior)
            } ?? false
        }
        var memoryAssessments: [MemoryAssessment] = []
        memoryAssessments.reserveCapacity(batch.samples.count)
        for sample in batch.samples {
            guard let prior = captured.values.first(where: { $0.binding == sample.binding }),
                  let incarnation = prior.incarnation else { continue }
            memoryAssessments.append(MemoryAssessment(
                owner         : prior.owner,
                identity      : prior.identity,
                incarnation   : incarnation,
                footprintBytes: sample.reduction.footprintBytes,
                isCurrent     : isCurrentMetricContributor(sample.binding, captured: captured)
                    && isCurrentMetricOwner(prior)
            ))
        }

        var observations: [ResourceOwnerObservation] = []
        observations.reserveCapacity(batch.cpuAccounting.count)
        var observationIndex: [VerifiedAddonIdentity: Int] = [:]
        var healthEvents: [VerifiedAddonIdentity: ResourceHealthEvent] = [:]
        for assessment in batch.cpuAccounting {
            let contributing = batch.samples.filter { $0.chargedOwners.contains(assessment.owner) }
            guard let prior = captured[assessment.owner],
                  cpuAuthority[assessment.owner] == true else {
                observationIndex[assessment.owner] = observations.count
                observations.append(ResourceOwnerObservation(
                    owner         : assessment.owner,
                    classification: assessment.classification,
                    decision      : nil,
                    status        : .stale
                ))
                continue
            }
            var status: ResourceOwnerStatus = .current
            if assessment.classification == .moderate {
                if healthStore.snapshot(for: prior.version)?.isQuarantined == true {
                    status = .stale
                } else {
                    cpuAdmissionPaused.insert(prior.identity)
                    healthEvents[prior.identity] = .moderate
                }
            } else if assessment.classification == .noNewViolation,
                      case .complete(let snapshot) = assessment.result,
                      snapshot.available > .zero,
                      (prior.incarnation == nil || prior.binding.map { binding in
                          contributing.contains(where: { $0.binding == binding })
                      } == true),
                      healthStore.snapshot(for: prior.version)?.isQuarantined == false {
                cpuAdmissionPaused.remove(prior.identity)
            }
            observationIndex[assessment.owner] = observations.count
            observations.append(ResourceOwnerObservation(
                owner         : assessment.owner,
                classification: assessment.classification,
                decision      : nil,
                status        : status
            ))
        }

        var severeStops: [(owner: AddonID, incarnation: RuntimeIncarnation)] = []
        for assessment in memoryAssessments where assessment.isCurrent {
            guard var process = processes[assessment.owner],
                  process.incarnation == assessment.incarnation else { continue }
            let result = process.memoryEpisode.observe(
                footprintBytes: assessment.footprintBytes
            )
            processes[assessment.owner]?.memoryEpisode = process.memoryEpisode
            switch result {
            case .unavailable:
                break
            case .withinTarget:
                memoryAdmissionPaused.remove(assessment.identity)
            case .moderate(let isNewEpisode):
                memoryAdmissionPaused.insert(assessment.identity)
                if isNewEpisode,
                   let prior = captured[assessment.identity],
                   healthStore.snapshot(for: prior.version)?.isQuarantined != true,
                   healthEvents[assessment.identity] == nil {
                    healthEvents[assessment.identity] = .moderate
                }
            case .severe:
                memoryAdmissionPaused.insert(assessment.identity)
                healthEvents[assessment.identity] = .severe
                severeStops.append((
                    owner      : assessment.owner,
                    incarnation: assessment.incarnation
                ))
            }
        }

        // CPU and RAM share version health history, so reduce both signals to one
        // event per owner. CPU result status remains CPU-specific; a valid own RAM
        // event can still apply when delegated CPU provenance was stale.
        for identity in healthEvents.keys.sorted(by: {
            $0.addonID.rawValue < $1.addonID.rawValue
        }) {
            guard let event = healthEvents[identity],
                  let prior = captured[identity] else { continue }
            var decision: AddonHealthDecision?
            var recordingFailed = false
            do {
                if event == .moderate,
                   let retry = prior.retryTicket,
                   prior.incarnation == nil {
                    decision = try healthStore.recordModerateDuringRetry(
                        from: retry,
                        at  : instant
                    )
                } else {
                    let session: AddonHealthSession
                    if let existing = prior.healthSession ?? prior.delegatedSession {
                        session = existing
                    } else {
                        _ = try healthStore.register(prior.version)
                        session = try healthStore.bind(
                            prior.version,
                            generation: ConnectionGeneration()
                        )
                        delegatedHealthSessions[prior.owner] = session
                    }
                    decision = try healthStore.record(
                        event == .severe ? .severe : .moderate,
                        from: session,
                        at  : instant
                    )
                }
                if decision == nil {
                    recordingFailed = true
                } else if decision == .quarantine || decision == .stop {
                    processes[prior.owner]?.healthSession = nil
                    delegatedHealthSessions.removeValue(forKey: prior.owner)
                }
            } catch {
                recordingFailed = true
            }
            if let index = observationIndex[identity] {
                let existing = observations[index]
                observations[index] = ResourceOwnerObservation(
                    owner         : existing.owner,
                    classification: existing.classification,
                    decision      : decision,
                    status        : existing.status == .stale
                        ? .stale
                        : recordingFailed ? .recordingFailed : .current
                )
            }
        }

        for stop in severeStops {
            guard processes[stop.owner]?.incarnation == stop.incarnation else { continue }
            requestStopOnce(owner: stop.owner, reason: .stopped)
        }
        return .sampled(observations)
    }

    /// resetProcessMetricsAfterWake drops only measurement continuity after one
    /// qualified host wake. CPU debt and admission state deliberately remain.
    func resetProcessMetricsAfterWake() async throws -> MetricWakeResetResult {
        guard !stopped, archiveQuiescence == nil else { return .completed }
        healthStore.cancelPendingRetries()
        for owner in pendingCrashDecisions.keys {
            healthStore.cancel(owner: owner)
        }
        pendingCrashDecisions.removeAll(keepingCapacity: true)
        for owner in Array(processes.keys) where processes[owner]?.pendingCrashSession != nil {
            healthStore.cancel(owner: owner)
            processes[owner]?.pendingCrashSession = nil
        }
        pendingMetricWake = UUID()
        return try await servicePendingMetricWake()
    }

    /// servicePendingMetricWake performs at most one coalesced reset. A newer wake
    /// observed while the coordinator awaits remains pending for the next host pass.
    private func servicePendingMetricWake() async throws -> MetricWakeResetResult {
        guard let token = pendingMetricWake else { return .completed }
        guard !resourceOperationInProgress, !cleanupInProgress,
              pendingMetricDetaches.isEmpty else { return .deferred }
        resourceOperationInProgress = true
        defer { resourceOperationInProgress = false }
        let instant = try currentInstant()
        try await processMetrics.resetAfterWake(at: instant.monotonic)
#if DEBUG
        await Self.cpuWakeResetCheckpoint?()
#endif
        guard pendingMetricWake == token else { return .deferred }
        guard !stopped, archiveQuiescence == nil else {
            pendingMetricWake = nil
            return .completed
        }
        pendingMetricWake = nil
        return .completed
    }

    func resourceHealthSnapshot(for identity: AddonVersionIdentity) -> AddonHealthSnapshot? {
        healthStore.snapshot(for: identity)
    }

    private func isFreshAdmissionOpen(_ identity: VerifiedAddonIdentity) -> Bool {
        guard !cpuAdmissionPaused.contains(identity),
              !memoryAdmissionPaused.contains(identity),
              let installed = catalog[identity.addonID],
              installed.verifiedIdentity == identity,
              let version = try? healthVersion(for: installed),
              healthStore.snapshot(for: version)?.isQuarantined != true else {
            return false
        }
        return true
    }

    /// requireFreshAdmissionOpen admits fresh work only through independent CPU and RAM gates plus
    /// durable health. Existing work and lifecycle recovery launches deliberately skip this guard.
    private func requireFreshAdmissionOpen(owner: AddonID) throws {
        guard let identity = catalog[owner]?.verifiedIdentity,
              isFreshAdmissionOpen(identity) else {
            throw failure(.resourceDenied)
        }
    }

    /// requireNewConsumerFreshAdmissionOpen protects only acquisition-created
    /// canonical interests. Reusing an existing interest creates no new consumer
    /// work and remains possible while that consumer is paused.
    private func requireNewConsumerFreshAdmissionOpen(
        _ acquisition: ServiceAcquisition,
        owner        : AddonID
    ) throws {
        if acquisition.createdNewConsumerInterest {
            try requireFreshAdmissionOpen(owner: owner)
        }
    }

    private func requireProcessOwner(_ incarnation: RuntimeIncarnation) throws -> AddonID {
        guard let owner = processes.first(where: { $0.value.incarnation == incarnation })?.key else {
            throw failure(.sessionRevoked)
        }
        return owner
    }

    /// eligibleMetricProcess checks runtime authority without treating an observed
    /// PID or a protocol connection as the source of verified ownership.
    private func eligibleMetricProcess(
        owner      : AddonID,
        incarnation: RuntimeIncarnation
    ) -> ProcessRecord? {
        guard !stopped, archiveQuiescence == nil, !disabledOwners.contains(owner),
              let process = processes[owner], process.incarnation == incarnation,
              !process.stopRequested, !process.connectionClosed,
              let installed = catalog[owner], installed.enabled,
              installed.verifiedIdentity == process.identity,
              installed.digest == process.digest,
              resolution?.acceptedAddons.contains(owner) == true else { return nil }
        if case .stopping = process.phase { return nil }
        return process
    }

    /// revokeMetricProcess removes logical health authority synchronously. Physical
    /// coordinator detachment follows through the common awaited cleanup barrier.
    private func revokeMetricProcess(
        owner               : AddonID,
        process             : ProcessRecord,
        preserveCrashSession: Bool = false
    ) {
        if preserveCrashSession {
            processes[owner]?.pendingCrashSession = process.healthSession
                ?? process.pendingCrashSession
        } else {
            healthStore.cancel(owner: owner)
            processes[owner]?.pendingCrashSession = nil
        }
        delegatedHealthSessions.removeValue(forKey: owner)
        processes[owner]?.healthSession = nil
        if let binding = process.metricBinding {
            pendingMetricDetaches[process.incarnation] = binding
            processes[owner]?.metricBinding = nil
        }
    }

    private func drainPendingMetricDetaches() async {
        let pending = pendingMetricDetaches
        pendingMetricDetaches.removeAll(keepingCapacity: true)
        for binding in pending.values {
            _ = await processMetrics.unregister(binding)
        }
    }

    /// assignPublication creates one host-issued feature binding after pooled admission.
    func assignPublication(
        owner                : AddonID,
        featureID            : String,
        instanceID           : UUID,
        assetPrivacyPartition: AssetPrivacyPartition = .addonOwned
    ) async throws -> PublicationID {
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        pruneAssignments(owner: owner)
        guard let installed = catalog[owner],
              installed.manifest.features.contains(where: { $0.id == featureID }),
              resolution?.enabledFeatures.contains(where: {
                $0.addonID == owner && $0.featureID == featureID
              }) == true else { throw failure(.permissionDenied) }
        if let existing = assignments.first(where: {
            $0.key.addonID == owner && $0.key.instanceID == instanceID
        }) {
            guard existing.value.featureID == featureID,
                  existing.value.assetPrivacyPartition == assetPrivacyPartition else {
                throw failure(.permissionDenied)
            }
            return existing.key
        }
        if let process = processes[owner], case .connected = process.phase {
            throw failure(.sessionRevoked)
        }
        guard assignments.values.filter({ $0.owner == owner }).count < 16 else {
            throw failure(.resourceDenied)
        }
        do {
            try await growPool(
                owner: owner,
                by   : Self.assignmentBytes
            )
            try validateOperation(operation, owner: owner)
            let id = PublicationID(
                addonID   : owner,
                instanceID: instanceID,
                sessionID : UUID()
            )
            assignments[id] = Assignment(
                owner                : owner,
                publisher            : installed.verifiedIdentity.publisher,
                digest               : installed.digest,
                featureID            : featureID,
                assetPrivacyPartition: assetPrivacyPartition,
                eligibility          : .available,
                authorityRevision    : authorityRevision,
                assignmentToken      : UUID(),
                hasPublished         : false
            )
            ownerPools[owner]?.restorationSealed = true
            await finishAdmissionAndDrain(operation)
            return id
        } catch {
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// requestLaunch reserves physical and ingress capacity before adapter handoff.
    func requestLaunch(
        owner: AddonID,
        retry: AddonRetryTicket? = nil
    ) async throws -> RuntimeLaunchID {
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        guard let installed = catalog[owner], installed.enabled,
              resolution?.acceptedAddons.contains(owner) == true,
              processes[owner] == nil,
              pendingCrashDecisions[owner] == nil else {
            throw failure(.resourceDenied)
        }
        let version = try healthVersion(for: installed)
        try requireLaunchHealthOpen(version, retry: retry)
        var provider: ResourceReservation?
        do {
            if let retry {
                let demanded = await hasCurrentRecoveryDemand(
                    owner   : owner,
                    provider: installed.verifiedIdentity
                )
                try validateOperation(operation, owner: owner)
                try requireLaunchHealthOpen(version, retry: retry)
                if !demanded {
                    _ = try healthStore.consume(
                        retry,
                        demandExists: false,
                        isEnabled   : true,
                        at          : currentInstant()
                    )
                    throw failure(.dependencyUnavailable)
                }
            }
            let admittedProvider = try await resourceAccess.admit(
                .provider,
                owner: owner
            )
            provider = admittedProvider
            try validateOperation(operation, owner: owner)
            try requireLaunchHealthOpen(version, retry: retry)
            try await growPool(
                owner: owner,
                by   : processAdmissionBytes
            )
            try validateOperation(operation, owner: owner)
            try requireLaunchHealthOpen(version, retry: retry)
            let demand = retry == nil ? false : await hasCurrentRecoveryDemand(
                owner   : owner,
                provider: installed.verifiedIdentity
            )
            try validateOperation(operation, owner: owner)
            try requireLaunchHealthOpen(version, retry: retry)
            let now = try currentInstant()
            if let retry, !demand {
                _ = try healthStore.consume(
                    retry,
                    demandExists: false,
                    isEnabled   : true,
                    at          : now
                )
                throw failure(.dependencyUnavailable)
            }
            var preparedHealth = healthStore
            if let retry {
                guard try preparedHealth.consume(
                    retry,
                    demandExists: true,
                    isEnabled   : true,
                    at          : now
                ) else { throw failure(.resourceDenied) }
            }
            _ = try preparedHealth.register(version)
            let healthSession = try preparedHealth.bind(
                version,
                generation: ConnectionGeneration()
            )
            let launchID = RuntimeLaunchID()
            let incarnation = RuntimeIncarnation()
            let start = RuntimeStartDelivery(
                launchID                  : launchID,
                incarnation               : incarnation,
                identity                  : installed.verifiedIdentity,
                digest                    : installed.digest,
                maximumIngressBytes       : maximumEnvelopeBytes,
                maximumStorageIngressBytes: storageIngressCapacity,
                maximumAssetIngressBytes  : assetIngressCapacity,
                maximumServiceIngressBytes: serviceFramesEnabled ? ServiceFrameCodec.maximumEncodedBytes : 0,
                maximumDeliveryBytes      : deliveryCapacity
            )
            let record = ProcessRecord(
                launchID          : launchID,
                incarnation       : incarnation,
                identity          : installed.verifiedIdentity,
                digest            : installed.digest,
                providerReservation: admittedProvider,
                coldStartDeadline : now.monotonic + .seconds(2),
                assembler         : BoundedAssetTransferAssembler(
                    incarnation: incarnation,
                    clock      : clock,
                    decoder    : assetDecoder
                ),
                phase             : .pending,
                stopRequested     : false,
                healthSession     : healthSession
            )
            processes[owner] = record
            launches[launchID] = owner
            healthStore = preparedHealth
            delegatedHealthSessions.removeValue(forKey: owner)
            guard adapter.tryHandoff(
                incarnation: incarnation,
                delivery   : .start(start)
            ) == .accepted else {
                processes.removeValue(forKey: owner)
                launches.removeValue(forKey: launchID)
                healthStore.cancel(owner: owner)
                try await resourceAccess.release(
                    admittedProvider.id,
                    owner: owner
                )
                provider = nil
                await shrinkPoolToCurrent(owner: owner)
                throw failure(.dependencyUnavailable)
            }
            ownerPools[owner]?.restorationSealed = true
            await finishAdmissionAndDrain(operation)
            return launchID
        } catch {
            if processes[owner] == nil, let provider {
                try? await resourceAccess.release(
                    provider.id,
                    owner: owner
                )
            }
            if processes[owner] == nil {
                await shrinkPoolToCurrent(owner: owner)
            }
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    private func healthVersion(for installed: InstalledAddon) throws -> AddonVersionIdentity {
        guard let version = SemanticVersion(installed.manifest.version) else {
            throw failure(.invalidPayload)
        }
        return try AddonVersionIdentity(
            verifiedIdentity: installed.verifiedIdentity,
            version         : version
        )
    }

    private func requireLaunchHealthOpen(
        _ version: AddonVersionIdentity,
        retry    : AddonRetryTicket?
    ) throws {
        guard pendingCrashDecisions[version.verifiedIdentity.addonID] == nil,
              healthStore.snapshot(for: version)?.isQuarantined != true else {
            throw failure(.resourceDenied)
        }
        let pending = healthStore.pendingRetryTickets.first { $0.version == version }
        guard pending == retry else { throw failure(.resourceDenied) }
    }

    private func hasCurrentRecoveryDemand(
        owner   : AddonID,
        provider: VerifiedAddonIdentity
    ) async -> Bool {
        guard let now = try? currentInstant() else { return false }
        if dispatcher.hasCurrentQueuedDemand(owner: owner, at: now.monotonic) {
            return true
        }
        let deadline = try? await broker.currentDemandDeadline(
            for: provider,
            at : now
        )
#if DEBUG
        await Self.crashDemandCheckpoint?()
#endif
        guard let fresh = try? currentInstant() else { return false }
        if dispatcher.hasCurrentQueuedDemand(owner: owner, at: fresh.monotonic) {
            return true
        }
        return deadline.map { $0 > fresh.monotonic } ?? false
    }

    /// attach opens fresh component sessions, composing generation only for negotiated 1.3.
    func attach(
        launchID: RuntimeLaunchID,
        offer   : ProtocolOffer
    ) async throws -> RuntimeConnection {
        guard let owner = launches[launchID],
              let process = processes[owner],
              process.launchID == launchID,
              case .pending = process.phase,
              let installed = catalog[owner] else { throw failure(.sessionRevoked) }
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        let ids = assignments.filter { $0.value.owner == owner }.map(\.key)
        let additionalBytes = try publicationState.connectionAdmissionBytes(
            identity: installed.verifiedIdentity
        )
        var publicationConnection: PublicationConnection?
        var serviceSession: ServiceSession?
        do {
            try await growPool(
                owner: owner,
                by   : additionalBytes
            )
            try validateOperation(operation, owner: owner)
            let openedConnection = try publicationState.openConnection(
                identity                  : installed.verifiedIdentity,
                verifiedDigest            : installed.digest,
                manifestProtocol          : installed.manifest.compatibility.cascadeProtocol,
                offer                     : offer,
                authorizedPublications    : ids,
                supportsKeyedStorageFrames: storageFramesEnabled,
                supportsAssetFrames       : assetFramesEnabled,
                serviceHost               : serviceFramesEnabled,
                subscriptionHost          : serviceSubscriptionsEnabled
            )
            publicationConnection = openedConnection
            let registeredSession: ServiceSession
            if openedConnection.negotiatedProtocol.serviceInvocationFrameProfile == .v1_3 {
                registeredSession = try await broker.registerSession(identity: installed.verifiedIdentity,
                                                                     generation: openedConnection.generation)
            } else {
                registeredSession = try await broker.registerSession(identity: installed.verifiedIdentity)
            }
            serviceSession = registeredSession
            try validateOperation(operation, owner: owner)
            guard let current = processes[owner], current.launchID == launchID,
                  case .pending = current.phase,
                  try currentInstant().monotonic < current.coldStartDeadline else {
                throw failure(.sessionRevoked)
            }
            let connection = RuntimeConnection(
                token                : UUID(),
                incarnation          : current.incarnation,
                identity             : current.identity,
                digest               : current.digest,
                publicationConnection: openedConnection,
                serviceSession       : registeredSession,
                authorityRevision    : authorityRevision
            )
            var updated = current
            updated.phase = .connected(connection)
            processes[owner] = updated
            launches.removeValue(forKey: launchID)
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            _ = try? await pumpReady()
            _ = try connectedOwner(connection)
            return connection
        } catch {
            if let publicationConnection {
                publicationState.closeConnection(publicationConnection)
            }
            if let serviceSession {
                await broker.disconnect(serviceSession)
            }
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// installDelivery records the synchronous accepted handoff before any suspension.
    private func installDelivery(
        _ credit   : DeliveryCredit,
        owner      : AddonID,
        incarnation: RuntimeIncarnation
    ) {
        precondition(
            processes[owner]?.incarnation == incarnation && processes[owner]?.credits.delivery == nil
        )
        processes[owner]?.credits.delivery = credit
    }

    /// releaseDelivery drops only an exact incarnation's current payload receipt. Canonical
    /// dispatcher/broker completion remains responsible for the separate job and command lifetimes.
    private func releaseDelivery(
        _ credit   : DeliveryCredit,
        owner      : AddonID,
        incarnation: RuntimeIncarnation
    ) {
        guard processes[owner]?.incarnation == incarnation,
            processes[owner]?.credits.delivery == credit
        else { return }
        processes[owner]?.credits.delivery = nil
        switch credit {
        case .storageReserved, .assetReserved, .serviceReserved:
            // A runtime-only reservation has no adapter payload to dispose.
            return
        default:
            break
        }
        adapter.deliveryWasReceived(incarnation: incarnation)
    }

    /// claimIngress reserves one invocation before taking its adapter value. Recheck this after
    /// admission awaits; an earlier empty-slot observation is never transferable authority.
    private func claimIngress(
        _ handle   : RuntimeIngressHandle,
        owner      : AddonID,
        incarnation: RuntimeIncarnation
    ) throws -> IngressClaim {
        guard processes[owner]?.incarnation == incarnation,
            handle.incarnation == incarnation,
            processes[owner]?.credits.ingress == nil
        else { throw failure(.invalidPayload) }
        let claim = IngressClaim(
            id    : UUID(),
            handle: .publication(handle)
        )
        processes[owner]?.credits.ingress = claim
        return claim
    }

    /// disposeIngress linearizes the actual adapter disposition and matching scalar clear.
    /// Stopping processes remain eligible for cleanup; an observed exit already disposed their slots.
    private func disposeIngress(
        _ claim    : IngressClaim,
        owner      : AddonID,
        incarnation: RuntimeIncarnation,
        disposition: IngressDisposition
    ) {
        guard processes[owner]?.incarnation == incarnation,
            processes[owner]?.credits.ingress == claim
        else { return }
        switch claim.handle {
        case .publication(let handle):
            switch disposition {
            case .finish:
                adapter.finishIngress(
                    handle,
                    incarnation: incarnation
                )
            case .cancel:
                adapter.cancelIngress(
                    handle,
                    incarnation: incarnation
                )
            case .reject:
                adapter.rejectIngress(
                    handle,
                    incarnation: incarnation
                )
            }
        case .storage(let handle):
            guard let storageAdapter = adapter as? any AddonRuntimeStorageAdapter else { return }
            switch disposition {
            case .finish:
                storageAdapter.finishStorageIngress(
                    handle,
                    incarnation: incarnation
                )
            case .cancel:
                storageAdapter.cancelStorageIngress(
                    handle,
                    incarnation: incarnation
                )
            case .reject:
                storageAdapter.rejectStorageIngress(
                    handle,
                    incarnation: incarnation
                )
            }
        case .service(let token, let encodedBytes, let sequence, let kind):
            let handle = RuntimeServiceIngressHandle(token: token, incarnation: incarnation, encodedBytes: encodedBytes,
                                                    sequence: sequence, kind: kind)
            guard let serviceAdapter = adapter as? any AddonRuntimeServiceAdapter else { return }
            switch disposition {
            case .finish: serviceAdapter.finishServiceIngress(handle, incarnation: incarnation)
            case .cancel: serviceAdapter.cancelServiceIngress(handle, incarnation: incarnation)
            case .reject: serviceAdapter.rejectServiceIngress(handle, incarnation: incarnation)
            }
        case .asset(let handle):
            guard let assetAdapter = adapter as? any AddonRuntimeAssetAdapter else { return }
            switch disposition {
            case .finish:
                assetAdapter.finishAssetIngress(
                    handle,
                    incarnation: incarnation
                )
            case .cancel:
                assetAdapter.cancelAssetIngress(
                    handle,
                    incarnation: incarnation
                )
            case .reject:
                assetAdapter.rejectAssetIngress(
                    handle,
                    incarnation: incarnation
                )
            }
        }
        processes[owner]?.credits.ingress = nil
    }

    /// RuntimeStorageOutcome records known backend results without retaining request or response bytes.
    enum RuntimeStorageOutcome: Equatable, Sendable {
        case value
        case missing
        case acknowledged
        case outcomeUnknown
        case failure(AddonFailure.Code)
    }

    /// RuntimeStorageReplyDisposition separates backend outcome from adapter reply ownership.
    enum RuntimeStorageReplyDisposition: Equatable, Sendable {
        case handedOff
        case rejectedBeforeHandoff
        case suppressed
    }

    /// RuntimeStorageRequestResult returns only scalars after the protected workspace has unwound.
    enum RuntimeStorageRequestResult: Equatable, Sendable {
        case refused(AddonFailure.Code)
        case completed(
            RuntimeStorageOutcome,
            RuntimeStorageReplyDisposition
        )
    }

    /// storageConnection derives authorization only from the currently stored host connection.
    private func storageConnection(_ supplied: RuntimeConnection) throws -> RuntimeConnection {
        try Task.checkCancellation()
        let owner = try connectedOwner(supplied)
        guard let process = processes[owner], case .connected(let current) = process.phase,
            let installed = catalog[owner], installed.verifiedIdentity == current.identity,
            installed.digest == current.digest, resolution?.acceptedAddons.contains(owner) == true
        else { throw failure(.sessionRevoked) }
        guard storageFramesEnabled,
            current.publicationConnection.negotiatedProtocol.storageFrameProfile == .v1_1
        else { throw failure(.versionConflict) }
        guard ownerPools[owner]?.storageOwnGranted == true else { throw failure(.permissionDenied) }
        return current
    }

    /// validateStorageSlots rechecks scalar ownership after every suspension before transferring authority.
    private func validateStorageSlots(
        _ ingress  : RuntimeStorageIngressHandle,
        connection : RuntimeConnection,
        operation  : AdmissionOperation? = nil,
        claim      : IngressClaim? = nil,
        reservation: UUID? = nil
    ) throws -> RuntimeConnection {
        let current = try storageConnection(connection)
        let owner   = current.identity.addonID
        if let operation {
            try validateOperation(
                operation,
                owner: owner
            )
        }
        guard ingress.incarnation == current.incarnation, ingress.encodedBytes > 0,
            ingress.encodedBytes <= storageIngressCapacity, ingress.sequence > 0,
            ingress.sequence > (processes[owner]?.credits.lastStorageSequence ?? UInt64.max)
        else { throw failure(.invalidPayload) }
        guard processes[owner]?.credits.ingress == claim,
            processes[owner]?.credits.delivery == reservation.map(DeliveryCredit.storageReserved)
        else { throw failure(.resourceDenied) }
        return current
    }

    /// receiveStorageRequest protects raw and decoded values until the scalar operation result returns.
    func receiveStorageRequest(
        _ ingress : RuntimeStorageIngressHandle,
        connection: RuntimeConnection
    ) async -> RuntimeStorageRequestResult {
        let storageAdapter = adapter as? any AddonRuntimeStorageAdapter
        let owner          = connection.identity.addonID
        var operation  : AdmissionOperation?
        var claim      : IngressClaim?
        var reservation: UUID?
        let result     : RuntimeStorageRequestResult
        do {
            _ = try validateStorageSlots(
                ingress,
                connection: connection
            )
            guard let coordinator = storageCoordinator, let storageAdapter else {
                throw failure(.dependencyUnavailable)
            }
            let acceptedOperation = try await beginAdmission(owner: owner)
            operation = acceptedOperation
            _ = try validateStorageSlots(
                ingress,
                connection: connection,
                operation : acceptedOperation
            )
            let acceptedClaim = IngressClaim(
                id    : UUID(),
                handle: .storage(ingress)
            )
            let nonce = UUID()
            processes[owner]?.credits.ingress = acceptedClaim
            installDelivery(
                .storageReserved(nonce),
                owner      : owner,
                incarnation: connection.incarnation
            )
            claim = acceptedClaim
            reservation = nonce
            result = try await governor.withAssetDecodeReservation(
                bytes: Self.scratchBytes,
                owner: owner
            ) {
                await self.executeStorageRequest(
                    ingress,
                    connection    : connection,
                    operation     : acceptedOperation,
                    claim         : acceptedClaim,
                    reservation   : nonce,
                    coordinator   : coordinator,
                    storageAdapter: storageAdapter
                )
            }
        } catch {
            result = .refused(Self.storageFailureCode(error))
        }
        if let reservation {
            releaseDelivery(
                .storageReserved(reservation),
                owner      : owner,
                incarnation: connection.incarnation
            )
        }
        if let claim {
            disposeIngress(
                claim,
                owner      : owner,
                incarnation: connection.incarnation,
                disposition: .reject
            )
        } else if processes[owner]?.credits.ingress?.handle != .storage(ingress) {
            storageAdapter?.rejectStorageIngress(
                ingress,
                incarnation: ingress.incarnation
            )
        }
        if let operation { await finishAdmissionAndDrain(operation) }
        return result
    }

    /// executeStorageRequest never throws after the coordinator accepts a decoded request.
    /// Its actor-isolated final checks are immediately adjacent to backend and adapter handoffs.
    private func executeStorageRequest(
        _ ingress     : RuntimeStorageIngressHandle,
        connection    : RuntimeConnection,
        operation     : AdmissionOperation,
        claim         : IngressClaim,
        reservation   : UUID,
        coordinator   : AddonStorageCoordinator,
        storageAdapter: any AddonRuntimeStorageAdapter
    ) async -> RuntimeStorageRequestResult {
        let owner       = connection.identity.addonID
        var transferred = false
        defer {
            disposeIngress(
                claim,
                owner      : owner,
                incarnation: connection.incarnation,
                disposition: transferred ? .finish : .reject
            )
        }
        let request   : StorageRequest
        let capability: AddonStorageCoordinator.Owner
        do {
            let current = try validateStorageSlots(
                ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation
            )
            capability = try await coordinator.owner(for: current.identity)
            _ = try validateStorageSlots(
                ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation
            )
            guard
                let raw = storageAdapter.takeStorageIngress(
                    ingress,
                    incarnation: current.incarnation
                )
            else { throw failure(.invalidPayload) }
            transferred = true
            guard raw.count == ingress.encodedBytes else { throw failure(.invalidPayload) }
            request = try StorageFrameCodec.decodeRequest(
                raw,
                profile: current.publicationConnection.negotiatedProtocol.storageFrameProfile
            )
            _ = try validateStorageSlots(
                ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation
            )
        } catch { return .refused(Self.storageFailureCode(error)) }
        processes[owner]?.credits.lastStorageSequence = ingress.sequence
        let backendResult = await coordinator.executeKeyedRequest(
            request,
            owner: capability
        )
        let outcome: RuntimeStorageOutcome
        let kind   : StorageResultKind
        var value  : Data?
        var code   : AddonFailure.Code?
        switch backendResult {
        case .acknowledged:
            outcome = .acknowledged
            kind = .acknowledged
        case .read(let bytes):
            outcome = bytes == nil ? .missing : .value
            kind = bytes == nil ? .missing : .value
            value = bytes
        case .outcomeUnknown:
            outcome = .outcomeUnknown
            kind = .failure
            code = .outcomeUnknown
        case .refused(let refusal):
            let failureCode: AddonFailure.Code
            switch refusal {
            case .invalidRequest: failureCode = .invalidPayload
            case .invalidOwner, .cancelled: failureCode = .sessionRevoked
            case .unavailable: failureCode = .dependencyUnavailable
            case .busy: failureCode = .resourceDenied
            case .readFailed(let readCode): failureCode = readCode
            }
            outcome = .failure(failureCode)
            kind = .failure
            code = failureCode
        }
        do {
            let response = try StorageResponse(
                requestID    : request.requestID,
                operation    : request.operation,
                result       : kind,
                value        : value,
                failureCode  : code,
                failureReason: code.map { _ in "The storage request could not be completed." }
            )
            let encoded = try StorageFrameCodec.encode(
                response,
                profile: .v1_1
            )
            let payload = encoded.withUnsafeBytes { Data($0) }
            let receipt = RuntimeStorageReceipt(
                token          : UUID(),
                incarnation    : connection.incarnation,
                connectionToken: connection.token,
                sequence       : ingress.sequence,
                requestID      : request.requestID,
                operation      : request.operation
            )
            _ = try storageConnection(connection)
            try validateOperation(
                operation,
                owner: owner
            )
            guard processes[owner]?.credits.ingress == claim,
                processes[owner]?.credits.delivery == .storageReserved(reservation),
                processes[owner]?.credits.lastStorageSequence == ingress.sequence
            else { throw failure(.sessionRevoked) }
            let handedOff = storageAdapter.tryHandoff(
                incarnation: connection.incarnation,
                delivery   : .storageResponse(
                    RuntimeStorageResponseDelivery(
                        receipt: receipt,
                        payload: payload
                    )
                )
            )
            if handedOff == .accepted {
                processes[owner]?.credits.delivery = .storageAccepted(receipt)
                return .completed(
                    outcome,
                    .handedOff
                )
            }
            releaseDelivery(
                .storageReserved(reservation),
                owner      : owner,
                incarnation: connection.incarnation
            )
            return .completed(
                outcome,
                .rejectedBeforeHandoff
            )
        } catch {
            releaseDelivery(
                .storageReserved(reservation),
                owner      : owner,
                incarnation: connection.incarnation
            )
            return .completed(
                outcome,
                .suppressed
            )
        }
    }

    /// receiveStorageReceipt releases only the current accepted payload, without altering work state.
    func receiveStorageReceipt(
        _ receipt : RuntimeStorageReceipt,
        connection: RuntimeConnection
    ) -> Bool {
        guard let current = try? storageConnection(connection), receipt.incarnation == current.incarnation,
            receipt.connectionToken == current.token,
            processes[current.identity.addonID]?.credits.delivery == .storageAccepted(receipt)
        else { return false }
        releaseDelivery(
            .storageAccepted(receipt),
            owner      : current.identity.addonID,
            incarnation: current.incarnation
        )
        return true
    }

    /// storageFailureCode bounds pre-handoff refusals without preserving arbitrary backend errors.
    private static func storageFailureCode(_ error: any Error) -> AddonFailure.Code {
        if error is CancellationError { return .sessionRevoked }
        if let coordinatorFailure = error as? AddonStorageCoordinator.Failure {
            switch coordinatorFailure {
            case .busy: return .resourceDenied
            case .unavailable, .invalidOwner: return .dependencyUnavailable
            case .invalidConfiguration: return .invalidPayload
            }
        }
        return (error as? AddonFailure)?.code ?? .invalidPayload
    }

    // MARK: Authenticated asset message ingress

    /// RuntimeAssetOutcome records the known backend result without retaining request or response bytes.
    enum RuntimeAssetOutcome: Equatable, Sendable {
        case accepted
        case failure(AddonFailure.Code)
    }

    /// RuntimeAssetReplyDisposition separates backend outcome from adapter reply ownership.
    enum RuntimeAssetReplyDisposition: Equatable, Sendable {
        case handedOff
        case rejectedBeforeHandoff
        case suppressed
    }

    /// RuntimeAssetRequestResult returns only scalars after the protected workspace has unwound.
    enum RuntimeAssetRequestResult: Equatable, Sendable {
        case refused(AddonFailure.Code)
        case completed(
            RuntimeAssetOutcome,
            RuntimeAssetReplyDisposition
        )
    }

    /// assetConnection derives asset authorization only from the currently stored host connection.
    /// Asset frames never require a storage.own grant; they only need the negotiated 1.2 profile.
    private func assetConnection(_ supplied: RuntimeConnection) throws -> RuntimeConnection {
        try Task.checkCancellation()
        let owner = try connectedOwner(supplied)
        guard let process = processes[owner], case .connected(let current) = process.phase,
            let installed = catalog[owner], installed.verifiedIdentity == current.identity,
            installed.digest == current.digest, resolution?.acceptedAddons.contains(owner) == true
        else { throw failure(.sessionRevoked) }
        guard assetFramesEnabled,
            current.publicationConnection.negotiatedProtocol.assetFrameProfile == .v1
        else { throw failure(.versionConflict) }
        return current
    }

    /// validateAssetSlots rechecks scalar ownership after every suspension before transferring authority.
    private func validateAssetSlots(
        _ ingress  : RuntimeAssetIngressHandle,
        connection : RuntimeConnection,
        operation  : AdmissionOperation? = nil,
        claim      : IngressClaim? = nil,
        reservation: UUID? = nil,
        checkingSequence: Bool = true
    ) throws -> RuntimeConnection {
        let current = try assetConnection(connection)
        let owner   = current.identity.addonID
        if let operation {
            try validateOperation(
                operation,
                owner: owner
            )
        }
        guard ingress.incarnation == current.incarnation, ingress.encodedBytes > 0,
            ingress.encodedBytes <= assetIngressCapacity, ingress.sequence > 0
        else { throw failure(.invalidPayload) }
        if checkingSequence {
            guard ingress.sequence > (processes[owner]?.lastAssetSequence ?? UInt64.max) else {
                throw failure(.invalidPayload)
            }
        }
        guard processes[owner]?.credits.ingress == claim,
            processes[owner]?.credits.delivery == reservation.map(DeliveryCredit.assetReserved)
        else { throw failure(.resourceDenied) }
        return current
    }

    /// assetBinding derives the immutable host binding from the canonical installed assignment.
    private func assetBinding(
        publicationID: PublicationID,
        connection   : RuntimeConnection
    ) throws -> AssetTransferBinding {
        let scope = try importAssetScope(
            publicationID: publicationID,
            connection   : connection
        )
        guard let assignment = assignments[publicationID],
            assignment.owner == scope.identity.addonID,
            publicationID.addonID == scope.identity.addonID else { throw failure(.permissionDenied) }
        return AssetTransferBinding(
            incarnation    : connection.incarnation,
            connectionToken: connection.token,
            publicationID  : publicationID,
            assignmentToken: assignment.assignmentToken
        )
    }

    /// validateAssetTransfer rechecks host-retained binding authority without granting new scope.
    private func validateAssetTransfer(
        _ state     : AssetTransferState,
        request     : AssetTransferRequest,
        connection  : RuntimeConnection
    ) throws {
        guard request.transferID == state.transferID,
            state.binding.incarnation == connection.incarnation,
            state.binding.connectionToken == connection.token,
            assignments[state.binding.publicationID]?.assignmentToken == state.binding.assignmentToken
        else { throw failure(.sessionRevoked) }
        _ = try importAssetScope(
            publicationID: state.binding.publicationID,
            connection   : connection
        )
    }

    /// ImportedAlias pairs the committed host handle with the exact scope used for rollback.
    private struct ImportedAlias {
        let handle: AssetState.AssetHandle
        let scope : AssetState.Scope
    }

    /// AssetRollback releases only the newly minted alias or transfer when a reply is suppressed.
    private enum AssetRollback {
        case transfer(owner: AddonID, assembler: BoundedAssetTransferAssembler, binding: AssetTransferBinding, transferID: UUID)
        case alias(owner: AddonID, assetID: String, scope: AssetState.Scope)
    }

    /// receiveAssetRequest protects raw and decoded values until the scalar operation result returns.
    func receiveAssetRequest(
        _ ingress : RuntimeAssetIngressHandle,
        connection: RuntimeConnection
    ) async -> RuntimeAssetRequestResult {
        let assetAdapter = adapter as? any AddonRuntimeAssetAdapter
        let owner        = connection.identity.addonID
        var operation  : AdmissionOperation?
        var claim      : IngressClaim?
        var reservation: UUID?
        let result     : RuntimeAssetRequestResult
        do {
            _ = try validateAssetSlots(
                ingress,
                connection: connection
            )
            guard let assetAdapter else { throw failure(.dependencyUnavailable) }
            let acceptedOperation = try await beginAdmission(owner: owner)
            operation = acceptedOperation
            _ = try validateAssetSlots(
                ingress,
                connection: connection,
                operation : acceptedOperation
            )
            let acceptedClaim = IngressClaim(
                id    : UUID(),
                handle: .asset(ingress)
            )
            let nonce = UUID()
            processes[owner]?.credits.ingress = acceptedClaim
            installDelivery(
                .assetReserved(nonce),
                owner      : owner,
                incarnation: connection.incarnation
            )
            claim = acceptedClaim
            reservation = nonce
            result = try await governor.withAssetDecodeReservation(
                bytes: Self.scratchBytes,
                owner: owner
            ) {
                await self.executeAssetRequest(
                    ingress,
                    connection  : connection,
                    operation   : acceptedOperation,
                    claim       : acceptedClaim,
                    reservation : nonce,
                    assetAdapter: assetAdapter
                )
            }
        } catch {
            result = .refused(Self.assetFailureCode(error))
        }
        if let reservation {
            releaseDelivery(
                .assetReserved(reservation),
                owner      : owner,
                incarnation: connection.incarnation
            )
        }
        if let claim {
            disposeIngress(
                claim,
                owner      : owner,
                incarnation: connection.incarnation,
                disposition: .reject
            )
        } else if processes[owner]?.credits.ingress?.handle != .asset(ingress) {
            assetAdapter?.rejectAssetIngress(
                ingress,
                incarnation: ingress.incarnation
            )
        }
        if let operation { await finishAdmissionAndDrain(operation) }
        return result
    }

    /// executeAssetRequest never throws after the authenticated parse. Its actor-isolated final
    /// checks are immediately adjacent to adapter handoff, so no actor suspension sits between.
    private func executeAssetRequest(
        _ ingress     : RuntimeAssetIngressHandle,
        connection    : RuntimeConnection,
        operation     : AdmissionOperation,
        claim         : IngressClaim,
        reservation   : UUID,
        assetAdapter  : any AddonRuntimeAssetAdapter
    ) async -> RuntimeAssetRequestResult {
        let owner       = connection.identity.addonID
        var transferred = false
        defer {
            disposeIngress(
                claim,
                owner      : owner,
                incarnation: connection.incarnation,
                disposition: transferred ? .finish : .reject
            )
        }
        let request: AssetTransferRequest
        do {
            let current = try validateAssetSlots(
                ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation
            )
            guard
                let raw = assetAdapter.takeAssetIngress(
                    ingress,
                    incarnation: current.incarnation
                )
            else { throw failure(.invalidPayload) }
            transferred = true
            guard raw.count == ingress.encodedBytes else { throw failure(.invalidPayload) }
            request = try AssetTransferFrameCodec.decodeRequest(
                raw,
                profile: current.publicationConnection.negotiatedProtocol.assetFrameProfile
            )
            _ = try validateAssetSlots(
                ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation
            )
        } catch { return .refused(Self.assetFailureCode(error)) }
        // The authenticated sequence advances immediately before dispatch, including failures.
        processes[owner]?.lastAssetSequence = ingress.sequence
        var outcome: RuntimeAssetOutcome = .accepted
        var rollback: AssetRollback?
        var response: AssetTransferResponse
        do {
            (response, rollback) = try await dispatchAssetRequest(
                request,
                ingress    : ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation
            )
        } catch {
            let code = Self.assetFailureCode(error)
            outcome = .failure(code)
            guard
                let failure = try? AssetTransferResponse(
                    requestID    : request.requestID,
                    operation    : request.operation,
                    result       : .failure,
                    failureCode  : code,
                    failureReason: "The asset request could not be completed."
                )
            else { return .refused(code) }
            response = failure
        }
        do {
            let current = try validateAssetSlots(
                ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation,
                checkingSequence: false
            )
            let encoded = try AssetTransferFrameCodec.encode(
                response,
                profile: current.publicationConnection.negotiatedProtocol.assetFrameProfile
            )
            let receipt = RuntimeAssetReceipt(
                token          : UUID(),
                incarnation    : current.incarnation,
                connectionToken: current.token,
                sequence       : ingress.sequence,
                requestID      : request.requestID,
                operation      : request.operation
            )
            _ = try validateAssetSlots(
                ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation,
                checkingSequence: false
            )
            guard processes[owner]?.credits.ingress == claim,
                processes[owner]?.credits.delivery == .assetReserved(reservation),
                processes[owner]?.lastAssetSequence == ingress.sequence
            else { throw failure(.sessionRevoked) }
            let handedOff = assetAdapter.tryHandoff(
                incarnation: current.incarnation,
                delivery   : .assetResponse(
                    RuntimeAssetResponseDelivery(
                        receipt: receipt,
                        payload: encoded
                    )
                )
            )
            if handedOff == .accepted {
                processes[owner]?.credits.delivery = .assetAccepted(receipt)
                return .completed(
                    outcome,
                    .handedOff
                )
            }
            releaseDelivery(
                .assetReserved(reservation),
                owner      : owner,
                incarnation: connection.incarnation
            )
            await applyAssetRollback(
                rollback,
                connection: connection
            )
            return .completed(
                outcome,
                .rejectedBeforeHandoff
            )
        } catch {
            releaseDelivery(
                .assetReserved(reservation),
                owner      : owner,
                incarnation: connection.incarnation
            )
            await applyAssetRollback(
                rollback,
                connection: connection
            )
            return .completed(
                outcome,
                .suppressed
            )
        }
    }

    /// dispatchAssetRequest maps one authenticated frame onto the canonical assembler or alias path.
    /// It revalidates canonical authority after every assembler suspension before mutating state.
    private func dispatchAssetRequest(
        _ request: AssetTransferRequest,
        ingress: RuntimeAssetIngressHandle,
        connection: RuntimeConnection,
        operation: AdmissionOperation,
        claim: IngressClaim,
        reservation: UUID
    ) async throws -> (AssetTransferResponse, AssetRollback?) {
        let owner = connection.identity.addonID
        switch request.operation {
        case .begin:
            guard let totalBytes = request.totalBytes, let publicationID = request.publicationID else {
                throw failure(.invalidPayload)
            }
            guard processes[owner]?.assetTransfer == nil else { throw failure(.resourceDenied) }
            guard let assembler = processes[owner]?.assembler else { throw failure(.sessionRevoked) }
            let binding = try assetBinding(
                publicationID: publicationID,
                connection   : connection
            )
            // Publish the exact binding before the assembler suspends in protected admission so a
            // publication end/expiry can invalidate a paused begin. The placeholder transfer ID is
            // never exposed, so no client frame can address it.
            let placeholder = UUID()
            processes[owner]?.assetTransfer = AssetTransferState(
                binding   : binding,
                transferID: placeholder
            )
            let transferID: UUID
            do {
                transferID = try await assembler.begin(
                    totalBytes: totalBytes,
                    binding   : binding
                )
            } catch {
                // A failed begin already refunds or retains its own disposal-only record.
                clearAssetTransfer(owner: owner, transferID: placeholder)
                throw error
            }
            do {
                let current = try validateAssetSlots(
                    ingress,
                    connection : connection,
                    operation  : operation,
                    claim      : claim,
                    reservation: reservation,
                    checkingSequence: false
                )
                guard processes[owner]?.incarnation == current.incarnation,
                    processes[owner]?.assetTransfer?.transferID == placeholder else {
                    throw failure(.sessionRevoked)
                }
                processes[owner]?.assetTransfer = AssetTransferState(
                    binding   : binding,
                    transferID: transferID
                )
            } catch {
                // A throwing post-begin authority check must still revoke the exact transfer
                // instead of dropping the runtime identity and leaking the assembly charge.
                await revokeAssetTransfer(
                    assembler,
                    transferID: transferID,
                    binding   : binding
                )
                clearAssetTransfer(owner: owner, transferID: placeholder)
                throw error
            }
            return (
                try AssetTransferResponse(
                    requestID : request.requestID,
                    operation : .begin,
                    result    : .begun,
                    transferID: transferID
                ),
                .transfer(owner: owner, assembler: assembler, binding: binding, transferID: transferID)
            )
        case .chunk:
            guard let state = processes[owner]?.assetTransfer else { throw failure(.resourceDenied) }
            do {
                try validateAssetTransfer(
                    state,
                    request   : request,
                    connection: connection
                )
            } catch {
                // Only the exact transfer may be revoked; a foreign transfer ID is refused
                // without clearing the live slot.
                if request.transferID == state.transferID {
                    await revokeExactAssetTransfer(
                        owner: owner,
                        state: state
                    )
                }
                throw error
            }
            guard let assembler = processes[owner]?.assembler,
                let offset = request.offset, let bytes = request.bytes else {
                throw failure(.invalidPayload)
            }
            let nextOffset: Int
            do {
                nextOffset = try await assembler.append(
                    transferID: state.transferID,
                    binding   : state.binding,
                    offset    : offset,
                    bytes     : bytes
                )
            } catch {
                await revokeExactAssetTransfer(
                    owner: owner,
                    state: state
                )
                throw error
            }
            _ = try validateAssetSlots(
                ingress,
                connection : connection,
                operation  : operation,
                claim      : claim,
                reservation: reservation,
                checkingSequence: false
            )
            return (
                try AssetTransferResponse(
                    requestID : request.requestID,
                    operation : .chunk,
                    result    : .acknowledged,
                    transferID: state.transferID,
                    nextOffset: nextOffset
                ),
                nil
            )
        case .finish:
            guard let state = processes[owner]?.assetTransfer else { throw failure(.resourceDenied) }
            do {
                try validateAssetTransfer(
                    state,
                    request   : request,
                    connection: connection
                )
            } catch {
                if request.transferID == state.transferID {
                    await revokeExactAssetTransfer(
                        owner: owner,
                        state: state
                    )
                }
                throw error
            }
            guard let assembler = processes[owner]?.assembler else { throw failure(.sessionRevoked) }
            let alias: ImportedAlias
            do {
                alias = try await importBackingAdmitted(
                    publicationID: state.binding.publicationID,
                    connection   : connection,
                    operation    : operation
                ) {
                    try await assembler.finish(
                        transferID: state.transferID,
                        binding   : state.binding
                    )
                }
            } catch {
                // The metadata quote must never outlive protected decode/cleanup, and a failure
                // before assembler.finish still owns the exact receiving transfer for disposal.
                pendingAssetMetadataBytes = 0
                await shrinkPoolToCurrent(owner: owner)
                // Revoke the exact assembler directly, not through the scalar guard: when a
                // terminal stop already cleared the runtime transfer, a refund that then fails
                // must still be retained by the bounded deferred cleanup instead of being lost.
                await revokeAssetTransfer(
                    assembler,
                    transferID: state.transferID,
                    binding   : state.binding
                )
                clearAssetTransfer(owner: owner, transferID: state.transferID)
                throw error
            }
            pendingAssetMetadataBytes = 0
            await shrinkPoolToCurrent(owner: owner)
            clearAssetTransfer(owner: owner, transferID: state.transferID)
            return (
                try AssetTransferResponse(
                    requestID  : request.requestID,
                    operation  : .finish,
                    result     : .imported,
                    transferID : state.transferID,
                    assetHandle: alias.handle
                ),
                .alias(owner: owner, assetID: alias.handle.assetID, scope: alias.scope)
            )
        case .abort:
            guard let state = processes[owner]?.assetTransfer else { throw failure(.resourceDenied) }
            do {
                try validateAssetTransfer(
                    state,
                    request   : request,
                    connection: connection
                )
            } catch {
                if request.transferID == state.transferID {
                    await revokeExactAssetTransfer(
                        owner: owner,
                        state: state
                    )
                }
                throw error
            }
            guard let assembler = processes[owner]?.assembler else { throw failure(.sessionRevoked) }
            do {
                try await assembler.abort(
                    transferID: state.transferID,
                    binding   : state.binding
                )
            } catch {
                await revokeExactAssetTransfer(
                    owner: owner,
                    state: state
                )
                throw error
            }
            clearAssetTransfer(owner: owner, transferID: state.transferID)
            return (
                try AssetTransferResponse(
                    requestID : request.requestID,
                    operation : .abort,
                    result    : .acknowledged,
                    transferID: state.transferID
                ),
                nil
            )
        case .share:
            guard let source = request.sourceHandle, let target = request.publicationID else {
                throw failure(.invalidPayload)
            }
            try source.validate()
            let alias: ImportedAlias
            do {
                alias = try await shareAssetAdmitted(
                    assetID   : source.assetID,
                    sourceID  : source.publicationID,
                    targetID  : target,
                    connection: connection,
                    operation : operation
                )
            } catch {
                // The sharing quote is protected across its own deferred cleanup; reconcile it
                // on every failure once that protected work has ended.
                pendingAssetMetadataBytes = 0
                await shrinkPoolToCurrent(owner: owner)
                throw error
            }
            pendingAssetMetadataBytes = 0
            await shrinkPoolToCurrent(owner: owner)
            return (
                try AssetTransferResponse(
                    requestID  : request.requestID,
                    operation  : .share,
                    result     : .shared,
                    assetHandle: alias.handle
                ),
                .alias(owner: owner, assetID: alias.handle.assetID, scope: alias.scope)
            )
        case .release:
            guard let source = request.sourceHandle else { throw failure(.invalidPayload) }
            try source.validate()
            try await releaseAssetAdmitted(
                assetID      : source.assetID,
                publicationID: source.publicationID,
                connection   : connection,
                operation    : operation
            )
            return (
                try AssetTransferResponse(
                    requestID: request.requestID,
                    operation: .release,
                    result   : .acknowledged
                ),
                nil
            )
        }
    }

    private func clearAssetTransfer(owner: AddonID, transferID: UUID) {
        guard processes[owner]?.assetTransfer?.transferID == transferID else { return }
        processes[owner]?.assetTransfer = nil
    }

    /// revokeAssetTransfer refunds an exact transfer whose reply could not be handed off.
    /// An idle or already-disposed assembler keeps no record and stays usable; a retained
    /// record is retried through the bounded deferred disposal ownership.
    private func revokeAssetTransfer(
        _ assembler : BoundedAssetTransferAssembler,
        transferID  : UUID,
        binding     : AssetTransferBinding
    ) async {
        guard assembler.nextDeadline != nil else { return }
        do {
            try await assembler.abort(
                transferID: transferID,
                binding   : binding
            )
        } catch {
            deferredAssetAssemblers[binding.incarnation] = assembler
        }
    }

    /// revokeExactAssetTransfer invalidates one live runtime transfer and retains its assembler
    /// for bounded deferred disposal. It matches the exact transfer ID and binding, so a foreign
    /// token can neither clear nor revoke another transfer.
    private func revokeExactAssetTransfer(
        owner: AddonID,
        state: AssetTransferState
    ) async {
        guard processes[owner]?.assetTransfer?.transferID == state.transferID,
            processes[owner]?.assetTransfer?.binding == state.binding else { return }
        guard let assembler = processes[owner]?.assembler else {
            processes[owner]?.assetTransfer = nil
            return
        }
        clearAssetTransfer(owner: owner, transferID: state.transferID)
        await revokeAssetTransfer(
            assembler,
            transferID: state.transferID,
            binding   : state.binding
        )
    }

    /// reconcileAssetTransfers revokes exactly one active transfer whose immutable assignment,
    /// connection or canonical publication no longer holds, then queues its bounded disposal.
    /// The revocation is nonterminal: it covers a paused begin, idle receiving and suspended finish
    /// without closing the process assembler, so an unrelated or later authorized assignment on the
    /// same live process still imports. Exact binding equality leaves a replacement assignment or an
    /// unrelated transfer untouched. Process/connection shutdown keeps its own terminal invalidation.
    private func reconcileAssetTransfers(at instant: RuntimeInstant) {
        for owner in Array(processes.keys) {
            guard let process = processes[owner], let transfer = process.assetTransfer else { continue }
            guard !assetTransferHolds(transfer, process: process, at: instant) else { continue }
            process.assembler.revokeTransfer(binding: transfer.binding)
            processes[owner]?.assetTransfer = nil
            // The retained assembler carries the exact record and sole reservation token until the
            // owned refund completes, so no cleanup ownership is dropped here.
            deferredAssetAssemblers[process.incarnation] = process.assembler
        }
    }

    /// assetTransferHolds mirrors importAssetScope authority for one host-retained binding.
    private func assetTransferHolds(
        _ transfer: AssetTransferState,
        process: ProcessRecord,
        at instant: RuntimeInstant
    ) -> Bool {
        guard process.incarnation == transfer.binding.incarnation,
            case .connected(let connection) = process.phase,
            connection.token == transfer.binding.connectionToken,
            let assignment = assignments[transfer.binding.publicationID],
            assignment.owner == transfer.binding.publicationID.addonID,
            assignment.assignmentToken == transfer.binding.assignmentToken,
            let installed = catalog[assignment.owner],
            installed.verifiedIdentity == connection.identity,
            installed.digest == connection.digest else { return false }
        if assignment.hasPublished,
            publicationState.publication(
                id: transfer.binding.publicationID,
                at: instant.wall
            ) == nil {
            return false
        }
        return true
    }

    /// applyAssetRollback releases only the newly minted alias/transfer when a reply is suppressed.
    private func applyAssetRollback(
        _ rollback: AssetRollback?,
        connection: RuntimeConnection
    ) async {
        switch rollback {
        case nil:
            return
        case .transfer(let owner, let assembler, let binding, let transferID):
            clearAssetTransfer(owner: owner, transferID: transferID)
            await revokeAssetTransfer(
                assembler,
                transferID: transferID,
                binding   : binding
            )
        case .alias(let owner, let assetID, let scope):
            try? assetState.releaseImport(
                assetID: assetID,
                scope  : scope
            )
            await shrinkPoolToCurrent(owner: owner)
        }
    }

    /// receiveAssetReceipt releases only the current accepted payload, without altering work state.
    func receiveAssetReceipt(
        _ receipt : RuntimeAssetReceipt,
        connection: RuntimeConnection
    ) -> Bool {
        guard let current = try? assetConnection(connection), receipt.incarnation == current.incarnation,
            receipt.connectionToken == current.token,
            processes[current.identity.addonID]?.credits.delivery == .assetAccepted(receipt)
        else { return false }
        releaseDelivery(
            .assetAccepted(receipt),
            owner      : current.identity.addonID,
            incarnation: current.incarnation
        )
        return true
    }

    /// assetFailureCode bounds pre-handoff refusals without preserving arbitrary backend errors.
    private static func assetFailureCode(_ error: any Error) -> AddonFailure.Code {
        if error is CancellationError { return .sessionRevoked }
        return (error as? AddonFailure)?.code ?? .invalidPayload
    }

    /// receivePublicationOutput reserves scratch, state growth and family slots before commit.
    func receivePublicationOutput(
        _ ingress   : RuntimeIngressHandle,
        connection  : RuntimeConnection,
        sequence    : UInt64
    ) async throws -> PublicationOutputResult {
        let owner: AddonID
        do {
            owner = try connectedOwner(connection)
        } catch {
            adapter.rejectIngress(
                ingress,
                incarnation: ingress.incarnation
            )
            throw error
        }
        guard ingress.incarnation == connection.incarnation,
              ingress.encodedBytes > 0,
              ingress.encodedBytes <= maximumEnvelopeBytes else {
            adapter.rejectIngress(
                ingress,
                incarnation: connection.incarnation
            )
            throw failure(.invalidPayload)
        }
        guard processes[owner]?.outputOutstanding == false else {
            if processes[owner]?.credits.ingress?.handle != .publication(ingress) {
                adapter.rejectIngress(
                    ingress,
                    incarnation: connection.incarnation
                )
            }
            throw failure(.invalidPayload)
        }
        if ingress.isCompletionOnly {
            let claim = try claimIngress(
                ingress,
                owner      : owner,
                incarnation: connection.incarnation
            )
            guard let output = adapter.takeIngress(
                ingress,
                incarnation: connection.incarnation
            ) else {
                disposeIngress(
                    claim,
                    owner      : owner,
                    incarnation: connection.incarnation,
                    disposition: .reject
                )
                throw failure(.invalidPayload)
            }
            do {
                guard try JSONEncoder().encode(output).count == ingress.encodedBytes,
                      output.checkpoint == nil,
                      output.publications.isEmpty,
                      output.operations.isEmpty,
                      let completion = try correlatedCompletion(
                        output.completion,
                        owner     : owner,
                        connection: connection
                      ) else { throw failure(.invalidPayload) }
                return try await receiveCompletionOnlyOutput(
                    output,
                    claim     : claim,
                    completion: completion,
                    connection: connection,
                    sequence  : sequence
                )
            } catch {
                disposeIngress(
                    claim,
                    owner      : owner,
                    incarnation: connection.incarnation,
                    disposition: .cancel
                )
                throw error
            }
        }
        let operation: AdmissionOperation
        do {
            operation = try await beginAdmission(owner: owner)
        } catch {
            adapter.rejectIngress(
                ingress,
                incarnation: connection.incarnation
            )
            throw error
        }
        defer { finishAdmission(operation) }
        var claim: IngressClaim?
        var scratch: ResourceReservation?
        var ownsIngressTransfer = false
        var newReservations: [(PublicationID, ResourceReservation)] = []
        do {
            claim = try claimIngress(
                ingress,
                owner      : owner,
                incarnation: connection.incarnation
            )
            scratch = try await resourceAccess.admit(
                .temporaryMemory(bytes: Self.scratchBytes),
                owner: owner
            )
            try validateOperation(operation, owner: owner)
            guard let output = adapter.takeIngress(
                ingress,
                incarnation: connection.incarnation
            ) else { throw failure(.invalidPayload) }
            ownsIngressTransfer = true
            guard try JSONEncoder().encode(output).count == ingress.encodedBytes,
            output.checkpoint == nil,
            output.publications.allSatisfy({ assignments[$0.id]?.owner == owner }),
            output.operations.allSatisfy({
                if case .endPublication(let id) = $0 {
                    return assignments[id]?.owner == owner
                }
                return false
            }) else { throw failure(.invalidPayload) }
            let completion = try correlatedCompletion(
                output.completion,
                owner     : owner,
                connection: connection
            )
            if case .service? = completion {
                throw failure(.invalidPayload)
            }
            _ = try currentInstant()
            let prepared = try publicationState.prepareOutput(
                output,
                connection: connection.publicationConnection,
                generation: connection.publicationConnection.generation,
                sequence  : sequence,
                expectedCompletion: completion?.expectation
            )
            for (id, kind) in prepared.newFamilies where publicationReservations[id] == nil {
                let reservation = try await resourceAccess.admit(
                    .publication(kind),
                    owner: owner
                )
                newReservations.append((id, reservation))
                try validateOperation(operation, owner: owner)
            }
            let assetPreparationBytes = try assetState.preparationBytes(prepared)
            let estimatedGrowth = max(
                0,
                prepared.retainedBytesAfter - publicationState.retainedBytes
            )
            try await growPool(
                owner: owner,
                by   : estimatedGrowth + assetPreparationBytes
            )
            try validateOperation(operation, owner: owner)
            let finalInstant = try currentInstant()
            try publicationState.validatePreparedOutput(
                prepared,
                at: finalInstant.wall
            )
            if case .action(_, let delivery, let outcome) = completion {
                guard try dispatcher.canComplete(
                    delivery,
                    owner     : owner,
                    generation: connection.publicationConnection.generation,
                    outcome   : outcome,
                    at        : finalInstant.monotonic
                ) else { throw failure(.sessionRevoked) }
            }
            let admission = try commitPublicationAndAssets(
                prepared,
                connection: connection,
                at        : finalInstant.wall
            )
            // Ending a publication in this committed batch revokes only a transfer bound to
            // that exact assignment; unrelated transfers and replacement assignments stay live.
            reconcileAssetTransfers(at: finalInstant)
            for publication in output.publications {
                assignments[publication.id]?.hasPublished = true
            }
            var completedActionResources: ActionResources?
            if case .action(let key, let delivery, let outcome) = completion {
                let accepted = try dispatcher.complete(
                    delivery,
                    owner     : owner,
                    generation: connection.publicationConnection.generation,
                    outcome   : outcome,
                    at        : finalInstant.monotonic
                )
                precondition(accepted)
                completedActionResources = actionResources.removeValue(forKey: key)
                releaseDelivery(
                    .action(ticketID: delivery.ticket.id),
                    owner      : owner,
                    incarnation: connection.incarnation
                )
            }
            for (id, reservation) in newReservations {
                publicationReservations[id] = reservation
            }
            for operation in output.operations {
                guard case .endPublication(let id) = operation else { continue }
                if let reservation = publicationReservations.removeValue(forKey: id) {
                    try? await resourceAccess.release(
                        reservation.id,
                        owner: owner
                    )
                }
            }
            if let completedActionResources {
                if let job = completedActionResources.job {
                    try? await resourceAccess.release(
                        job.id,
                        owner: owner
                    )
                }
                try? await resourceAccess.release(
                    completedActionResources.command.id,
                    owner: owner
                )
            }
            if let scratch {
                try? await resourceAccess.release(
                    scratch.id,
                    owner: owner
                )
            }
            if let claim {
                disposeIngress(
                    claim,
                    owner      : owner,
                    incarnation: connection.incarnation,
                    disposition: .finish
                )
            }
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            return .committed(admission)
        } catch {
            if let claim {
                disposeIngress(
                    claim,
                    owner      : owner,
                    incarnation: connection.incarnation,
                    disposition: ownsIngressTransfer ? .cancel : .reject
                )
            } else if processes[owner]?.credits.ingress?.handle != .publication(ingress) {
                adapter.rejectIngress(
                    ingress,
                    incarnation: connection.incarnation
                )
            }
            for (_, reservation) in newReservations {
                try? await resourceAccess.release(
                    reservation.id,
                    owner: owner
                )
            }
            if let scratch {
                try? await resourceAccess.release(
                    scratch.id,
                    owner: owner
                )
            }
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    private func correlatedCompletion(
        _ completion: InvocationCompletion?,
        owner       : AddonID,
        connection  : RuntimeConnection
    ) throws -> CorrelatedCompletion? {
        guard let completion else { return nil }
        switch completion {
        case .action(let requestID, let outcome):
            let key = ActionKey(
                owner    : owner,
                requestID: requestID
            )
            guard let delivery = actionResources[key]?.delivery else {
                throw failure(.sessionRevoked)
            }
            return .action(
                key     : key,
                delivery: delivery,
                outcome : outcome
            )
        case .service(let requestID, let response):
            guard let execution = serviceExecutions.values.first(where: {
                $0.provider == owner
                    && $0.work.invocation.requestID == requestID
                    && $0.work.invocation.contractID == response.contractID
                    && $0.work.invocation.operation == response.operation
                    && $0.isHandedOff
                    && $0.providerIncarnation == connection.incarnation
            }) else { throw failure(.sessionRevoked) }
            return .service(
                workID              : execution.work.id,
                requestID           : requestID,
                response            : response,
                providerIncarnation : execution.providerIncarnation,
                consumer            : execution.consumer,
                authorityRevision   : authorityRevision
            )
        }
    }

    /// receiveCompletionOnlyOutput consumes pre-reserved result capacity and no scratch permit.
    private func receiveCompletionOnlyOutput(
        _ output    : ProviderOutput,
        claim       : IngressClaim,
        completion  : CorrelatedCompletion,
        connection  : RuntimeConnection,
        sequence    : UInt64
    ) async throws -> PublicationOutputResult {
        let owner = connection.identity.addonID
        do {
            let prepared = try publicationState.prepareCompletion(
                output,
                connection: connection.publicationConnection,
                generation: connection.publicationConnection.generation,
                sequence  : sequence,
                expectedCompletion: completion.expectation
            )
            switch completion {
            case .action(let key, let delivery, let outcome):
                let instant = try currentInstant()
                try publicationState.validatePreparedCompletion(prepared)
                guard try dispatcher.canComplete(
                    delivery,
                    owner     : owner,
                    generation: connection.publicationConnection.generation,
                    outcome   : outcome,
                    at        : instant.monotonic
                ) else { throw failure(.sessionRevoked) }
                let admission = try publicationState.commitPreparedCompletion(prepared)
                let accepted = try dispatcher.complete(
                    delivery,
                    owner     : owner,
                    generation: connection.publicationConnection.generation,
                    outcome   : outcome,
                    at        : instant.monotonic
                )
                precondition(accepted)
                let resources = actionResources.removeValue(forKey: key)
                releaseDelivery(
                    .action(ticketID: delivery.ticket.id),
                    owner      : owner,
                    incarnation: connection.incarnation
                )
                disposeIngress(
                    claim,
                    owner      : owner,
                    incarnation: connection.incarnation,
                    disposition: .finish
                )
                if let job = resources?.job {
                    deferRelease(
                        job,
                        owner: owner
                    )
                }
                if let command = resources?.command {
                    deferRelease(
                        command,
                        owner: owner
                    )
                }
                deferredPoolOwners.insert(owner)
                await drainIfNoActiveAdmission()
                return .committed(admission)
            case .service(
                let workID,
                let requestID,
                let response,
                let providerIncarnation,
                let consumer,
                let operation
            ):
                try validateOperation(operation, owner: consumer)
                _ = try connectedOwner(connection)
                guard let execution = serviceExecutions[workID], execution.isHandedOff,
                      execution.providerIncarnation == providerIncarnation,
                      execution.work.invocation.requestID == requestID,
                      response.contractID == execution.work.invocation.contractID,
                      response.operation == execution.work.invocation.operation else {
                    throw failure(.sessionRevoked)
                }
                try response.validate()
                let instant = try currentInstant()
                guard instant.monotonic < execution.work.effectiveDeadline else {
                    throw failure(.deadlineExceeded)
                }
                guard !inFlightServiceCompletionIDs.contains(workID),
                      serviceGrants[execution.grantID]?.owner == execution.consumer,
                      let consumerProcess = processes[execution.consumer],
                      case .connected(let consumerConnection) = consumerProcess.phase,
                      consumerConnection.token == execution.connectionToken else {
                    throw failure(.sessionRevoked)
                }
                deferredServiceCompletions[workID] = DeferredServiceCompletion(
                    response : response,
                    requestID: requestID,
                    grantID  : execution.grantID,
                    consumer : execution.consumer,
                    connectionToken: execution.connectionToken,
                    providerIncarnation: execution.providerIncarnation,
                    authorityRevision: operation,
                    receivedAt: instant,
                    preparedCompletion: prepared,
                    ingressClaim: claim,
                    provider: owner
                )
                inFlightServiceCompletionIDs.insert(workID)
                releaseDelivery(
                    .service(workID: workID),
                    owner      : owner,
                    incarnation: connection.incarnation
                )
                let outcome = await drainIfNoActiveAdmission(
                    reportingServiceCompletion: workID
                )
                switch outcome {
                case .accepted(.some(let admission)):
                    return .committed(admission)
                case .accepted(nil), .refused:
                    throw failure(.sessionRevoked)
                case nil:
                    break
                }
                guard deferredServiceCompletions[workID] != nil else {
                    throw failure(.sessionRevoked)
                }
                return .pendingServiceCompletion
            }
        } catch {
            // The outer invocation disposes only its exact claim if deferred cleanup has not done so.
            throw error
        }
    }

    /// submitAction returns exact recovery before touching the admission lane or governor.
    func submitAction(_ request: ActionRequest) async throws -> ActionJournal.Admission {
        let now = try currentInstant()
        let context = try actionContext(
            request.publicationID,
            at: now.wall
        )
        switch try dispatcher.classify(
            request: request,
            context: context,
            at     : now
        ) {
        case .duplicate(let state): return .duplicate(state)
        case .admission(let quote):
            try requireFreshAdmissionOpen(owner: quote.owner)
            let operation = try await beginAdmission(owner: quote.owner)
            defer { finishAdmission(operation) }
            var command: ResourceReservation?
            do {
                try requireFreshAdmissionOpen(owner: quote.owner)
                let admittedCommand = try await resourceAccess.admit(
                    .command,
                    owner: quote.owner
                )
                command = admittedCommand
                try validateOperation(operation, owner: quote.owner)
                try requireFreshAdmissionOpen(owner: quote.owner)
                try await growPool(
                    owner: quote.owner,
                    by   : quote.retainedBytes + Self.actionRowBytes
                )
                try validateOperation(operation, owner: quote.owner)
                try requireFreshAdmissionOpen(owner: quote.owner)
                let fresh = try currentInstant()
                let admission = try dispatcher.submit(
                    request,
                    context: try actionContext(
                        request.publicationID,
                        at: fresh.wall
                    ),
                    at: fresh
                )
                actionResources[ActionKey(
                    owner    : quote.owner,
                    requestID: quote.requestID
                )] = ActionResources(command: admittedCommand)
                await shrinkAllPools()
                await finishAdmissionAndDrain(operation)
                return admission
            } catch {
                if let command {
                    try? await resourceAccess.release(
                        command.id,
                        owner: quote.owner
                    )
                }
                await shrinkAllPools()
                await finishAdmissionAndDrain(operation)
                throw error
            }
        }
    }

    func actionState(
        _ requestID: UUID,
        owner      : AddonID
    ) -> ActionJournal.State? {
        dispatcher.state(
            requestID,
            owner: owner
        )
    }

    /// pumpReady reserves the global job before taking local scheduler capacity and handing off.
    func pumpReady() async throws -> Bool {
        guard let job = dispatcher.peekReady(at: try currentInstant().monotonic),
              case .command(let request) = job.work else { return false }
        let owner = job.owner
        if processes[owner] == nil {
            guard let installed = catalog[owner] else { throw failure(.sessionRevoked) }
            let operation = try await beginAdmission(owner: owner)
            defer { finishAdmission(operation) }
            do {
                let path = try serviceProviderPath(to: installed.verifiedIdentity)
                try await admitMissingProviderPath(
                    path,
                    operation     : operation,
                    admissionOwner: owner
                )
                await finishAdmissionAndDrain(operation)
                return false
            } catch {
                await finishAdmissionAndDrain(operation)
                throw error
            }
        }
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        guard let process = processes[owner], case .connected(let connection) = process.phase,
              !process.deliveryOutstanding else {
            return false
        }
        var reservation: ResourceReservation?
        do {
            let admittedReservation = try await resourceAccess.admit(
                .job,
                owner: owner
            )
            reservation = admittedReservation
            try validateOperation(operation, owner: owner)
            let fresh = try currentInstant()
            guard let ticket = dispatcher.takeReady(
                expectedJobID: job.id,
                at           : fresh.monotonic
            ),
            let delivery = try dispatcher.consume(
                ticket,
                context   : actionContext(
                    request.publicationID,
                    at: fresh.wall
                ),
                generation: connection.publicationConnection.generation,
                at        : fresh
            ) else {
                try await resourceAccess.release(
                    admittedReservation.id,
                    owner: owner
                )
                await finishAdmissionAndDrain(operation)
                return false
            }
            let key = ActionKey(
                owner    : owner,
                requestID: request.requestID
            )
            if adapter.tryHandoff(
                incarnation: connection.incarnation,
                delivery   : .action(delivery)
            ) == .rejectedBeforeHandoff {
                let rejection = failure(.dependencyUnavailable)
                _ = dispatcher.rejectNeverHandedOff(
                    delivery: delivery,
                    failure : rejection
                )
                try await resourceAccess.release(
                    admittedReservation.id,
                    owner: owner
                )
                if let command = actionResources.removeValue(forKey: key)?.command {
                    try await resourceAccess.release(
                        command.id,
                        owner: owner
                    )
                }
                await shrinkPoolToCurrent(owner: owner)
                await finishAdmissionAndDrain(operation)
                return false
            }
            actionResources[key]?.job = admittedReservation
            actionResources[key]?.delivery = delivery
            installDelivery(
                .action(ticketID: delivery.ticket.id),
                owner      : owner,
                incarnation: connection.incarnation
            )
            await finishAdmissionAndDrain(operation)
            return true
        } catch {
            if let reservation {
                try? await resourceAccess.release(
                    reservation.id,
                    owner: owner
                )
            }
            await releaseTerminalActionResources(owner: owner)
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    func receiveAcknowledgment(
        _ delivery : ActionDispatcher.Delivery,
        connection : RuntimeConnection
    ) throws -> Bool {
        _ = try connectedOwner(connection)
        let acknowledged = dispatcher.acknowledge(
            delivery,
            owner     : connection.identity.addonID,
            generation: connection.publicationConnection.generation,
            at        : try currentInstant().monotonic
        )
        if acknowledged {
            releaseDelivery(
                .action(ticketID: delivery.ticket.id),
                owner      : connection.identity.addonID,
                incarnation: connection.incarnation
            )
        }
        return acknowledged
    }

    func receiveActionCompletion(
        _ delivery : ActionDispatcher.Delivery,
        connection : RuntimeConnection,
        outcome    : ActionOutcome
    ) async throws -> Bool {
        let owner = try connectedOwner(connection)
        let accepted = try dispatcher.complete(
            delivery,
            owner     : owner,
            generation: connection.publicationConnection.generation,
            outcome   : outcome,
            at        : try currentInstant().monotonic
        )
        guard accepted else { return false }
        releaseDelivery(
            .action(ticketID: delivery.ticket.id),
            owner      : owner,
            incarnation: connection.incarnation
        )
        let key = ActionKey(
            owner    : owner,
            requestID: delivery.ticket.request.requestID
        )
        if let resources = actionResources.removeValue(forKey: key) {
            if let job = resources.job {
                deferRelease(
                    job,
                    owner: owner
                )
            }
            deferRelease(
                resources.command,
                owner: owner
            )
        }
        deferredPoolOwners.insert(owner)
        await drainIfNoActiveAdmission()
        return true
    }

    /// authorizeService derives permission from the canonical resolution and connection.
    func authorizeService(
        connection           : RuntimeConnection,
        requirementID        : String,
        scope                : ServiceScope,
        partition            : String,
        crossPublisherConsent: Bool
    ) async throws -> UUID {
        let owner = try connectedOwner(connection)
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        guard let resolution,
              resolution.enabledFeatures.contains(where: {
                $0.addonID == owner && $0.featureID == scope.featureID
              }),
              let binding = resolution.bindings.first(where: {
                $0.consumer == owner && $0.requirementID == requirementID
                    && ($0.featureID == scope.featureID || $0.featureID == nil)
              }) else { throw failure(.permissionDenied) }
        let selectedBinding = ServiceBinding(
            requirementID  : binding.requirementID,
            consumer       : binding.consumer,
            provider       : binding.provider,
            providerIdentity: binding.providerIdentity,
            contractVersion: binding.contractVersion,
            digest          : binding.digest,
            featureID       : scope.featureID
        )
        let permission = HostServicePermission(
            consumer            : connection.identity,
            binding             : selectedBinding,
            serviceID           : requirementID,
            partition           : partition,
            operation           : scope.operation,
            crossPublisherConsent: crossPublisherConsent
        )
        var permissionID: UUID?
        do {
            try await growPool(
                owner: owner,
                by   : Self.servicePermissionBytes
            )
            try validateOperation(operation, owner: owner)
            let id = try await broker.authorize(permission)
            permissionID = id
            try validateOperation(operation, owner: owner)
            servicePermissions[id] = ServicePermissionRecord(
                owner        : owner,
                requirementID: requirementID,
                scope        : scope,
                provider     : binding.providerIdentity
            )
            await finishAdmissionAndDrain(operation)
            return id
        } catch {
            if let permissionID {
                await broker.revokePermission(permissionID)
            }
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// acquireService routes one canonical permission through the private broker.
    func acquireService(
        connection   : RuntimeConnection,
        permissionID : UUID,
        lifetime     : Duration
    ) async throws -> ServiceAcquisition {
        let owner = try connectedOwner(connection)
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        guard let permission = servicePermissions[permissionID], permission.owner == owner else {
            throw failure(.permissionDenied)
        }
        var acquisition: ServiceAcquisition?
        do {
            try await growPool(
                owner: owner,
                by   : Self.serviceGrantBytes
            )
            try validateOperation(operation, owner: owner)
            let acquired = try await broker.acquire(
                session      : connection.serviceSession,
                requirementID: permission.requirementID,
                scope        : permission.scope,
                now          : currentInstant(),
                lifetime     : lifetime,
                allowNewSourceStart     : isFreshAdmissionOpen(permission.provider),
                allowNewConsumerInterest: isFreshAdmissionOpen(connection.identity)
            )
            acquisition = acquired
            try validateOperation(operation, owner: owner)
            try requireNewConsumerFreshAdmissionOpen(acquired, owner: owner)
            // The canonical broker decides whether this is a new consumer interest.
            // Its refusal must precede any physical launch in the missing path.
            let providerPath = try serviceProviderPath(to: permission.provider)
            try await admitMissingProviderPath(
                providerPath,
                operation            : operation,
                admissionOwner       : owner,
                freshConsumerOwner: acquired.createdNewConsumerInterest ? owner : nil
            )
            try validateOperation(operation, owner: owner)
            try requireNewConsumerFreshAdmissionOpen(acquired, owner: owner)
            guard providerPath.allSatisfy({ installed in
                guard let process = processes[installed.manifest.id],
                      process.identity == installed.verifiedIdentity,
                      process.digest == installed.digest,
                      case .connected = process.phase else { return false }
                return true
            }) else {
                throw failure(.dependencyUnavailable)
            }
            if acquired.decisions.contains(.startSource(acquired.sourceID)) {
                try requireFreshAdmissionOpen(owner: permission.provider.addonID)
            }
            serviceGrants[acquired.grant.id] = ServiceGrantRecord(
                owner   : owner,
                provider: permission.provider,
                sourceID: acquired.sourceID,
                deadline: acquired.effectiveDeadline
            )
        for decision in acquired.decisions {
            guard case .startSource(let sourceID) = decision else { continue }
            guard let providerProcess = processes[permission.provider.addonID],
                  case .connected(let providerConnection) = providerProcess.phase,
                  !providerProcess.deliveryOutstanding else {
                throw failure(.resourceDenied)
            }
            try requireFreshAdmissionOpen(owner: permission.provider.addonID)
            try requireNewConsumerFreshAdmissionOpen(acquired, owner: owner)
            try await growPool(
                owner: permission.provider.addonID,
                by   : Self.sourceExecutionBytes
            )
            try validateOperation(operation, owner: owner)
            try requireFreshAdmissionOpen(owner: permission.provider.addonID)
            try requireNewConsumerFreshAdmissionOpen(acquired, owner: owner)
            let job = try await resourceAccess.admit(
                .job,
                owner: permission.provider.addonID
            )
            do {
                try validateOperation(operation, owner: owner)
                try requireFreshAdmissionOpen(owner: permission.provider.addonID)
                try requireNewConsumerFreshAdmissionOpen(acquired, owner: owner)
                let descriptor = try await serviceDecisionAccess.consumeSourceStart(
                    sourceID,
                    now: currentInstant()
                )
                try validateOperation(operation, owner: owner)
                try requireFreshAdmissionOpen(owner: permission.provider.addonID)
                try requireNewConsumerFreshAdmissionOpen(acquired, owner: owner)
                let fresh = try currentInstant()
                guard fresh.monotonic < acquired.effectiveDeadline,
                      descriptor.provider == permission.provider,
                      processes[permission.provider.addonID]?.incarnation
                        == providerConnection.incarnation,
                      adapter.tryHandoff(
                        incarnation: providerConnection.incarnation,
                        delivery   : .source(descriptor)
                      ) == .accepted else {
                    _ = await broker.abandonSourceStart(
                        sourceID,
                        knownUnsent: true
                    )
                    try? await resourceAccess.release(
                        job.id,
                        owner: permission.provider.addonID
                    )
                    throw failure(.dependencyUnavailable)
                }
                sourceExecutions[sourceID] = SourceExecutionRecord(
                    provider            : permission.provider.addonID,
                    providerIncarnation : providerConnection.incarnation,
                    deadline            : acquired.effectiveDeadline,
                    job                 : job,
                    isHandedOff         : true
                )
                installDelivery(
                    .source(sourceID: sourceID),
                    owner      : permission.provider.addonID,
                    incarnation: providerConnection.incarnation
                )
            } catch {
                _ = await broker.abandonSourceStart(
                    sourceID,
                    knownUnsent: true
                )
                try? await resourceAccess.release(
                    job.id,
                    owner: permission.provider.addonID
                )
                throw error
            }
        }
            await finishAdmissionAndDrain(operation)
            return acquired
        } catch {
            if let acquisition {
                serviceGrants.removeValue(forKey: acquisition.grant.id)
                await broker.rollbackAcquisition(acquisition)
            }
            await shrinkPoolToCurrent(owner: owner)
            await shrinkPoolToCurrent(owner: permission.provider.addonID)
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// receiveSourceStartupCompletion releases only the finite startup execution job.
    func receiveSourceStartupCompletion(
        _ sourceID : UUID,
        connection : RuntimeConnection
    ) async throws -> Bool {
        guard serviceSources[sourceID] == nil, let execution = sourceExecutions[sourceID], execution.isHandedOff,
              execution.provider == connection.identity.addonID,
              execution.providerIncarnation == connection.incarnation else { return false }
        _ = try connectedOwner(connection)
        sourceExecutions.removeValue(forKey: sourceID)
        releaseDelivery(
            .source(sourceID: sourceID),
            owner      : execution.provider,
            incarnation: execution.providerIncarnation
        )
        deferRelease(
            execution.job,
            owner: execution.provider
        )
        deferredPoolOwners.insert(execution.provider)
        await drainIfNoActiveAdmission()
        return true
    }

    /// beginServiceInvocation reserves the shared command and provider job before broker retention.
    func beginServiceInvocation(
        connection: RuntimeConnection,
        grantID   : UUID,
        invocation: ServiceInvocation
    ) async throws -> ServiceWork {
        let consumer = try connectedOwner(connection)
        let operation = try await beginAdmission(owner: consumer)
        do {
            let work = try await beginServiceInvocationAdmitted(connection: connection, grantID: grantID,
                                                                invocation: invocation, operation: operation)
            await finishAdmissionAndDrain(operation)
            return work
        } catch { await finishAdmissionAndDrain(operation); throw error }
    }

    private func beginServiceInvocationAdmitted(
        connection: RuntimeConnection, grantID: UUID, invocation: ServiceInvocation,
        operation: AdmissionOperation, routeID: UUID? = nil
    ) async throws -> ServiceWork {
        let consumer = try connectedOwner(connection)
        guard !serviceExecutions.values.contains(where: {
            $0.provider == consumer && $0.isHandedOff
        }) else { throw failure(.resourceDenied) }
        guard let grant = serviceGrants[grantID], grant.owner == consumer,
              let providerProcess = processes[grant.provider.addonID],
              case .connected(let providerConnection) = providerProcess.phase,
              !serviceExecutions.values.contains(where: {
                $0.provider == grant.provider.addonID
              }) else { throw failure(.resourceDenied) }
        try requireFreshAdmissionOpen(owner: consumer)
        try requireFreshAdmissionOpen(owner: grant.provider.addonID)
        var command: ResourceReservation?
        var job: ResourceReservation?
        var brokerWorkID: UUID?
        do {
            try requireFreshAdmissionOpen(owner: consumer)
            try requireFreshAdmissionOpen(owner: grant.provider.addonID)
            let admittedCommand = try await resourceAccess.admit(
                .command,
                owner: consumer
            )
            command = admittedCommand
            try validateOperation(operation, owner: consumer)
            try requireFreshAdmissionOpen(owner: consumer)
            try requireFreshAdmissionOpen(owner: grant.provider.addonID)
            _ = try connectedOwner(connection)
            guard serviceGrants[grantID]?.owner == consumer,
                  processes[grant.provider.addonID]?.incarnation == providerConnection.incarnation,
                  try currentInstant().monotonic < grant.deadline else { throw failure(.sessionRevoked) }
            if let routeID { try validateInvocationReservations(routeID, operation: operation) }
            try requireFreshAdmissionOpen(owner: consumer)
            try requireFreshAdmissionOpen(owner: grant.provider.addonID)
            let admittedJob = try await resourceAccess.admit(
                .job,
                owner: grant.provider.addonID
            )
            job = admittedJob
            try validateOperation(operation, owner: consumer)
            try requireFreshAdmissionOpen(owner: consumer)
            try requireFreshAdmissionOpen(owner: grant.provider.addonID)
            _ = try connectedOwner(connection)
            guard serviceGrants[grantID]?.owner == consumer,
                  processes[grant.provider.addonID]?.incarnation == providerConnection.incarnation,
                  try currentInstant().monotonic < grant.deadline else { throw failure(.sessionRevoked) }
            if let routeID { try validateInvocationReservations(routeID, operation: operation) }
            try requireFreshAdmissionOpen(owner: consumer)
            try requireFreshAdmissionOpen(owner: grant.provider.addonID)
            try await growPool(
                owner: consumer,
                by   : Self.serviceExecutionBytes
            )
            try validateOperation(operation, owner: consumer)
            try requireFreshAdmissionOpen(owner: consumer)
            try requireFreshAdmissionOpen(owner: grant.provider.addonID)
            _ = try connectedOwner(connection)
            guard serviceGrants[grantID]?.owner == consumer,
                  processes[grant.provider.addonID]?.incarnation == providerConnection.incarnation,
                  try currentInstant().monotonic < grant.deadline else { throw failure(.sessionRevoked) }
            if let routeID { try validateInvocationReservations(routeID, operation: operation) }
            try requireFreshAdmissionOpen(owner: consumer)
            try requireFreshAdmissionOpen(owner: grant.provider.addonID)
            let work = try await broker.beginInvocation(
                session   : connection.serviceSession,
                grantID   : grantID,
                invocation: invocation,
                now       : currentInstant()
            )
            brokerWorkID = work.id
            try validateOperation(operation, owner: consumer)
            try requireFreshAdmissionOpen(owner: consumer)
            try requireFreshAdmissionOpen(owner: grant.provider.addonID)
            _ = try connectedOwner(connection)
            guard serviceGrants[grantID]?.owner == consumer,
                  processes[grant.provider.addonID]?.incarnation == providerConnection.incarnation,
                  try currentInstant().monotonic < grant.deadline else { throw failure(.sessionRevoked) }
            if let routeID { try validateInvocationReservations(routeID, operation: operation) }
            serviceExecutions[work.id] = ServiceExecutionRecord(
                work           : work,
                grantID        : grantID,
                consumer       : consumer,
                provider       : grant.provider.addonID,
                connectionToken: connection.token,
                providerIncarnation: providerConnection.incarnation,
                command        : admittedCommand,
                job            : admittedJob,
                isHandedOff    : false
            )
            return work
        } catch {
            if let brokerWorkID {
                _ = await broker.abandonInvocation(
                    brokerWorkID,
                    knownUnsent: true
                )
            }
            if let job {
                try? await resourceAccess.release(
                    job.id,
                    owner: grant.provider.addonID
                )
            }
            if let command {
                try? await resourceAccess.release(
                    command.id,
                    owner: consumer
                )
            }
            await shrinkPoolToCurrent(owner: consumer)
            throw error
        }
    }

    /// pumpServiceInvocation rechecks authority after the real broker consume return.
    func pumpServiceInvocation(_ workID: UUID) async throws -> Bool {
        guard let execution = serviceExecutions[workID], !execution.isHandedOff else { return false }
        let operation = try await beginAdmission(owner: execution.consumer)
        do {
            let accepted = try await pumpServiceInvocationAdmitted(workID, operation: operation)
            await finishAdmissionAndDrain(operation)
            return accepted
        } catch { await finishAdmissionAndDrain(operation); throw error }
    }

    private func pumpServiceInvocationAdmitted(_ workID: UUID, operation: AdmissionOperation,
                                              routeID: UUID? = nil) async throws -> Bool {
        guard let execution = serviceExecutions[workID], !execution.isHandedOff else { return false }
        do {
            let sourceID = try await serviceDecisionAccess.consumeInvocation(
                workID,
                now: currentInstant()
            )
            try validateOperation(operation, owner: execution.consumer)
            if let routeID { try validateInvocationReservations(routeID, operation: operation) }
            guard sourceID == execution.work.sourceID,
                  let process = processes[execution.provider],
                  case .connected(let connection) = process.phase,
                  connection.incarnation == execution.providerIncarnation,
                  (routeID == nil ? !process.deliveryOutstanding : providerReservationHolds(routeID!, process: process)) else {
                _ = await broker.abandonInvocation(
                    workID,
                    knownUnsent: true
                )
                invocationExchange.mark(workID: workID, terminal: .refused(.dependencyUnavailable))
                await releaseServiceExecution(workID)
                return false
            }
            let fresh = try currentInstant()
            guard fresh.monotonic < execution.work.effectiveDeadline else {
                throw failure(.deadlineExceeded)
            }
            let delivery: RuntimeAdapterDelivery
            let credit: DeliveryCredit
            if let routeID, let route = invocationExchange.routes[routeID] {
                let payload = try ServiceFrameCodec.encode(ServiceProviderFrame.invocation(execution.work.invocation),
                                                           profile: connection.publicationConnection.negotiatedProtocol.serviceInvocationFrameProfile)
                let receipt = RuntimeServiceReceipt(token: route.providerReservation!, incarnation: connection.incarnation,
                    connectionToken: connection.token, sequence: route.sequence, requestID: route.requestID,
                    kind: .providerInvocation(workID: workID))
                delivery = .serviceInvocation(RuntimeServiceDelivery(receipt: receipt, payload: payload))
                credit = .serviceAccepted(receipt.token)
            } else { delivery = .service(execution.work); credit = .service(workID: workID) }
            guard adapter.tryHandoff(incarnation: connection.incarnation, delivery: delivery) == .accepted else {
                _ = await broker.abandonInvocation(
                    workID,
                    knownUnsent: true
                )
                invocationExchange.mark(workID: workID, terminal: .refused(.dependencyUnavailable))
                await releaseServiceExecution(workID)
                return false
            }
            serviceExecutions[workID]?.isHandedOff = true
            if case .serviceInvocation(let d) = delivery { processes[execution.provider]?.servicePayloadReceipt = d.receipt }
            if let routeID, let route = invocationExchange.routes[routeID] {
                releaseDelivery(.serviceReserved(route.providerReservation!), owner: execution.provider,
                                incarnation: connection.incarnation)
            }
            installDelivery(
                credit,
                owner      : execution.provider,
                incarnation: connection.incarnation
            )
            return true
        } catch {
            invocationExchange.mark(workID: workID, terminal: .refused(Self.serviceFailureCode(error)))
            _ = await broker.abandonInvocation(
                workID,
                knownUnsent: true
            )
            await releaseServiceExecution(workID)
            throw error
        }
    }

    /// receiveServiceRequest admits a scalar route and returns after short admission/raw workspace disposal.
    /// The adapter's single exchange slot awaits an event, never this actor's admission.
    func receiveServiceRequest(_ ingress: RuntimeServiceIngressHandle, connection: RuntimeConnection)
        async -> RuntimeServiceInvocationExchange.Admission {
        guard let serviceAdapter = adapter as? any AddonRuntimeServiceAdapter else { return .refused(.versionConflict) }
        let operation: AdmissionOperation
        do {
            _ = try serviceConnection(connection)
            guard ingress.kind == .invocation, ingress.incarnation == connection.incarnation,
                  ingress.encodedBytes > 0, ingress.encodedBytes <= ServiceFrameCodec.maximumEncodedBytes,
                  ingress.sequence > 0 else { throw failure(.invalidPayload) }
            operation = try await beginAdmission(owner: connection.identity.addonID)
        } catch {
            serviceAdapter.rejectServiceIngress(ingress, incarnation: ingress.incarnation)
            return .refused(Self.serviceFailureCode(error))
        }
        let result: RuntimeServiceInvocationExchange.Admission
        do {
            if let parked = try await parkServiceIngressIfNeeded(ingress, connection: connection, operation: operation) {
                await finishAdmissionAndDrain(operation)
                return .admitted(parked)
            }
            result = try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes,
                owner: connection.identity.addonID) {
                await self.receiveServiceRequestAdmitted(ingress, connection: connection, operation: operation)
            }
        } catch {
            serviceAdapter.rejectServiceIngress(ingress, incarnation: ingress.incarnation)
            result = .refused(Self.serviceFailureCode(error))
        }
        await finishAdmissionAndDrain(operation)
        return result
    }

    private func serviceConnection(_ connection: RuntimeConnection) throws -> AddonID {
        let owner = try connectedOwner(connection)
        guard serviceFramesEnabled,
              connection.publicationConnection.negotiatedProtocol.serviceInvocationFrameProfile == .v1_3
        else { throw failure(.versionConflict) }
        return owner
    }

    private static func serviceFailureCode(_ error: any Error) -> AddonFailure.Code {
        (error as? AddonFailure)?.code ?? .invalidPayload
    }

    private func receiveServiceRequestAdmitted(_ ingress: RuntimeServiceIngressHandle,
        connection: RuntimeConnection, operation: AdmissionOperation, prepaidRouteID: UUID? = nil) async -> RuntimeServiceInvocationExchange.Admission {
        let owner = connection.identity.addonID
        let serviceAdapter = adapter as! any AddonRuntimeServiceAdapter
        let routeID = prepaidRouteID ?? UUID()
        var claim: IngressClaim?
        var taken = false
        var installedRoute = false
        do {
            try validateOperation(operation, owner: owner)
            _ = try serviceConnection(connection)
            try validateServiceRequestSlots(ingress, owner: owner)
            pendingServiceMetadataBytes = RuntimeServiceInvocationExchange.routeBytes
            if prepaidRouteID == nil { try await growPool(owner: owner, by: pendingServiceMetadataBytes) }
            try validateOperation(operation, owner: owner)
            _ = try serviceConnection(connection)
            try validateServiceRequestSlots(ingress, owner: owner)
            let issued = IngressClaim(id: UUID(), handle: .service(token: ingress.token, encodedBytes: ingress.encodedBytes, sequence: ingress.sequence, kind: ingress.kind))
            claim = issued
            processes[owner]?.credits.ingress = issued
            installDelivery(.serviceReserved(routeID), owner: owner, incarnation: connection.incarnation)
            processes[owner]?.lastServiceSequence = ingress.sequence
            guard let bytes = serviceAdapter.takeServiceIngress(ingress, incarnation: connection.incarnation) else {
                throw failure(.invalidPayload)
            }
            taken = true
            guard bytes.count == ingress.encodedBytes, bytes.count <= ServiceFrameCodec.maximumEncodedBytes else {
                throw failure(.invalidPayload)
            }
            let request = try ServiceFrameCodec.decodeInvocationRequest(bytes,
                profile: connection.publicationConnection.negotiatedProtocol.serviceInvocationFrameProfile)
            var route = RuntimeServiceInvocationExchange.Route(id: routeID, consumer: owner,
                incarnation: connection.incarnation, connectionToken: connection.token, sequence: ingress.sequence,
                grantID: request.grantID, requestID: request.invocation.requestID,
                contractID: request.invocation.contractID, operation: request.invocation.operation,
                deadline: try currentInstant().monotonic + .seconds(max(0, request.invocation.deadline.timeIntervalSince(clock.now().wall))))
            invocationExchange.insert(route)
            installedRoute = true
            pendingServiceMetadataBytes = 0
            // Neither broker request retention nor work consume precedes both slot reservations.
            guard let grant = serviceGrants[request.grantID], grant.owner == owner else { throw failure(.permissionDenied) }
            guard grant.provider.addonID != owner else { throw failure(.resourceDenied) }
            let path = try serviceProviderPath(to: grant.provider)
            guard !path.contains(where: { $0.manifest.id == owner }),
                  path.allSatisfy({ processes[$0.manifest.id]?.credits.delivery == nil }),
                  let process = processes[grant.provider.addonID], case .connected(let providerConnection) = process.phase
            else { throw failure(.resourceDenied) }
            _ = try serviceConnection(providerConnection)
            route.provider = grant.provider.addonID
            route.providerIncarnation = process.incarnation
            route.providerReservation = UUID()
            route.deadline = min(route.deadline, grant.deadline)
            invocationExchange.update(route)
            installDelivery(.serviceReserved(route.providerReservation!), owner: grant.provider.addonID,
                            incarnation: process.incarnation)
            let work = try await beginServiceInvocationAdmitted(connection: connection, grantID: request.grantID,
                invocation: request.invocation, operation: operation, routeID: routeID)
            try validateInvocationReservations(routeID, operation: operation)
            guard var current = invocationExchange.routes[routeID] else { throw failure(.sessionRevoked) }
            current.workID = work.id; current.deadline = work.effectiveDeadline
            invocationExchange.update(current)
            let accepted = try await pumpServiceInvocationAdmitted(work.id, operation: operation, routeID: routeID)
            if !accepted { invocationExchange.mark(workID: work.id, terminal: .refused(.dependencyUnavailable)) }
            disposeIngress(issued, owner: owner, incarnation: connection.incarnation, disposition: .finish)
            return .admitted(routeID)
        } catch {
            pendingServiceMetadataBytes = 0
            if let claim {
                disposeIngress(claim, owner: owner, incarnation: connection.incarnation, disposition: taken ? .cancel : .reject)
            } else { serviceAdapter.rejectServiceIngress(ingress, incarnation: connection.incarnation) }
            if installedRoute, var route = invocationExchange.routes[routeID] {
                if route.terminal == nil { route.terminal = .refused(Self.serviceFailureCode(error)) }
                invocationExchange.update(route)
                releaseProviderRouteReservation(route)
                return .admitted(routeID)
            }
            releaseDelivery(.serviceReserved(routeID), owner: owner, incarnation: connection.incarnation)
            deferredPoolOwners.insert(owner)
            return .refused(Self.serviceFailureCode(error))
        }
    }

    private func validateServiceRequestSlots(_ ingress: RuntimeServiceIngressHandle, owner: AddonID) throws {
        guard let process = processes[owner], process.incarnation == ingress.incarnation,
              process.credits.ingress == nil, process.credits.delivery == nil,
              ingress.sequence > process.lastServiceSequence,
              invocationExchange.count + serviceConnections.count < RuntimeServiceInvocationExchange.maximumRoutes,
              !serviceConnections.contains(ingress.incarnation),
              !invocationExchange.hasRoute(incarnation: ingress.incarnation) else { throw failure(.resourceDenied) }
    }

    private func providerReservationHolds(_ routeID: UUID, process: ProcessRecord) -> Bool {
        guard let route = invocationExchange.routes[routeID], let nonce = route.providerReservation else { return false }
        return process.incarnation == route.providerIncarnation && process.credits.delivery == .serviceReserved(nonce)
    }

    private func validateInvocationReservations(_ routeID: UUID, operation: AdmissionOperation) throws {
        guard let route = invocationExchange.routes[routeID], let process = processes[route.consumer],
              case .connected(let connection) = process.phase,
              connection.token == route.connectionToken, process.incarnation == route.incarnation,
              process.credits.delivery == .serviceReserved(route.id),
              let grant = serviceGrants[route.grantID], grant.owner == route.consumer,
              grant.provider.addonID == route.provider,
              let provider = route.provider, let providerProcess = processes[provider],
              case .connected(let providerConnection) = providerProcess.phase,
              providerReservationHolds(routeID, process: providerProcess),
              try currentInstant().monotonic < min(route.deadline, grant.deadline)
        else { throw failure(.sessionRevoked) }
        try validateOperation(operation, owner: route.consumer)
        _ = try serviceConnection(connection)
        _ = try serviceConnection(providerConnection)
        let path = try serviceProviderPath(to: grant.provider)
        guard !path.contains(where: { $0.manifest.id == route.consumer }), path.allSatisfy({
            $0.manifest.id == provider || processes[$0.manifest.id]?.credits.delivery == nil
        }) else { throw failure(.resourceDenied) }
    }

    private func releaseProviderRouteReservation(_ route: RuntimeServiceInvocationExchange.Route) {
        if let provider = route.provider, let incarnation = route.providerIncarnation, let nonce = route.providerReservation {
            releaseDelivery(.serviceReserved(nonce), owner: provider, incarnation: incarnation)
        }
    }

    /// receiveServiceCompletionOutput treats the original raw byte count as authoritative;
    /// completion-only handling claims ingress once. No short admission is needed, so a held
    /// unrelated admission can defer the canonical commit.
    func receiveServiceCompletionOutput(_ ingress: RuntimeServiceIngressHandle, connection: RuntimeConnection)
        async throws -> PublicationOutputResult {
        guard let serviceAdapter = adapter as? any AddonRuntimeServiceAdapter else { throw failure(.versionConflict) }
        let owner: AddonID
        let claim: IngressClaim
        do {
            owner = try serviceConnection(connection)
            guard ingress.kind == .completion, ingress.incarnation == connection.incarnation,
                  ingress.encodedBytes > 0, ingress.encodedBytes <= ServiceFrameCodec.maximumEncodedBytes,
                  ingress.sequence > 0, processes[owner]?.credits.ingress == nil else { throw failure(.invalidPayload) }
            claim = IngressClaim(id: UUID(), handle: .service(token: ingress.token, encodedBytes: ingress.encodedBytes, sequence: ingress.sequence, kind: ingress.kind))
            processes[owner]?.credits.ingress = claim
        } catch {
            serviceAdapter.rejectServiceIngress(ingress, incarnation: ingress.incarnation)
            throw error
        }
        do {
            return try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes, owner: owner) {
                try await self.receiveServiceCompletionPrepared(ingress, claim: claim, connection: connection)
            }
        } catch {
            disposeIngress(claim, owner: owner, incarnation: connection.incarnation, disposition: .cancel)
            serviceAdapter.rejectServiceIngress(ingress, incarnation: connection.incarnation)
            throw error
        }
    }

    private func receiveServiceCompletionPrepared(_ ingress: RuntimeServiceIngressHandle, claim: IngressClaim,
        connection: RuntimeConnection) async throws -> PublicationOutputResult {
        let owner = try serviceConnection(connection)
        guard processes[owner]?.credits.ingress == claim,
              let bytes = (adapter as! any AddonRuntimeServiceAdapter).takeServiceIngress(ingress, incarnation: connection.incarnation),
              bytes.count == ingress.encodedBytes, bytes.count <= ServiceFrameCodec.maximumEncodedBytes else {
            throw failure(.invalidPayload)
        }
        let output = try ProviderOutput.decode(bytes)
        guard output.checkpoint == nil, output.publications.isEmpty, output.operations.isEmpty,
              case .service? = output.completion,
              let completion = try correlatedCompletion(output.completion, owner: owner, connection: connection)
        else { throw failure(.invalidPayload) }
        return try await receiveCompletionOnlyOutput(output, claim: claim, completion: completion,
                                                     connection: connection, sequence: ingress.sequence)
    }

    /// receiveServiceReceipt settles the delivery credit behind a payload receipt; payload receipts
    /// do not retire broker work or command/job authority.
    func receiveServiceReceipt(_ receipt: RuntimeServiceReceipt, connection: RuntimeConnection) async -> Bool {
        guard let owner = try? serviceConnection(connection), receipt.incarnation == connection.incarnation,
              receipt.connectionToken == connection.token,
              processes[owner]?.credits.delivery == .serviceAccepted(receipt.token) else { return false }
        switch receipt.kind {
        case .consumerReply:
            guard let route = invocationExchange.routes.values.first(where: { $0.acceptedReceipt == receipt }),
                  route.consumer == owner else { return false }
            releaseDelivery(.serviceAccepted(receipt.token), owner: owner, incarnation: connection.incarnation)
            invocationExchange.remove(route.id)
            deferredPoolOwners.insert(route.consumer)
        case .providerInvocation:
            guard processes[owner]?.servicePayloadReceipt == receipt else { return false }
            releaseDelivery(.serviceAccepted(receipt.token), owner: owner, incarnation: connection.incarnation)
            processes[owner]?.servicePayloadReceipt = nil
        }
        await drainIfNoActiveAdmission()
        return true
    }

    /// drainInvocationRoutes takes one bounded route snapshot per pass. Events arriving across its
    /// awaits are coalesced by drainIfNoActiveAdmission and serviced after this guard and admission
    /// are released. Canonical history is read once under current authority, then rechecked after
    /// workspace admission/history suspension and immediately before synchronous adapter handoff.
    private func drainInvocationRoutes() async {
        guard activeOperation == nil, !cleanupInProgress, !serviceRouteDrainInProgress,
              let serviceAdapter = adapter as? any AddonRuntimeServiceAdapter else { return }
        serviceRouteDrainInProgress = true
        defer { serviceRouteDrainInProgress = false }
        let readyIDs = invocationExchange.routes.values.filter { $0.terminal != nil }.map(\.id)
        for id in readyIDs {
            guard let route = invocationExchange.routes[id] else { continue }
            if route.acceptedReceipt != nil {
                if (try? serviceRouteTransport(route)) == nil { settleInvocationRoute(id, adapter: serviceAdapter) }
                continue
            }
            let operation: AdmissionOperation
            do {
                guard let admitted = try await tryBeginAdmission(owner: route.consumer, purpose: .normal,
                                                               forServiceRouteDrain: true) else { break }
                operation = admitted
            } catch { settleInvocationRoute(id, adapter: serviceAdapter); continue }
            do {
                try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes, owner: route.consumer) {
                    try await self.deliverInvocationRoute(id, operation: operation)
                }
            } catch { settleInvocationRoute(id, adapter: serviceAdapter) }
            finishAdmission(operation)
        }
        // The outer event drain owns subsequent cleanup/newly-ready snapshots. Do not
        // recurse from finishAdmission while this snapshot's guard is still held.
    }

    private func serviceRouteTransport(_ route: RuntimeServiceInvocationExchange.Route) throws -> RuntimeConnection {
        guard let current = invocationExchange.routes[route.id], current.connectionToken == route.connectionToken,
              let process = processes[route.consumer], process.incarnation == route.incarnation,
              case .connected(let connection) = process.phase, connection.token == route.connectionToken
        else { throw failure(.sessionRevoked) }
        _ = try serviceConnection(connection)
        return connection
    }

    private func serviceRouteAuthority(_ route: RuntimeServiceInvocationExchange.Route) throws -> RuntimeConnection {
        let connection = try serviceRouteTransport(route)
        guard let grant = serviceGrants[route.grantID], grant.owner == route.consumer,
              try currentInstant().monotonic < min(route.deadline, grant.deadline) else { throw failure(.permissionDenied) }
        return connection
    }

    private func deliverInvocationRoute(_ id: UUID, operation: AdmissionOperation) async throws {
        guard var route = invocationExchange.routes[id], let terminal = route.terminal,
              processes[route.consumer]?.credits.delivery == .serviceReserved(id) else { throw failure(.sessionRevoked) }
        try validateOperation(operation, owner: route.consumer)
        let connection = try serviceRouteTransport(route)
        var result: ServiceInvocationResult
        switch terminal {
        case .refused(let code): result = code == .outcomeUnknown ? .outcomeUnknown : .refused(code: code, reason: "The service host refused this exchange.")
        case .unknown: result = .outcomeUnknown
        case .completed:
            _ = try serviceRouteAuthority(route)
            guard !deferredServiceCompletions.values.contains(where: { $0.requestID == route.requestID && $0.grantID == route.grantID }),
                  route.workID.map({ !inFlightServiceCompletionIDs.contains($0) }) == true else { throw failure(.resourceDenied) }
            let outcome = try await broker.requestOutcome(session: connection.serviceSession, grantID: route.grantID,
                requestID: route.requestID, now: currentInstant())
#if DEBUG
            await Self.serviceInvocationObserver?(.historyRead)
#endif
            try validateOperation(operation, owner: route.consumer)
            _ = try serviceRouteAuthority(route)
            guard invocationExchange.routes[id]?.terminal == terminal,
                  case .completed(let response) = outcome, response.contractID == route.contractID,
                  response.operation == route.operation else { throw failure(.sessionRevoked) }
            result = .completed(response)
        }
        // Refused/unknown can settle an authenticated control route without history authority.
        if case .completed = result { _ = try serviceRouteAuthority(route) }
        let reply = try ServiceInvocationReply(requestID: route.requestID, contractID: route.contractID,
                                               operation: route.operation, result: result)
        let payload = try ServiceFrameCodec.encode(reply, profile: connection.publicationConnection.negotiatedProtocol.serviceInvocationFrameProfile)
#if DEBUG
        await Self.serviceInvocationObserver?(.encoded)
#endif
        try validateOperation(operation, owner: route.consumer)
        _ = try serviceRouteTransport(route)
        if case .completed = result { _ = try serviceRouteAuthority(route) }
#if DEBUG
        await Self.serviceInvocationObserver?(.handoff)
#endif
        try validateOperation(operation, owner: route.consumer)
        _ = try serviceRouteTransport(route)
        if case .completed = result { _ = try serviceRouteAuthority(route) }
        guard invocationExchange.routes[id]?.terminal == terminal,
              processes[route.consumer]?.credits.delivery == .serviceReserved(id) else { throw failure(.sessionRevoked) }
        let receipt = RuntimeServiceReceipt(token: id, incarnation: route.incarnation, connectionToken: route.connectionToken,
                                            sequence: route.sequence, requestID: route.requestID, kind: .consumerReply)
        guard adapter.tryHandoff(incarnation: route.incarnation,
            delivery: .serviceReply(RuntimeServiceDelivery(receipt: receipt, payload: payload))) == .accepted else {
            throw failure(.outcomeUnknown)
        }
        releaseDelivery(.serviceReserved(id), owner: route.consumer, incarnation: route.incarnation)
        installDelivery(.serviceAccepted(receipt.token), owner: route.consumer, incarnation: route.incarnation)
        route.acceptedReceipt = receipt
        invocationExchange.update(route)
        releaseProviderRouteReservation(route)
    }

    private func settleInvocationRoute(_ id: UUID, adapter: any AddonRuntimeServiceAdapter) {
        guard let route = invocationExchange.remove(id) else { return }
        if let receipt = route.acceptedReceipt { releaseDelivery(.serviceAccepted(receipt.token), owner: route.consumer, incarnation: route.incarnation) }
        else { releaseDelivery(.serviceReserved(id), owner: route.consumer, incarnation: route.incarnation) }
        releaseProviderRouteReservation(route)
        adapter.settleServiceExchange(route.settlement)
        deferredPoolOwners.insert(route.consumer)
        serviceEventDrainRequested = true
    }

    /// removeSubscriptionSource removes a source row, which pays the indirect delivery credit. Retire
    /// that exact credit synchronously with its physical payload, before any refund can drop the row.
    @discardableResult
    private func removeSubscriptionSource(_ sourceID: UUID) -> RuntimeServiceSourceBinding? {
        guard let source = serviceSources.removeValue(forKey: sourceID) else { return nil }
        if let receipt = source.receipt {
            releaseDelivery(.subscriptionAccepted(receipt), owner: source.key.provider.addonID,
                            incarnation: source.incarnation)
        }
        deferredPoolOwners.insert(source.key.provider.addonID)
        return source
    }

    private func invalidateSubscriptionConnection(_ incarnation: RuntimeIncarnation) {
        for id in Array(serviceSubscriptions.aliases.keys) {
            guard let alias = serviceSubscriptions.aliases[id], alias.connection.incarnation == incarnation else { continue }
            serviceSubscriptions.aliases.removeValue(forKey: id)
            if let receipt = alias.receipt { releaseDelivery(.subscriptionAccepted(receipt), owner: alias.connection.identity.addonID, incarnation: incarnation) }
            deferredPoolOwners.insert(alias.connection.identity.addonID)
        }
        serviceSubscriptions.cursor.removeValue(forKey: incarnation)
        for id in Array(serviceConnections.controls.keys) where serviceConnections.controls[id]?.connection.incarnation == incarnation { settleControl(id) }
        if let parked = serviceConnections.parked[incarnation] { disposeParked(parked) }
        for id in Array(serviceSources.keys) {
            guard let source = serviceSources[id], source.incarnation == incarnation else { continue }
            removeSubscriptionSource(id)
        }
    }

    private func subscriptionConnection(_ connection: RuntimeConnection) throws -> AddonID {
        let owner = try serviceConnection(connection)
        guard serviceSubscriptionsEnabled, adapter is any AddonRuntimeServiceSubscriptionAdapter,
              connection.publicationConnection.negotiatedProtocol.minor >= 4 else { throw failure(.versionConflict) }
        return owner
    }

    func receiveServiceControl(_ ingress: RuntimeServiceIngressHandle, connection: RuntimeConnection)
        async -> RuntimeServiceInvocationExchange.Admission {
        guard let transport = adapter as? any AddonRuntimeServiceSubscriptionAdapter else { return .refused(.versionConflict) }
        let operation: AdmissionOperation
        do {
            _ = try subscriptionConnection(connection)
            guard ingress.kind == .control, ingress.incarnation == connection.incarnation,
                  ingress.encodedBytes > 0, ingress.encodedBytes <= ServiceSubscriptionFrameCodec.maximumEncodedBytes,
                  ingress.sequence > 0 else { throw failure(.invalidPayload) }
            operation = try await beginAdmission(owner: connection.identity.addonID)
        } catch {
            transport.rejectServiceIngress(ingress, incarnation: ingress.incarnation)
            return .refused(Self.serviceFailureCode(error))
        }
        let result: RuntimeServiceInvocationExchange.Admission
        do {
            if let parked = try await parkServiceIngressIfNeeded(ingress, connection: connection, operation: operation) {
                await finishAdmissionAndDrain(operation)
                return .admitted(parked)
            }
            result = try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes, owner: connection.identity.addonID) {
                await self.receiveControlAdmitted(ingress, connection: connection, operation: operation)
            }
        } catch {
            transport.rejectServiceIngress(ingress, incarnation: ingress.incarnation)
            result = .refused(Self.serviceFailureCode(error))
        }
        await finishAdmissionAndDrain(operation)
        return result
    }

    private func receiveControlAdmitted(_ ingress: RuntimeServiceIngressHandle, connection: RuntimeConnection,
                                       operation: AdmissionOperation, prepaidRouteID: UUID? = nil) async -> RuntimeServiceInvocationExchange.Admission {
        let owner = connection.identity.addonID
        let transport = adapter as! any AddonRuntimeServiceSubscriptionAdapter
        let id = prepaidRouteID ?? UUID()
        var claim: IngressClaim?
        var taken = false
        do {
            try validateOperation(operation, owner: owner)
            _ = try subscriptionConnection(connection)
            try validateServiceRequestSlots(ingress, owner: owner)
            pendingServiceMetadataBytes = RuntimeServiceAcquisitionState.bytes
            if prepaidRouteID == nil { try await growPool(owner: owner, by: pendingServiceMetadataBytes) }
            try validateOperation(operation, owner: owner)
            _ = try subscriptionConnection(connection)
            try validateServiceRequestSlots(ingress, owner: owner)
            let issued = IngressClaim(id: UUID(), handle: .service(token: ingress.token, encodedBytes: ingress.encodedBytes,
                                                                  sequence: ingress.sequence, kind: ingress.kind))
            claim = issued
            processes[owner]?.credits.ingress = issued
            installDelivery(.serviceReserved(id), owner: owner, incarnation: connection.incarnation)
            processes[owner]?.lastServiceSequence = ingress.sequence
            guard let bytes = transport.takeServiceIngress(ingress, incarnation: connection.incarnation) else {
                throw failure(.invalidPayload)
            }
            taken = true
            guard bytes.count == ingress.encodedBytes else { throw failure(.invalidPayload) }
            let request = try ServiceSubscriptionFrameCodec.decodeControlRequest(bytes, profile: .v1_4)
            serviceConnections.controls[id] = RuntimeServiceAcquisitionState(id: id, connection: connection,
                sequence: ingress.sequence, request: request, deadline: try currentInstant().monotonic + .seconds(30))
            pendingServiceMetadataBytes = 0
            try await executeServiceControl(id, operation: operation)
            disposeIngress(issued, owner: owner, incarnation: connection.incarnation, disposition: .finish)
            return .admitted(id)
        } catch {
            pendingServiceMetadataBytes = 0
            if let claim { disposeIngress(claim, owner: owner, incarnation: connection.incarnation, disposition: taken ? .cancel : .reject) }
            else { transport.rejectServiceIngress(ingress, incarnation: ingress.incarnation) }
            if var route = serviceConnections.controls[id] {
                route.terminal = route.committed ? .outcomeUnknown : .refused(code: Self.serviceFailureCode(error) == .outcomeUnknown ? .dependencyUnavailable : Self.serviceFailureCode(error), reason: "Service control refused before effects")
                serviceConnections.controls[id] = route
                return .admitted(id)
            }
            releaseDelivery(.serviceReserved(id), owner: owner, incarnation: connection.incarnation)
            deferredPoolOwners.insert(owner)
            return .refused(Self.serviceFailureCode(error))
        }
    }

    private func controlTransport(_ id: UUID, operation: AdmissionOperation) throws -> RuntimeServiceAcquisitionState {
        guard let route = serviceConnections.controls[id], !route.transportSettled else { throw failure(.sessionRevoked) }
        try validateOperation(operation, owner: route.connection.identity.addonID)
        _ = try subscriptionConnection(route.connection)
        guard try currentInstant().monotonic < route.deadline else { throw failure(.deadlineExceeded) }
        return route
    }

    private func executeServiceControl(_ id: UUID, operation: AdmissionOperation) async throws {
        var route = try controlTransport(id, operation: operation)
        let connection = route.connection, owner = connection.identity.addonID
        switch route.request.action {
        case .acquire(.requestService(let requirementID, let scope)):
            let permissionID = try await broker.permissionID(session: connection.serviceSession, requirementID: requirementID,
                                                              scope: scope, now: currentInstant())
            route = try controlTransport(id, operation: operation)
            guard let permission = servicePermissions[permissionID], permission.owner == owner,
                  permission.requirementID == requirementID, permission.scope == scope else { throw failure(.permissionDenied) }
            let path = try serviceProviderPath(to: permission.provider)
            guard !path.contains(where: { $0.manifest.id == owner }) else { throw failure(.resourceDenied) }
            for installed in path {
                if let process = processes[installed.manifest.id], case .connected(let peer) = process.phase {
                    _ = try subscriptionConnection(peer)
                }
            }
            // A legacy live startup cannot be promoted by a new consumer offer.
            for grant in serviceGrants.values where grant.provider == permission.provider {
                if serviceSources[grant.sourceID] == nil,
                   !serviceConnections.controls.values.contains(where: {
                       !$0.transportSettled && $0.terminal == nil && $0.acquisition?.sourceID == grant.sourceID
                   }) { throw failure(.versionConflict) }
            }
            try await growPool(owner: owner, by: Self.serviceGrantBytes)
            _ = try controlTransport(id, operation: operation)
            _ = try await broker.permissionID(session: connection.serviceSession, requirementID: requirementID, scope: scope, now: currentInstant())
            _ = try controlTransport(id, operation: operation)
            let acquired = try await broker.acquire(session: connection.serviceSession, requirementID: requirementID,
                                                     scope: scope, now: currentInstant(), lifetime: .seconds(3_600),
                                                     allowNewSourceStart: isFreshAdmissionOpen(permission.provider),
                                                     allowNewConsumerInterest: isFreshAdmissionOpen(connection.identity))
            // Canonical commit happened even if runtime authority was withdrawn during await.
            serviceConnections.controls[id]?.committed = true
            serviceConnections.controls[id]?.acquisition = acquired
            serviceConnections.controls[id]?.needsStart = acquired.decisions.contains(.startSource(acquired.sourceID))
#if DEBUG
            // Scalar-only causal seam: the broker committed, but transport/deadline
            // authority has not yet been revalidated. No production suspension.
            await Self.serviceSubscriptionObserver?(.acquisitionCommitted)
#endif
            do {
                try requireNewConsumerFreshAdmissionOpen(acquired, owner: owner)
            } catch {
                await broker.rollbackAcquisition(acquired)
                // The broker interest is gone, but this committed intent still
                // needs its admission acknowledgement before terminal unknown.
                // Keep only the immutable acquisition receipt metadata.
                serviceConnections.controls[id]?.needsStart = false
                throw error
            }
            route = try controlTransport(id, operation: operation)
            route.deadline = min(route.deadline, acquired.effectiveDeadline)
            serviceConnections.controls[id] = route
            serviceGrants[acquired.grant.id] = ServiceGrantRecord(owner: owner, provider: permission.provider,
                sourceID: acquired.sourceID, deadline: acquired.effectiveDeadline)
            // Progress is event-driven after the raw input and short admission retire.
        case .acquire: throw failure(.invalidPayload)
        case .subscribe(let requirementID, let grantID):
            let binding = try await broker.bindSubscription(session: connection.serviceSession, grantID: grantID,
                                                             requirementID: requirementID, now: currentInstant())
            _ = try controlTransport(id, operation: operation)
            guard serviceGrants[grantID]?.owner == owner else { throw failure(.permissionDenied) }
            let previous = serviceSubscriptions.existing(interestID: binding.interestID, incarnation: connection.incarnation)
            if previous == nil {
                guard serviceSubscriptions.aliases.count < ServiceSubscriptionRegistry.maximumAliases,
                      serviceSubscriptions.aliases.values.filter({ $0.connection.identity.addonID == owner }).count < ServiceSubscriptionRegistry.maximumPerOwner else { throw failure(.resourceDenied) }
                try await growPool(owner: owner, by: ServiceSubscriptionRegistry.Alias.bytes)
            }
            _ = try controlTransport(id, operation: operation)
            let fresh = try await broker.bindSubscription(session: connection.serviceSession, grantID: grantID,
                                                           requirementID: requirementID, now: currentInstant())
            _ = try controlTransport(id, operation: operation)
            guard fresh.interestID == binding.interestID, fresh.key == binding.key else { throw failure(.sessionRevoked) }
            var alias = previous ?? ServiceSubscriptionRegistry.Alias(id: UUID(), connection: connection,
                interestID: fresh.interestID, sourceID: fresh.sourceID, permissionID: fresh.permissionID,
                requirementID: requirementID, grantID: grantID, deadline: fresh.deadline)
            if previous != nil {
                guard alias.revision < UInt64.max else { throw failure(.resourceDenied) }
                alias.revision += 1
                alias.grantID = grantID; alias.deadline = fresh.deadline
                alias.deliveredRevision = 0
            }
            alias.pendingRevision = serviceCache.entries[fresh.sourceID]?.revision ?? 0
            serviceSubscriptions.aliases[alias.id] = alias
            serviceConnections.controls[id]?.committed = true
            serviceConnections.controls[id]?.terminal = .subscribed(alias.id)
        case .unsubscribe(let aliasID):
            guard let alias = serviceSubscriptions.aliases[aliasID], alias.connection.token == connection.token,
                  alias.connection.incarnation == connection.incarnation else { throw failure(.permissionDenied) }
            _ = try await broker.bindSubscription(session: connection.serviceSession, grantID: alias.grantID,
                                                   requirementID: alias.requirementID, now: currentInstant())
            _ = try controlTransport(id, operation: operation)
            guard serviceSubscriptions.aliases[aliasID]?.revision == alias.revision else { throw failure(.permissionDenied) }
            serviceSubscriptions.aliases.removeValue(forKey: aliasID)
            serviceConnections.controls[id]?.committed = true
            let decisions = try await broker.unsubscribe(session: connection.serviceSession, interestID: alias.interestID)
            await executeSubscriptionDecisions(decisions, operation: operation)
            await reconcileBrokerAuthority(stopReason: .stopped)
            _ = try controlTransport(id, operation: operation)
            serviceConnections.controls[id]?.terminal = .acknowledged
            deferredPoolOwners.insert(owner)
        }
    }

    private func executeSubscriptionDecisions(_ decisions: [ServiceDecision], operation: AdmissionOperation) async {
        for decision in decisions {
            switch decision {
            case .stopSource(let sourceID):
                if let source = removeSubscriptionSource(sourceID) {
                    requestStopOnce(owner: source.key.provider.addonID, reason: .stopped)
                    deferredPoolOwners.insert(source.key.provider.addonID)
                }
                if let entry = serviceCache.entries.removeValue(forKey: sourceID) { deferredPoolOwners.insert(entry.key.provider.addonID) }
            case .wakeConsumer: break // Retained canonical wake is consumed by the event drain below.
            case .startSource: break // Owned by a paid acquisition route.
            }
        }
    }

    private func progressAcquisition(_ id: UUID, operation: AdmissionOperation) async throws {
        var route = try controlTransport(id, operation: operation)
        guard let acquired = route.acquisition else { return }
        let owner = route.connection.identity.addonID
        guard case .acquire(.requestService(let requirementID, _)) = route.request.action else { throw failure(.invalidPayload) }
        let binding = try await broker.bindSubscription(session: route.connection.serviceSession, grantID: acquired.grant.id,
                                                        requirementID: requirementID, now: currentInstant())
        route = try controlTransport(id, operation: operation)
        if route.needsStart, serviceSources[acquired.sourceID] == nil {
            try requireFreshAdmissionOpen(owner: binding.key.provider.addonID)
        }
        let path = try serviceProviderPath(to: binding.key.provider)
        try await admitMissingProviderPath(path, operation: operation, admissionOwner: owner)
        route = try controlTransport(id, operation: operation)
        for installed in path {
            guard let process = processes[installed.manifest.id], case .connected(let peer) = process.phase else { return }
            _ = try subscriptionConnection(peer)
        }
        if route.needsStart, serviceSources[acquired.sourceID] == nil {
            try requireFreshAdmissionOpen(owner: binding.key.provider.addonID)
            try await startSubscriptionSource(binding, routeID: id, operation: operation)
            _ = try controlTransport(id, operation: operation)
        }
        guard let source = serviceSources[acquired.sourceID], source.ready, source.receipt == nil,
              source.key == binding.key, let process = processes[source.key.provider.addonID],
              process.incarnation == source.incarnation, case .connected(let provider) = process.phase,
              provider.token == source.connectionToken else { return }
        let fresh = try await broker.bindSubscription(session: route.connection.serviceSession, grantID: acquired.grant.id,
                                                      requirementID: requirementID, now: currentInstant())
        _ = try controlTransport(id, operation: operation)
        guard fresh.grant == acquired.grant, serviceSources[acquired.sourceID]?.ready == true else { throw failure(.sessionRevoked) }
        serviceConnections.controls[id]?.terminal = .acquired(fresh.grant)
    }

    private func startSubscriptionSource(_ binding: ServiceSubscriptionBinding, routeID: UUID,
                                         operation: AdmissionOperation) async throws {
        let provider = binding.key.provider.addonID
        guard serviceSources.count < 128, let process = processes[provider], case .connected(let connection) = process.phase,
              process.credits.delivery == nil else { return }
        try requireFreshAdmissionOpen(owner: provider)
        _ = try subscriptionConnection(connection)
        try await growPool(owner: provider, by: RuntimeServiceSourceBinding.bytes + Self.sourceExecutionBytes)
        _ = try controlTransport(routeID, operation: operation)
        do {
            try requireFreshAdmissionOpen(owner: provider)
        } catch {
            await shrinkPoolToCurrent(owner: provider)
            throw error
        }
        let job = try await resourceAccess.admit(.job, owner: provider)
        var handed = false
        do {
            _ = try controlTransport(routeID, operation: operation)
            try requireFreshAdmissionOpen(owner: provider)
            let descriptor = try await serviceDecisionAccess.consumeSourceStart(binding.sourceID, now: currentInstant())
            _ = try controlTransport(routeID, operation: operation)
            try requireFreshAdmissionOpen(owner: provider)
            let canonical = try await broker.sourceBinding(sourceID: binding.sourceID, now: currentInstant())
            _ = try controlTransport(routeID, operation: operation)
            try requireFreshAdmissionOpen(owner: provider)
            _ = try subscriptionConnection(connection)
            guard canonical.key == binding.key, canonical.startConsumed, !canonical.restartRequired,
                  processes[provider]?.credits.delivery == nil else { throw failure(.sessionRevoked) }
            let frame = try ServiceSourceStartFrame(sourceID: binding.sourceID, startNonce: UUID(), providerID: provider,
                publisher: descriptor.provider.publisher, digest: descriptor.digest, contractVersion: descriptor.contractVersion,
                serviceID: descriptor.serviceID, partition: descriptor.partition,
                scope: ServiceScope(featureID: descriptor.featureID, operation: descriptor.operation))
            let payload = try ServiceSubscriptionFrameCodec.encode(frame, profile: .v1_4)
            let receipt = RuntimeServiceSubscriptionReceipt(token: UUID(), incarnation: connection.incarnation,
                connectionToken: connection.token, sequence: 0, kind: .sourceStart(sourceID: binding.sourceID, startNonce: frame.startNonce))
            guard adapter.tryHandoff(incarnation: connection.incarnation,
                delivery: .serviceSourceStart(RuntimeServiceSubscriptionDelivery(receipt: receipt, payload: payload))) == .accepted else {
                throw failure(.dependencyUnavailable)
            }
            handed = true
            serviceSources[binding.sourceID] = RuntimeServiceSourceBinding(frame: frame, key: binding.key,
                incarnation: connection.incarnation, connectionToken: connection.token, receipt: receipt)
            // Acceptance ends pending-start ownership synchronously. A later
            // connection invalidation must not make an actually handed start look
            // abandoned merely because its persistent binding was removed.
            for id in Array(serviceConnections.controls.keys)
                where serviceConnections.controls[id]?.acquisition?.sourceID == binding.sourceID {
                serviceConnections.controls[id]?.needsStart = false
            }
            sourceExecutions[binding.sourceID] = SourceExecutionRecord(provider: provider, providerIncarnation: connection.incarnation,
                deadline: min(binding.deadline, try currentInstant().monotonic + .seconds(30)), job: job, isHandedOff: true)
            installDelivery(.subscriptionAccepted(receipt), owner: provider, incarnation: connection.incarnation)
        } catch {
            if !handed { deferRelease(job, owner: provider) }
            deferredPoolOwners.insert(provider)
            throw error
        }
    }

    func receiveServiceSourceOutput(_ ingress: RuntimeServiceIngressHandle, connection: RuntimeConnection)
        async -> RuntimeServiceSourceOutputResult {
        guard let transport = adapter as? any AddonRuntimeServiceSubscriptionAdapter else { return .refused(.versionConflict) }
        let owner = connection.identity.addonID
        do {
            _ = try subscriptionConnection(connection)
            guard ingress.kind == .sourceOutput, ingress.incarnation == connection.incarnation,
                  ingress.encodedBytes > 0, ingress.encodedBytes <= ServiceSubscriptionFrameCodec.maximumEncodedBytes,
                  processes[owner]?.credits.ingress == nil else { throw failure(.invalidPayload) }
        } catch {
            transport.rejectServiceIngress(ingress, incarnation: ingress.incarnation)
            return .refused(Self.serviceFailureCode(error))
        }
        let claim = IngressClaim(id: UUID(), handle: .service(token: ingress.token, encodedBytes: ingress.encodedBytes,
                                                            sequence: ingress.sequence, kind: ingress.kind))
        processes[owner]?.credits.ingress = claim
        let result: RuntimeServiceSourceOutputResult
        do {
            try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes, owner: owner) {
                try await self.acceptServiceSourceOutput(ingress, connection: connection, claim: claim)
            }
            disposeIngress(claim, owner: owner, incarnation: connection.incarnation, disposition: .finish)
            result = .accepted
        } catch {
            disposeIngress(claim, owner: owner, incarnation: connection.incarnation, disposition: .cancel)
            transport.rejectServiceIngress(ingress, incarnation: ingress.incarnation)
            result = .refused(Self.serviceFailureCode(error))
        }
        deferredPoolOwners.insert(owner)
        await drainIfNoActiveAdmission()
        return result
    }

    private func acceptServiceSourceOutput(_ ingress: RuntimeServiceIngressHandle, connection: RuntimeConnection,
                                          claim: IngressClaim) async throws {
        let owner = try subscriptionConnection(connection)
        guard processes[owner]?.credits.ingress == claim,
              let bytes = (adapter as! any AddonRuntimeServiceSubscriptionAdapter).takeServiceIngress(ingress, incarnation: connection.incarnation),
              bytes.count == ingress.encodedBytes else { throw failure(.invalidPayload) }
        let output = try ServiceSubscriptionFrameCodec.decodeSourceOutput(bytes, profile: .v1_4)
        guard let source = serviceSources[output.sourceID], source.incarnation == connection.incarnation,
              source.connectionToken == connection.token else { throw failure(.permissionDenied) }
        try output.validate(matching: source.frame)
        try publicationState.validateServiceSourceSequence(connection: connection.publicationConnection, sequence: ingress.sequence)
        let revision = authorityRevision
        let canonical = try await broker.sourceBinding(sourceID: output.sourceID, now: currentInstant())
        try validateOperation(revision, owner: owner)
        _ = try subscriptionConnection(connection)
        guard processes[owner]?.credits.ingress == claim, canonical.key == source.key,
              canonical.startConsumed, !canonical.restartRequired,
              serviceSources[output.sourceID]?.frame.startNonce == source.frame.startNonce else { throw failure(.permissionDenied) }
        // Finite completion is an out-of-band lifecycle event. Its already-paid
        // scalar transition/job refund must not wait for an unrelated admission.
        if case .startupCompleted = output.output {
            guard !source.ready, let execution = sourceExecutions[output.sourceID],
                  execution.providerIncarnation == connection.incarnation,
                  try currentInstant().monotonic < execution.deadline else { throw failure(.invalidPayload) }
            try publicationState.commitServiceSourceSequence(connection: connection.publicationConnection, sequence: ingress.sequence)
            serviceSources[output.sourceID]?.ready = true
            sourceExecutions.removeValue(forKey: output.sourceID)
            deferRelease(execution.job, owner: owner)
            return
        }
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        switch output.output {
        case .startupCompleted: throw failure(.invalidPayload)
        case .sourceUpdate(let response):
            guard source.ready else { throw failure(.permissionDenied) }
            let revision = try serviceCache.nextRevision(sourceID: output.sourceID)
            // Pay full replacement while the old backing is still retained. No swap on denial.
            try await growPool(owner: owner, by: ServiceLatestStateCache.Entry.metadataBytes + response.payload.count)
            try validateOperation(operation, owner: owner)
            let fresh = try await broker.sourceBinding(sourceID: output.sourceID, now: currentInstant())
            try validateOperation(operation, owner: owner)
            _ = try subscriptionConnection(connection)
            guard fresh.key == source.key, !fresh.restartRequired,
                  serviceSources[output.sourceID]?.frame.startNonce == source.frame.startNonce,
                  serviceSources[output.sourceID]?.ready == true else { throw failure(.permissionDenied) }
            try publicationState.validateServiceSourceSequence(connection: connection.publicationConnection, sequence: ingress.sequence)
            try serviceCache.replace(sourceID: output.sourceID, key: fresh.key, response: response, revision: revision)
            try publicationState.commitServiceSourceSequence(connection: connection.publicationConnection, sequence: ingress.sequence)
            for id in serviceSubscriptions.aliases.keys where serviceSubscriptions.aliases[id]?.sourceID == output.sourceID {
                serviceSubscriptions.aliases[id]?.pendingRevision = revision
            }
            let decisions = await broker.sourceChanged(output.sourceID, now: clock.now())
            await executeSubscriptionDecisions(decisions, operation: operation)
        }
    }

    /// abandonControlSourceStart retires only this abandoned intent. A live route sharing the
    /// canonical source inherits the one pending start; otherwise the next explicit acquire rearms it.
    @discardableResult
    private func abandonControlSourceStart(_ id: UUID) async -> Bool {
        guard let route = serviceConnections.controls[id], route.needsStart else { return true }
        guard route.committed, let acquired = route.acquisition,
              serviceSources[acquired.sourceID] == nil,
              sourceExecutions[acquired.sourceID] == nil else { return false }
        let successor = serviceConnections.controls.values.first {
            $0.id != id && !$0.transportSettled && $0.committed && $0.terminal == nil
                && $0.acquisition?.sourceID == acquired.sourceID
                && $0.deadline > clock.now().monotonic
                && (try? subscriptionConnection($0.connection)) != nil
        }
        // Public admissions cannot replace startup ownership during this outer
        // drain. Lifecycle callbacks can settle a row, but cannot remove it here.
        guard await broker.abandonUnhandedAcquisition(acquired, startTransferred: successor != nil) else { return false }
        if let successor {
            serviceConnections.controls[successor.id]?.needsStart = true
            // A successor settled during the broker refund still owns this paid
            // disposition; a following bounded pass rearms or transfers it again.
            serviceEventDrainRequested = true
        }
        serviceConnections.controls[id]?.needsStart = false
        serviceGrants.removeValue(forKey: acquired.grant.id)
        await reconcileBrokerAuthority(stopReason: .stopped)
        return true
    }

    private func drainSubscriptionRoutes() async {
        guard serviceSubscriptionsEnabled, activeOperation == nil, !cleanupInProgress, !subscriptionDrainInProgress,
              adapter is any AddonRuntimeServiceSubscriptionAdapter else { return }
        subscriptionDrainInProgress = true
        defer { subscriptionDrainInProgress = false }
        for id in Array(serviceConnections.controls.keys) {
            guard let route = serviceConnections.controls[id] else { continue }
            if route.transportSettled {
                guard await abandonControlSourceStart(id) else { continue }
                serviceConnections.controls.removeValue(forKey: id)
                deferredPoolOwners.insert(route.connection.identity.addonID)
                // Retiring this paid row is new cleanup work, not a refund retry.
                serviceEventDrainRequested = true
                continue
            }
            guard (try? subscriptionConnection(route.connection)) != nil else { settleControl(id); continue }
            let operation: AdmissionOperation
            do {
                guard let admitted = try await tryBeginAdmission(owner: route.connection.identity.addonID,
                    purpose: .normal, forServiceRouteDrain: true) else { break }
                operation = admitted
            } catch { settleControl(id); continue }
            do {
                if route.committed, route.acquisition != nil {
                    // The first ack is encoded in the same single reserved slot.
                    // A post-commit failure can already have set terminal unknown;
                    // that does not erase the required admission phase.
                    if route.receipt == nil && !route.admissionReceived {
                        do {
                            try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes, owner: route.connection.identity.addonID) {
                                try await self.deliverControl(id, phase: .admission, result: .accepted, operation: operation)
                            }
                        } catch {
                            // Lost admission delivery settles the physical exchange;
                            // it cannot be relabeled request-side non-exposure.
                            settleControl(id)
                            finishAdmission(operation)
                            continue
                        }
                    }
                    if route.terminal == nil { try await progressAcquisition(id, operation: operation) }
                }
            } catch {
                serviceConnections.controls[id]?.terminal = .outcomeUnknown
            }
            if serviceConnections.controls[id]?.terminal != nil { await abandonControlSourceStart(id) }
            if let current = serviceConnections.controls[id], current.receipt == nil, let terminal = current.terminal {
                do {
                    try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes, owner: current.connection.identity.addonID) {
                        try await self.deliverControl(id, phase: .terminal, result: terminal, operation: operation)
                    }
                } catch {
                    if terminal != .outcomeUnknown, (try? subscriptionConnection(current.connection)) != nil {
                        serviceConnections.controls[id]?.terminal = .outcomeUnknown
                        // One bounded downgrade; unknown's own failure settles physically.
                        serviceEventDrainRequested = true
                    } else { settleControl(id) }
                }
            }
            finishAdmission(operation)
        }
        for installed in catalog.values where processes[installed.manifest.id] == nil {
            guard await broker.pendingWakeIsCurrent(consumer: installed.verifiedIdentity, now: clock.now()) else { continue }
            let operation: AdmissionOperation
            do {
                guard let admitted = try await tryBeginAdmission(owner: installed.manifest.id, purpose: .normal, forServiceRouteDrain: true) else { break }
                operation = admitted
            } catch { continue }
            if await broker.pendingWakeIsCurrent(consumer: installed.verifiedIdentity, now: clock.now()) {
                try? await admitMissingProviderPath([installed], operation: operation, admissionOwner: installed.manifest.id)
            }
            finishAdmission(operation)
        }
        // Resume parked ingress ahead of further events on its physical connection.
        for parked in Array(serviceConnections.parked.values) {
            let owner = parked.connection.identity.addonID
            guard (try? subscriptionConnection(parked.connection)) != nil else { disposeParked(parked); continue }
            if clock.now().monotonic >= parked.deadline { disposeParked(parked); continue }
            guard processes[owner]?.credits.delivery == nil else { continue }
            let operation: AdmissionOperation
            do {
                guard let admitted = try await tryBeginAdmission(owner: owner, purpose: .normal, forServiceRouteDrain: true) else { break }
                operation = admitted
            } catch { disposeParked(parked); continue }
            serviceConnections.parked.removeValue(forKey: parked.connection.incarnation)
            processes[owner]?.credits.ingress = nil // Still staged, never transferred; next claim owns transfer.
            do {
                let resumed = try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes, owner: owner) {
                    if parked.ingress.kind == .invocation {
                        return await self.receiveServiceRequestAdmitted(parked.ingress, connection: parked.connection, operation: operation, prepaidRouteID: parked.id)
                    }
                    return await self.receiveControlAdmitted(parked.ingress, connection: parked.connection, operation: operation, prepaidRouteID: parked.id)
                }
                if case .refused = resumed { disposeParked(parked) }
            } catch {
                disposeParked(parked)
            }
            deferredPoolOwners.insert(owner)
            finishAdmission(operation)
            // Resumption happened after this pass's control/invocation snapshot.
            // Hand newly terminal work back to the SAME outer event owner.
            serviceEventDrainRequested = true
        }
        // One eligible event per connection per pass, stable round-robin alias order.
        for process in Array(processes.values) {
            guard process.credits.delivery == nil, case .connected(let connection) = process.phase,
                  !invocationExchange.hasRoute(incarnation: connection.incarnation),
                  !serviceConnections.contains(connection.incarnation),
                  let alias = serviceSubscriptions.next(incarnation: connection.incarnation) else { continue }
            let operation: AdmissionOperation
            do {
                guard let admitted = try await tryBeginAdmission(owner: connection.identity.addonID, purpose: .normal,
                                                                 forServiceRouteDrain: true) else { break }
                operation = admitted
            } catch { continue }
            do {
                try await governor.withAssetDecodeReservation(bytes: Self.serviceWorkspaceBytes, owner: connection.identity.addonID) {
                    try await self.deliverSubscriptionEvent(alias.id, operation: operation)
                }
            } catch {
                if (try? subscriptionConnection(connection)) == nil || clock.now().monotonic >= alias.deadline {
                    serviceSubscriptions.aliases.removeValue(forKey: alias.id)
                    deferredPoolOwners.insert(connection.identity.addonID)
                }
            }
            finishAdmission(operation)
        }
    }

    private func validateAcquisitionReadiness(_ binding: ServiceSubscriptionBinding) throws {
        guard let source = serviceSources[binding.sourceID], source.key == binding.key,
              source.ready, source.receipt == nil,
              let provider = processes[binding.key.provider.addonID],
              provider.incarnation == source.incarnation, case .connected(let connection) = provider.phase,
              connection.token == source.connectionToken else { throw failure(.dependencyUnavailable) }
        let path = try serviceProviderPath(to: binding.key.provider)
        for installed in path {
            guard let process = processes[installed.manifest.id], process.identity == installed.verifiedIdentity,
                  process.digest == installed.digest, case .connected(let peer) = process.phase else { throw failure(.dependencyUnavailable) }
            _ = try subscriptionConnection(peer)
        }
    }

    private func deliverControl(_ id: UUID, phase: ServiceControlPhase, result: ServiceControlResult,
                                operation: AdmissionOperation) async throws {
        guard let route = serviceConnections.controls[id], route.receipt == nil else { throw failure(.sessionRevoked) }
        let owner = route.connection.identity.addonID
        try validateOperation(operation, owner: owner)
        _ = try subscriptionConnection(route.connection)
        guard processes[owner]?.credits.delivery == .serviceReserved(id) else { throw failure(.resourceDenied) }
        if case .acquired(let grant) = result {
            guard case .acquire(.requestService(let requirementID, _)) = route.request.action else { throw failure(.invalidPayload) }
            let current = try await broker.bindSubscription(session: route.connection.serviceSession, grantID: grant.id,
                                                              requirementID: requirementID, now: currentInstant())
            _ = try controlTransport(id, operation: operation)
            guard current.grant == grant else { throw failure(.permissionDenied) }
            try validateAcquisitionReadiness(current)
        }
        if case .subscribed(let aliasID) = result {
            guard let alias = serviceSubscriptions.aliases[aliasID] else { throw failure(.permissionDenied) }
            _ = try await broker.bindSubscription(session: route.connection.serviceSession, grantID: alias.grantID,
                                                   requirementID: alias.requirementID, now: currentInstant())
            _ = try controlTransport(id, operation: operation)
            guard serviceSubscriptions.aliases[aliasID]?.revision == alias.revision else { throw failure(.permissionDenied) }
        }
        let reply = try ServiceControlReply(requestID: route.request.requestID, kind: route.request.kind, phase: phase, result: result)
        try reply.validate(matching: route.request)
        let bytes = try ServiceSubscriptionFrameCodec.encode(reply, profile: .v1_4)
        let receipt = RuntimeServiceSubscriptionReceipt(token: UUID(), incarnation: route.connection.incarnation,
            connectionToken: route.connection.token, sequence: route.sequence,
            kind: .control(requestID: route.request.requestID, kind: route.request.kind, phase: phase))
        guard adapter.tryHandoff(incarnation: route.connection.incarnation,
            delivery: .serviceControl(RuntimeServiceSubscriptionDelivery(receipt: receipt, payload: bytes))) == .accepted else {
            throw failure(.outcomeUnknown)
        }
        releaseDelivery(.serviceReserved(id), owner: owner, incarnation: route.connection.incarnation)
        installDelivery(.subscriptionAccepted(receipt), owner: owner, incarnation: route.connection.incarnation)
        serviceConnections.controls[id]?.receipt = receipt
    }

    /// deliverSubscriptionEvent borrows the cache only after every suspension and releases it
    /// before returning.
    private func deliverSubscriptionEvent(_ id: UUID, operation: AdmissionOperation) async throws {
        guard let alias = serviceSubscriptions.aliases[id] else { throw failure(.permissionDenied) }
        let owner = alias.connection.identity.addonID
#if DEBUG
        // Real protected workspace is already held. These scalar-only causal
        // windows precede cache borrowing; neither transfers authority or Data.
        await Self.serviceSubscriptionObserver?(.eventWorkspaceReady)
#endif
        let binding = try await broker.bindSubscription(session: alias.connection.serviceSession, grantID: alias.grantID,
                                                        requirementID: alias.requirementID, now: currentInstant())
#if DEBUG
        await Self.serviceSubscriptionObserver?(.eventBindingRead)
#endif
        try validateOperation(operation, owner: owner)
        _ = try subscriptionConnection(alias.connection)
        guard let current = serviceSubscriptions.aliases[id], current.revision == alias.revision,
              current.grantID == binding.grant.id, current.deadline > (try currentInstant()).monotonic,
              current.interestID == binding.interestID, current.sourceID == binding.sourceID,
              processes[owner]?.credits.delivery == nil, !serviceConnections.contains(alias.connection.incarnation),
              !invocationExchange.hasRoute(incarnation: alias.connection.incarnation),
              let cached = serviceCache.entries[binding.sourceID], cached.key == binding.key,
              cached.revision > current.deliveredRevision else { throw failure(.permissionDenied) }
        let event = try ServiceEvent(subscriptionID: id, token: binding.grant, response: cached.response)
        let bytes = try ServiceSubscriptionFrameCodec.encode(event, profile: .v1_4)
        let receipt = RuntimeServiceSubscriptionReceipt(token: UUID(), incarnation: alias.connection.incarnation,
            connectionToken: alias.connection.token, sequence: 0,
            kind: .event(subscriptionID: id, bindingRevision: alias.revision, cacheRevision: cached.revision))
        guard adapter.tryHandoff(incarnation: alias.connection.incarnation,
            delivery: .serviceEvent(RuntimeServiceSubscriptionDelivery(receipt: receipt, payload: bytes))) == .accepted else { throw failure(.dependencyUnavailable) }
        installDelivery(.subscriptionAccepted(receipt), owner: owner, incarnation: alias.connection.incarnation)
        serviceSubscriptions.aliases[id]?.receipt = receipt
        serviceSubscriptions.cursor[alias.connection.incarnation] = id
    }

    func receiveServiceSubscriptionReceipt(_ receipt: RuntimeServiceSubscriptionReceipt, connection: RuntimeConnection) async -> Bool {
        guard let owner = try? subscriptionConnection(connection), receipt.incarnation == connection.incarnation,
              receipt.connectionToken == connection.token,
              processes[owner]?.credits.delivery == .subscriptionAccepted(receipt) else { return false }
        switch receipt.kind {
        case .control(_, _, let phase):
            guard let route = serviceConnections.controls.values.first(where: { $0.receipt == receipt }),
                  route.connection.token == connection.token else { return false }
            releaseDelivery(.subscriptionAccepted(receipt), owner: owner, incarnation: connection.incarnation)
            if phase == .admission {
                serviceConnections.controls[route.id]?.receipt = nil
                serviceConnections.controls[route.id]?.admissionReceived = true
                installDelivery(.serviceReserved(route.id), owner: owner, incarnation: connection.incarnation)
            } else {
                // Receipt completes transport, not an indeterminate canonical
                // startup disposition. Keep the same paid row until it resolves.
                serviceConnections.controls[route.id]?.receipt = nil
                serviceConnections.controls[route.id]?.transportSettled = true
                deferredPoolOwners.insert(owner)
                serviceEventDrainRequested = true
            }
        case .sourceStart(let sourceID, let nonce):
            guard serviceSources[sourceID]?.receipt == receipt, serviceSources[sourceID]?.frame.startNonce == nonce else { return false }
            serviceSources[sourceID]?.receipt = nil
            releaseDelivery(.subscriptionAccepted(receipt), owner: owner, incarnation: connection.incarnation)
        case .event(let id, let revision, let cachedRevision):
            guard let alias = serviceSubscriptions.aliases[id], alias.receipt == receipt, alias.revision == revision else { return false }
            serviceSubscriptions.aliases[id]?.receipt = nil
            serviceSubscriptions.aliases[id]?.deliveredRevision = cachedRevision
            releaseDelivery(.subscriptionAccepted(receipt), owner: owner, incarnation: connection.incarnation)
        }
        await drainIfNoActiveAdmission()
        return true
    }

    private func settleControl(_ id: UUID) {
        guard var route = serviceConnections.controls[id], !route.transportSettled else { return }
        let owner = route.connection.identity.addonID
        if let receipt = route.receipt { releaseDelivery(.subscriptionAccepted(receipt), owner: owner, incarnation: route.connection.incarnation) }
        else { releaseDelivery(.serviceReserved(id), owner: owner, incarnation: route.connection.incarnation) }
        (adapter as? any AddonRuntimeServiceAdapter)?.settleServiceExchange(RuntimeServiceSettlement(routeID: id,
            incarnation: route.connection.incarnation, connectionToken: route.connection.token, sequence: route.sequence))
        route.receipt = nil
        route.transportSettled = true
        serviceConnections.controls[id] = route
        deferredPoolOwners.insert(owner)
        serviceEventDrainRequested = true
    }

    private func disposeParked(_ parked: RuntimeServiceConnectionState.Parked) {
        let owner = parked.connection.identity.addonID
        if processes[owner]?.incarnation == parked.connection.incarnation {
            let previousSequence = processes[owner]?.lastServiceSequence ?? 0
            processes[owner]?.lastServiceSequence = max(previousSequence, parked.ingress.sequence)
        }
        if let claim = processes[owner]?.credits.ingress, claim.id == parked.id {
            disposeIngress(claim, owner: owner, incarnation: parked.connection.incarnation, disposition: .reject)
        }
        (adapter as? any AddonRuntimeServiceAdapter)?.rejectServiceIngress(parked.ingress, incarnation: parked.connection.incarnation)
        (adapter as? any AddonRuntimeServiceAdapter)?.settleServiceExchange(RuntimeServiceSettlement(routeID: parked.id,
            incarnation: parked.connection.incarnation, connectionToken: parked.connection.token, sequence: parked.ingress.sequence))
        serviceConnections.parked.removeValue(forKey: parked.connection.incarnation)
        deferredPoolOwners.insert(owner)
    }

    private func parkServiceIngressIfNeeded(_ ingress: RuntimeServiceIngressHandle, connection: RuntimeConnection,
                                           operation: AdmissionOperation) async throws -> UUID? {
        let owner = connection.identity.addonID
        guard case .subscriptionAccepted(let receipt)? = processes[owner]?.credits.delivery,
              case .event = receipt.kind else { return nil }
        _ = try subscriptionConnection(connection)
        guard processes[owner]?.credits.ingress == nil, !serviceConnections.contains(connection.incarnation),
              !invocationExchange.hasRoute(incarnation: connection.incarnation),
              (serviceConnections.count + invocationExchange.count) < 32,
              ingress.sequence > (processes[owner]?.lastServiceSequence ?? UInt64.max) else { throw failure(.resourceDenied) }
        pendingServiceMetadataBytes = RuntimeServiceAcquisitionState.bytes
        defer { pendingServiceMetadataBytes = 0 }
        try await growPool(owner: owner, by: pendingServiceMetadataBytes)
        try validateOperation(operation, owner: owner)
        _ = try subscriptionConnection(connection)
        guard processes[owner]?.credits.delivery == .subscriptionAccepted(receipt) else { return nil }
        guard processes[owner]?.credits.ingress == nil else { throw failure(.resourceDenied) }
        let parked = RuntimeServiceConnectionState.Parked(id: UUID(), connection: connection, ingress: ingress,
                                                        deadline: try currentInstant().monotonic + .seconds(30))
        serviceConnections.parked[connection.incarnation] = parked
        processes[owner]?.credits.ingress = IngressClaim(id: parked.id, handle: .service(token: ingress.token,
            encodedBytes: ingress.encodedBytes, sequence: ingress.sequence, kind: ingress.kind))
        return parked.id
    }

    /// receiveServiceCompletion accepts a response only for current sent work.
    func receiveServiceCompletion(
        _ workID : UUID,
        connection: RuntimeConnection,
        response : ServiceResponse
    ) async throws -> ServiceCompletionResult {
        guard let execution = serviceExecutions[workID], execution.isHandedOff,
              execution.provider == connection.identity.addonID,
              execution.providerIncarnation == connection.incarnation else {
            throw failure(.sessionRevoked)
        }
        _ = try connectedOwner(connection)
        try response.validate()
        let receivedAt = try currentInstant()
        guard !inFlightServiceCompletionIDs.contains(workID),
              serviceGrants[execution.grantID]?.owner == execution.consumer,
              let consumerProcess = processes[execution.consumer],
              case .connected(let consumerConnection) = consumerProcess.phase,
              consumerConnection.token == execution.connectionToken,
              response.contractID == execution.work.invocation.contractID,
              response.operation == execution.work.invocation.operation,
              receivedAt.monotonic < execution.work.effectiveDeadline else {
            throw failure(.sessionRevoked)
        }
        deferredServiceCompletions[workID] = DeferredServiceCompletion(
            response : response,
            requestID: execution.work.invocation.requestID,
            grantID  : execution.grantID,
            consumer : execution.consumer,
            connectionToken: execution.connectionToken,
            providerIncarnation: execution.providerIncarnation,
            authorityRevision: authorityRevision,
            receivedAt: receivedAt,
            preparedCompletion: nil,
            ingressClaim: nil,
            provider: execution.provider
        )
        inFlightServiceCompletionIDs.insert(workID)
        releaseDelivery(
            .service(workID: workID),
            owner      : execution.provider,
            incarnation: execution.providerIncarnation
        )
        let outcome = await drainIfNoActiveAdmission(
            reportingServiceCompletion: workID
        )
        switch outcome {
        case .accepted:
            return .accepted(response)
        case .refused:
            throw failure(.sessionRevoked)
        case nil:
            break
        }
        guard deferredServiceCompletions[workID] != nil else {
            throw failure(.sessionRevoked)
        }
        return .pending
    }

    /// serviceOutcome recovers canonical broker history only through a current runtime grant.
    func serviceOutcome(
        connection: RuntimeConnection,
        grantID   : UUID,
        requestID : UUID
    ) async throws -> ServiceRequestOutcome? {
        let owner = try connectedOwner(connection)
        let operation = authorityRevision
        guard let grant = serviceGrants[grantID], grant.owner == owner else {
            throw failure(.permissionDenied)
        }
        if deferredServiceCompletions.values.contains(where: {
            $0.grantID == grantID && $0.requestID == requestID
        }) || serviceExecutions.contains(where: { id, execution in
            inFlightServiceCompletionIDs.contains(id)
                && execution.grantID == grantID
                && execution.work.invocation.requestID == requestID
        }) {
            throw failure(.resourceDenied)
        }
        let outcome = try await broker.requestOutcome(
            session  : connection.serviceSession,
            grantID  : grantID,
            requestID: requestID,
            now      : currentInstant()
        )
        try validateOperation(operation, owner: owner)
        _ = try connectedOwner(connection)
        guard serviceGrants[grantID]?.owner == owner,
              try currentInstant().monotonic < grant.deadline else {
            throw failure(.permissionDenied)
        }
        return outcome
    }

    /// closeConnection revokes only the current authenticated incarnation, preserving durable
    /// publications and their pins. Stop drains adapter staging; actual exit alone releases
    /// physical provider and handed-off work reservations. Obsolete closes are harmless.
    func closeConnection(_ supplied: RuntimeConnection) async {
        let owner = supplied.identity.addonID
        // Lifecycle authentication must still work after a service requested stop or archive
        // quiescence closed ordinary traffic. Neither event closes the retained sessions.
        guard let process = processes[owner], !process.connectionClosed,
              process.incarnation == supplied.incarnation,
              let current = connection(from: process.phase),
              current.token == supplied.token,
              current.identity == supplied.identity,
              current.digest == supplied.digest,
              current.authorityRevision == supplied.authorityRevision,
              catalog[owner]?.verifiedIdentity == current.identity,
              catalog[owner]?.digest == current.digest else { return }
        processes[owner]?.connectionClosed = true
        // Use retained component handles rather than fields from the supplied value. The
        // authenticated scalar identity must not confer authority over another session.
        advanceAuthority()
        publicationState.closeConnection(current.publicationConnection)
        assetState.revokeImports(connectionToken: current.token)
        _ = dispatcher.connectionLost(
            owner     : owner,
            generation: current.publicationConnection.generation
        )
        requestStopOnce(
            owner : owner,
            reason: .connectionLost
        )
        deferredConnectionCloses[current.incarnation] = current
        deferBrokerReconciliation(.connectionLost)
        deferredPoolOwners.insert(owner)
        await drainIfNoActiveAdmission()
    }

    /// disable advances authority before any broker suspension and requests one physical stop.
    func disable(owner: AddonID) async {
        guard catalog[owner] != nil, !disabledOwners.contains(owner) else { return }
        disabledOwners.insert(owner)
        healthStore.cancel(owner: owner)
        pendingCrashDecisions.removeValue(forKey: owner)
        processes[owner]?.pendingCrashSession = nil
        delegatedHealthSessions.removeValue(forKey: owner)
        advanceAuthority()
        _ = dispatcher.disable(owner: owner)
        publicationState.remove(owner: owner)
        assetState.removeOwner(owner)
        requestStopOnce(
            owner : owner,
            reason: .disabled
        )
#if DEBUG
        Self.cpuDisableCheckpoint?(owner)
#endif
        if let identity = catalog[owner]?.verifiedIdentity {
            deferredDisabledProviders[owner] = identity
        }
        deferBrokerReconciliation(.disabled)
        deferInactivePublicationReservations(owner: owner)
        servicePermissions = servicePermissions.filter {
            $0.value.owner != owner && $0.value.provider.addonID != owner
        }
        serviceGrants = serviceGrants.filter {
            $0.value.owner != owner && $0.value.provider.addonID != owner
        }
        for id in Array(serviceExecutions.keys) {
            guard let execution = serviceExecutions[id],
                  execution.consumer == owner || execution.provider == owner else { continue }
            if execution.isHandedOff {
                requestStopOnce(
                    owner : execution.provider,
                    reason: .disabled
                )
            } else {
                deferServiceExecutionRelease(id)
            }
        }
        for key in Array(actionResources.keys) where key.owner == owner {
            guard actionResources[key]?.delivery == nil,
                  let resources = actionResources.removeValue(forKey: key) else { continue }
            if let job = resources.job {
                deferRelease(
                    job,
                    owner: owner
                )
            }
            deferRelease(
                resources.command,
                owner: owner
            )
        }
        deferredPoolOwners.insert(owner)
        await drainIfNoActiveAdmission()
    }

    /// enable reopens host eligibility only after the disabled incarnation actually exits.
    func enable(owner: AddonID) throws {
        guard !stopped, archiveQuiescence == nil, !admissionInProgress, !cleanupInProgress,
              catalog[owner] != nil, disabledOwners.contains(owner),
              processes[owner] == nil else { throw failure(.sessionRevoked) }
        advanceAuthority()
        guard !stopped else { throw failure(.resourceDenied) }
        disabledOwners.remove(owner)
    }

    /// observeExit releases only the exact incarnation's physical and uncertain work.
    func observeExit(
        _ incarnation: RuntimeIncarnation,
        cause        : PhysicalExitCause = .unclassified
    ) async {
        guard let pair = processes.first(where: { $0.value.incarnation == incarnation }) else { return }
        let owner = pair.key
        let crashSession = cause == .unexpected
            ? pair.value.healthSession ?? pair.value.pendingCrashSession
            : nil
        revokeMetricProcess(
            owner               : owner,
            process             : pair.value,
            preserveCrashSession: crashSession != nil
        )
        if let crashSession {
            pendingCrashDecisions[owner] = PendingCrashDecision(
                incarnation: incarnation,
                session    : crashSession,
                identity   : pair.value.identity,
                digest     : pair.value.digest
            )
        }
        invalidateSubscriptionConnection(incarnation)
        invocationExchange.invalidate(owner: owner)
        var process = processes[owner] ?? pair.value
        advanceAuthority()
        process.assembler.invalidate()
        process.assetTransfer = nil
        adapter.processDidExit(incarnation: incarnation)
        processes.removeValue(forKey: owner)
        launches.removeValue(forKey: process.launchID)
        let exitedConnection = connection(from: process.phase)
        if let connection = exitedConnection {
            publicationState.closeConnection(connection.publicationConnection)
            assetState.revokeImports(connectionToken: connection.token)
        }
        deferredExits[incarnation] = DeferredExit(
            owner     : owner,
            process   : process,
            connection: exitedConnection
        )
        deferBrokerReconciliation(.connectionLost)
        serviceGrants = serviceGrants.filter {
            $0.value.provider != process.identity
        }
        for key in Array(actionResources.keys) where key.owner == owner {
            guard let retained = actionResources[key],
                  let delivery = retained.delivery,
                  delivery.generation == connection(from: process.phase)?.publicationConnection.generation,
                  let resources = actionResources.removeValue(forKey: key) else { continue }
            if (try? dispatcher.observeExit(
                delivery,
                owner     : owner,
                generation: delivery.generation
               )) == true {}
            if let job = resources.job {
                deferRelease(
                    job,
                    owner: owner
                )
            }
            deferRelease(
                resources.command,
                owner: owner
            )
        }
        for id in Array(serviceExecutions.keys) {
            guard let execution = serviceExecutions[id], execution.provider == owner,
                  execution.providerIncarnation == incarnation else { continue }
            deferServiceExecutionRelease(id)
        }
        for sourceID in Array(sourceExecutions.keys) {
            guard let execution = sourceExecutions[sourceID], execution.provider == owner,
                  execution.providerIncarnation == incarnation else { continue }
            sourceExecutions.removeValue(forKey: sourceID)
            deferRelease(
                execution.job,
                owner: owner
            )
        }
        deferRelease(
            process.providerReservation,
            owner: owner
        )
        deferredPoolOwners.insert(owner)
        await drainIfNoActiveAdmission()
    }

    /// serviceDeadlines drains wall, action, broker and cold-start expiry from explicit events.
    func serviceDeadlines() async throws -> Duration? {
        let instant = try currentInstant()
        // Canonical lookup becomes nil at the same finite expiry boundary used by expire.
        // Timeline projection alone still has retained content and is not an archive change.
        for (id, assignment) in assignments {
            if let record = publicationState.recordAccounting(id: id),
                record.kind != .notice, record.contentBytes > 0,
                publicationState.publication(
                    id: id,
                    at: instant.wall
                ) == nil
            {
                markArchiveChange(owner: assignment.owner)
            }
        }
        publicationState.expire(at: instant.wall)
        assetState.reconcile(
            publications: publicationState,
            at          : instant.wall
        )
        // A canonical publication end or expiry revokes the exact bound transfer immediately,
        // without waiting for process exit or the 30-second assembler deadline.
        reconcileAssetTransfers(at: instant)
        for owner in Array(ownerPools.keys) {
            deferInactivePublicationReservations(owner: owner)
        }
        let actionStops = dispatcher.expire(at: instant.monotonic)
        for delivery in actionStops {
            requestStopOnce(
                owner : delivery.ticket.request.publicationID.addonID,
                reason: .deadlineExceeded
            )
        }
        for (owner, process) in processes where process.coldStartDeadline <= instant.monotonic {
            if case .pending = process.phase {
                requestStopOnce(
                    owner : owner,
                    reason: .deadlineExceeded
                )
            }
        }
        // The nonrenewable 30-second assembler deadline is serviced from the one aggregate key.
        for (owner, process) in processes {
            guard let deadline = process.assembler.nextDeadline, deadline <= instant.monotonic else { continue }
            do {
                try await process.assembler.expire()
            } catch {
                deferredAssetAssemblers[process.incarnation] = process.assembler
            }
            if processes[owner]?.assembler === process.assembler {
                processes[owner]?.assetTransfer = nil
            }
        }
        for execution in serviceExecutions.values where execution.isHandedOff
            && execution.work.effectiveDeadline <= instant.monotonic {
            requestStopOnce(
                owner : execution.provider,
                reason: .deadlineExceeded
            )
        }
        for execution in sourceExecutions.values where execution.isHandedOff
            && execution.deadline <= instant.monotonic {
            requestStopOnce(
                owner : execution.provider,
                reason: .deadlineExceeded
            )
        }
        if deferredBrokerExpiry.map({ $0.monotonic < instant.monotonic }) ?? true {
            deferredBrokerExpiry = instant
        }
        deferBrokerReconciliation(.deadlineExceeded)
        for owner in Array(ownerPools.keys) {
            deferTerminalActionResources(owner: owner)
            pruneAssignments(owner: owner)
            deferredPoolOwners.insert(owner)
        }
        await drainIfNoActiveAdmission()
        if pendingMetricWake != nil {
            _ = try await servicePendingMetricWake()
        }
        if pendingMetricWake == nil {
            _ = try await sampleResources(reason: .periodic)
        }
        // Retry tickets share the existing action/cold-start deadline lane.
        // Each pass observes only the bounded canonical projection; a refused
        // pre-handoff attempt remains pending for the next bounded wake.
        for retry in healthStore.pendingRetryTickets {
            let now = try currentInstant()
            guard retry.deadline <= now.monotonic else { break }
            let owner = retry.version.verifiedIdentity.addonID
            guard activeOperation == nil, !cleanupInProgress,
                  pendingCrashDecisions[owner] == nil,
                  processes[owner] == nil,
                  !stopped, !disabledOwners.contains(owner),
                  let installed = catalog[owner], installed.enabled,
                  installed.verifiedIdentity == retry.version.verifiedIdentity,
                  (try? healthVersion(for: installed)) == retry.version else { continue }
            _ = try? await requestLaunch(owner: owner, retry: retry)
        }
        return try await nextDelay(at: instant)
    }

    /// nextDelay refreshes five stable aggregate keys and installs no timer.
    func nextDelay(at instant: RuntimeInstant) async throws -> Duration? {
        guard !stopped,
              let owner = catalog.keys.sorted(by: { $0.rawValue < $1.rawValue }).first(where: {
                  !disabledOwners.contains($0)
              }) else {
            clearAggregateDeadlines()
            return nil
        }
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        do {
            let canonicalDeadline = await serviceDecisionAccess.nextDeadline()
            let brokerDeadline = ([canonicalDeadline].compactMap { $0 }
                + serviceConnections.controls.values.map(\.deadline)
                + serviceConnections.parked.values.map(\.deadline)
                + sourceExecutions.values.map(\.deadline)).min()
            let metricDeadline = await processMetrics.nextDeadline
            try validateOperation(operation, owner: owner)
            let fresh = try currentInstant()
            migrateAggregateDeadlines(to: owner)
            try refreshDeadline(
                publicationDeadlineKey,
                owner   : owner,
                deadline: publicationState.nextDeadline(after: fresh.wall).map(DeadlineQueue.Deadline.wall)
            )
            let coldStart = processes.values.compactMap { process -> Duration? in
                guard !process.stopRequested, case .pending = process.phase else { return nil }
                return process.coldStartDeadline
            }.min()
            let retryDeadline: Duration?
            if let deadline = healthStore.nextDeadline {
                retryDeadline = deadline <= fresh.monotonic
                    ? try metricRetryDeadline(after: fresh.monotonic)
                    : deadline
            } else {
                retryDeadline = nil
            }
            let action = [dispatcher.nextDeadline, coldStart, retryDeadline].compactMap { $0 }.min()
            try refreshDeadline(
                actionDeadlineKey,
                owner   : owner,
                deadline: action.map(DeadlineQueue.Deadline.monotonic)
            )
            let asset = processes.values.compactMap { $0.assembler.nextDeadline }.min()
            try refreshDeadline(
                assetDeadlineKey,
                owner   : owner,
                deadline: asset.map(DeadlineQueue.Deadline.monotonic)
            )
            try refreshDeadline(
                serviceDeadlineKey,
                owner   : owner,
                deadline: brokerDeadline.map(DeadlineQueue.Deadline.monotonic)
            )
            let metricsBusy = resourceOperationInProgress || cleanupInProgress
                || !pendingMetricDetaches.isEmpty || pendingMetricWake != nil
            let metricRearm: Duration?
            if metricsBusy,
               metricDeadline.map({ $0 <= fresh.monotonic }) ?? (pendingMetricWake != nil) {
                metricRearm = try metricRetryDeadline(after: fresh.monotonic)
            } else {
                metricRearm = metricDeadline
            }
            try refreshDeadline(
                metricDeadlineKey,
                owner   : owner,
                deadline: metricRearm.map(DeadlineQueue.Deadline.monotonic)
            )
            let delay = try deadlines.nextDelay(at: fresh)
            await finishAdmissionAndDrain(operation)
            return delay
        } catch {
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// ArchiveQuiescence is one host-issued monotonic window bound to this runtime nonce.
    struct ArchiveQuiescence: Equatable, Sendable {
        fileprivate let nonce: UUID
        fileprivate let deadline: Duration
    }

    /// StopProgress reports logical cleanup and canonical process records, never physical exit.
    struct StopProgress: Equatable, Sendable {
        let cleanupPending      : Bool
        let retainedProcessCount: Int
    }

    /// ShutdownArchiveFailure returns bounded causes without platform error payloads.
    enum ShutdownArchiveFailure: Error, Equatable, Sendable {
        case runtime(AddonFailure.Code)
        case archive(SwiftDataArchiveFailure)
        case cancelled
        case unavailable
    }

    /// ShutdownArchiveAttempt distinguishes refusal from accepted work and preserves known commits.
    enum ShutdownArchiveAttempt: Equatable, Sendable {
        case busy
        case skipped
        case windowClosed
        case refused(ShutdownArchiveFailure)
        case failed(ShutdownArchiveFailure)
        case committed(SwiftDataArchiveSaveOutcome)
    }

    /// beginArchiveQuiescence revokes normal authority synchronously while retaining private checkpoint state.
    /// The supplied monotonic window cannot be extended or reused after terminal stop.
    func beginArchiveQuiescence(until deadline: Duration) throws -> ArchiveQuiescence {
        try Task.checkCancellation()
        let instant = try currentInstant()
        guard !stopped, deadline >= .zero else { throw failure(.sessionRevoked) }
        if let existing = archiveQuiescence {
            guard existing.deadline == deadline else { throw failure(.permissionDenied) }
            return existing
        }
        guard deadline > instant.monotonic else { throw failure(.deadlineExceeded) }
        let ticket = ArchiveQuiescence(
            nonce   : UUID(),
            deadline: deadline
        )
        archiveQuiescence = ticket
        advanceAuthority()
        guard !stopped else { throw failure(.resourceDenied) }
        let actionStops = dispatcher.stop()
        servicePermissions.removeAll()
        serviceGrants.removeAll()
        deferredBrokerShutdown = true
        deferBrokerReconciliation(.stopped)
        for owner in ownerPools.keys {
            if !actionStops.contains(where: { $0.ticket.request.publicationID.addonID == owner }) {
                deferTerminalActionResources(owner: owner)
            }
            deferredPoolOwners.insert(owner)
        }
        return ticket
    }

    /// validateQuiescence distinguishes a foreign capability from a closed accepted window.
    private func validateQuiescence(_ ticket: ArchiveQuiescence) throws {
        guard archiveQuiescence == ticket else { throw failure(.permissionDenied) }
        guard !stopped, try currentInstant().monotonic < ticket.deadline else {
            throw ArchiveWindowClosed.closed
        }
    }

    /// saveQuiescingArchive reports actual admission acceptance without inferring it from an error code.
    /// The deadline is checked through runtime handoff; an accepted backend save may finish afterward.
    func saveQuiescingArchive(
        owner     : AddonID,
        to archive: SwiftDataArchive,
        quiescence: ArchiveQuiescence
    ) async -> ShutdownArchiveAttempt {
        var accepted: AdmissionOperation?
        do {
            try Task.checkCancellation()
            try validateQuiescence(quiescence)
            guard !disabledOwners.contains(owner), let installedOwner = catalog[owner],
                installedOwner.enabled,
                resolution?.acceptedAddons.contains(owner) == true
            else { return .skipped }
            let purpose   = AdmissionPurpose.archiveQuiescence(quiescence)
            let installed = try archiveInstalled(
                owner  : owner,
                archive: archive,
                purpose: purpose
            )
            guard let progress = ownerPools[owner]?.archiveProgress, progress.current != progress.saved else {
                return .skipped
            }
            guard
                let operation = try await tryBeginAdmission(
                    owner  : owner,
                    purpose: purpose
                )
            else { return .busy }
            accepted = operation
            try validateArchiveOperation(
                operation,
                installed: installed,
                archive  : archive,
                features : []
            )
            guard let current = ownerPools[owner]?.archiveProgress, current.current != current.saved else {
                await finishAdmissionAndDrain(operation)
                return .skipped
            }
            ownerPools[owner]?.archiveProgress.attempted = current.current
            _ = try await archive.start()
            try validateArchiveOperation(
                operation,
                installed: installed,
                archive  : archive,
                features : []
            )
            let outcome = try await saveAdmittedArchive(
                operation,
                installed: installed,
                archive  : archive
            )
            await finishAdmissionAndDrain(operation)
            return .committed(outcome)
        } catch {
            // Capture the bounded result at the failing boundary before cleanup can change clock/authority.
            let result: ShutdownArchiveAttempt
            if error is ArchiveWindowClosed {
                result = .windowClosed
            } else {
                let bounded = Self.shutdownArchiveFailure(error)
                result = accepted == nil ? .refused(bounded) : .failed(bounded)
            }
            if let accepted { await finishAdmissionAndDrain(accepted) }
            return result
        }
    }

    /// shutdownArchiveFailure drops platform error payloads before returning from the actor.
    private static func shutdownArchiveFailure(_ error: any Error) -> ShutdownArchiveFailure {
        if let error = error as? AddonFailure { return .runtime(error.code) }
        if let error = error as? SwiftDataArchiveFailure { return .archive(error) }
        if error is CancellationError { return .cancelled }
        return .unavailable
    }

    /// requestStop revokes logical authority without awaiting backend, governor or provider cleanup.
    /// Retained process records and pending cleanup are receipts, not physical exit observations.
    func requestStop() -> StopProgress {
        guard !stopped else { return stopProgress }
        stopped = true
        for owner in catalog.keys { healthStore.cancel(owner: owner) }
        pendingCrashDecisions.removeAll(keepingCapacity: true)
        for owner in processes.keys { processes[owner]?.pendingCrashSession = nil }
        delegatedHealthSessions.removeAll(keepingCapacity: true)
        assetDecoder.close()
        assetCoordinator.close()
        advanceAuthority()
        let actionStops = dispatcher.stop()
        for owner in catalog.keys {
            publicationState.remove(owner: owner)
            assetState.removeOwner(owner)
        }
        for owner in Array(ownerPools.keys) {
            deferInactivePublicationReservations(owner: owner)
        }
        let ownersWithSentWork = Set(actionStops.map { $0.ticket.request.publicationID.addonID })
        for owner in Array(processes.keys) {
            requestStopOnce(
                owner : owner,
                reason: .stopped
            )
        }
        deferredBrokerShutdown = true
        deferBrokerReconciliation(.stopped)
        servicePermissions.removeAll()
        serviceGrants.removeAll()
        for owner in Array(ownerPools.keys) {
            if !ownersWithSentWork.contains(owner) {
                deferTerminalActionResources(owner: owner)
            }
            deferredPoolOwners.insert(owner)
        }
        return stopProgress
    }

    private var stopProgress: StopProgress {
        StopProgress(
            cleanupPending      : hasDeferredCleanup || cleanupInProgress || activeOperation != nil,
            retainedProcessCount: processes.count
        )
    }

    /// stop retries deferred cleanup even after an earlier synchronous stop request.
    func stop() async {
        _ = requestStop()
        await drainIfNoActiveAdmission()
    }

    func snapshot(at date: Date) -> Snapshot {
        Snapshot(
            publications: stopped || archiveQuiescence != nil
                ? []
                : disabledOwners.isEmpty
                    ? publicationState.snapshot(at: date)
                    : publicationState.snapshot(at: date).filter {
                        !disabledOwners.contains($0.id.addonID)
                    },
            actionCount  : dispatcher.historyCount,
            providerCount: processes.count,
            isStopped    : stopped
        )
    }

    /// ArchiveRestorationResult reports only committed scalar effects, never retained archive data.
    enum ArchiveRestorationResult: Equatable, Sendable {
        case empty
        case restored(
            revision: UInt64,
            active  : Int,
            terminal: Int
        )
    }

    /// ArchiveRestorationCandidate holds inert remapped inputs inside the admitted M/Q scopes.
    private struct ArchiveRestorationCandidate: Sendable {
        let records    : [PublicationArchiveRecord]
        let assignments: [PublicationID: Assignment]
        let aliases    : [PublicationID: [String: Data]]
        let features   : [String]
        let date       : Date
        let growth     : Int
    }

    /// restoreArchive activates one complete generation before this owner's first publication lifecycle.
    /// All scoped payloads and failed proposals disappear before pooled refunds. A completed commit
    /// remains successful even if later cleanup observes cancellation or a lifecycle transition.
    func restoreArchive(
        owner       : AddonID,
        from archive: SwiftDataArchive
    ) async throws -> ArchiveRestorationResult {
        let installed = try archiveInstalled(
            owner  : owner,
            archive: archive
        )
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        do {
            try validateArchiveRestoration(
                operation,
                installed: installed,
                archive  : archive,
                features : []
            )
            let result = try await archive.withGeneration { generation in
                try await self.validateArchiveRestoration(
                    operation,
                    installed: installed,
                    archive  : archive,
                    features : []
                )
                guard let generation else { return ArchiveRestorationResult.empty }
                guard generation.verifiedDigest == installed.digest else {
                    throw AddonFailure(
                        code  : .permissionDenied,
                        reason: "Archived generation does not match the current executable."
                    )
                }
                return try await self.restoreArchiveGeneration(
                    generation,
                    operation: operation,
                    installed: installed,
                    archive  : archive
                )
            }
            pendingArchiveMetadataBytes = 0
            await shrinkPoolToCurrent(owner: owner)
            try? await assetCoordinator.flushDisposed()
            await finishAdmissionAndDrain(operation)
            return result
        } catch {
            // Scoped helpers have returned: no failed proposal or backing borrow survives this refund.
            pendingArchiveMetadataBytes = 0
            await shrinkPoolToCurrent(owner: owner)
            try? await assetCoordinator.flushDisposed()
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// validateArchiveRestoration checks permanent startup eligibility after every suspension.
    private func validateArchiveRestoration(
        _ operation: AdmissionOperation,
        installed  : InstalledAddon,
        archive    : SwiftDataArchive,
        features   : [String]
    ) throws {
        try validateArchiveOperation(
            operation,
            installed: installed,
            archive  : archive,
            features : features
        )
        let owner = installed.manifest.id
        guard let pool = ownerPools[owner], !pool.restorationSealed,
              processes[owner] == nil else { throw failure(.sessionRevoked) }
    }

    /// restoreArchiveGeneration nests raw scalar, inspection and graph capacity in the approved order.
    /// The backend and full envelope scopes remain held until every decoded leaf and graph disappears.
    private func restoreArchiveGeneration(
        _ generation: SwiftDataArchiveGeneration,
        operation   : AdmissionOperation,
        installed   : InstalledAddon,
        archive     : SwiftDataArchive
    ) async throws -> ArchiveRestorationResult {
        try await governor.withAssetDecodeReservation(
            bytes: RuntimeArchiveEnvelope.retentionReservationBytes(),
            owner: installed.manifest.id
        ) {
            let envelope = try await self.governor.withAssetDecodeReservation(
                bytes: generation.payload.count,
                owner: installed.manifest.id
            ) {
                try RuntimeArchiveEnvelope.decode(generation.payload)
            }
            try await self.validateArchiveRestoration(
                operation,
                installed: installed,
                archive  : archive,
                features : []
            )
            guard envelope.publisher == Data(installed.verifiedIdentity.publisher.utf8),
                  envelope.addon == Data(installed.manifest.id.rawValue.utf8),
                  envelope.digest == Data(installed.digest.utf8) else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "Archive envelope does not match current verified ownership."
                )
            }
            let graphBytes = try await self.governor.withAssetDecodeReservation(
                bytes: RuntimeArchivePublicationCodec.inspectionReservationBytes(),
                owner: installed.manifest.id
            ) {
                var total = 0
                for record in envelope.records {
                    guard let json = record.publication else { continue }
                    total = try RuntimeArchiveCost.add(
                        total,
                        RuntimeArchivePublicationCodec.inspect(json).requiredBytes
                    )
                }
                return total
            }
            // The inspection graph has left scope before aggregate original/remapped graphs enter.
            return try await self.governor.withAssetDecodeReservation(
                bytes: graphBytes,
                owner: installed.manifest.id
            ) {
                try await self.prepareArchiveRestoration(
                    envelope,
                    revision : generation.revision,
                    operation: operation,
                    installed: installed,
                    archive  : archive
                )
            }
        }
    }

    /// makeArchiveRestorationCandidate remaps validated graphs and quotes persistent growth without mutation.
    /// Its one finite date classifies quoted content and is reused by the first canonical preparation.
    private func makeArchiveRestorationCandidate(
        _ envelope: RuntimeArchiveEnvelope,
        operation : AdmissionOperation,
        installed : InstalledAddon,
        archive   : SwiftDataArchive
    ) throws -> ArchiveRestorationCandidate {
        try validateArchiveRestoration(
            operation,
            installed: installed,
            archive  : archive,
            features : []
        )
        let owner = installed.manifest.id
        let date = try currentInstant().wall
        guard envelope.records.count <= 16 - assignments.values.filter({ $0.owner == owner }).count else {
            throw failure(.resourceDenied)
        }
        var records: [PublicationArchiveRecord] = []
        var proposedAssignments: [PublicationID: Assignment] = [:]
        var aliases: [PublicationID: [String: Data]] = [:]
        var partitions: [Data: UUID] = [:]
        var instances = Set<UUID>()
        var features: [String] = []
        var contentBytes = 0
        var bindingCount = 0
        var aliasCount = 0
        for record in envelope.records {
            let id = try PublicationID(
                addonID   : owner,
                instanceID: RuntimeArchiveEnvelope.uuid(record.instance),
                sessionID : RuntimeArchiveEnvelope.uuid(record.session)
            )
            guard assignments[id] == nil,
                  !assignments.keys.contains(where: { $0.addonID == owner && $0.instanceID == id.instanceID }),
                  instances.insert(id.instanceID).inserted else { throw failure(.invalidPayload) }
            let feature = try RuntimeArchiveEnvelope.text(
                record.feature,
                maximum: 128
            )
            try validateArchiveFeature(
                feature,
                installed: installed
            )
            features.append(feature)
            let partition: AssetPrivacyPartition
            if let label = record.partition {
                let fresh = partitions[label] ?? UUID()
                partitions[label] = fresh
                partition = .isolated(fresh)
            } else {
                partition = .addonOwned
            }
            var replacements: [String: String] = [:]
            var mappedAliases: [String: Data] = [:]
            for alias in record.aliases {
                let previous = try RuntimeArchiveEnvelope.text(
                    alias.name,
                    maximum: 128
                )
                let fresh = "asset-" + UUID().uuidString
                guard mappedAliases[fresh] == nil else { throw failure(.resourceDenied) }
                replacements[previous] = fresh
                mappedAliases[fresh] = alias.blob
            }
            let content: Publication?
            if let json = record.publication {
                let decoded = try RuntimeArchivePublicationCodec.decode(json)
                try RuntimeArchivePublicationCodec.validateBinding(
                    decoded,
                    record: record,
                    owner : owner
                )
                content = try RuntimeArchiveRemapping.publication(
                    decoded,
                    aliases: replacements
                )
            } else {
                content = nil
            }
            if let content, content.expiresAt > date, record.sessionDeadline > date {
                contentBytes = try RuntimeArchiveCost.add(
                    contentBytes,
                    RuntimeArchivePublicationCodec.encode(content).count
                )
                if !mappedAliases.isEmpty {
                    bindingCount += 1
                    aliasCount = try RuntimeArchiveCost.add(
                        aliasCount,
                        mappedAliases.count
                    )
                }
            }
            records.append(PublicationArchiveRecord(
                id             : id,
                revision       : record.revision,
                kind           : record.kind,
                sessionDeadline: record.sessionDeadline,
                publication    : content
            ))
            aliases[id] = mappedAliases
            proposedAssignments[id] = Assignment(
                owner                : owner,
                publisher            : installed.verifiedIdentity.publisher,
                digest               : installed.digest,
                featureID            : feature,
                assetPrivacyPartition: partition,
                eligibility          : .available,
                authorityRevision    : authorityRevision,
                assignmentToken      : UUID(),
                hasPublished         : true
            )
        }
        var growth = try publicationState.restorationMetadataBytes(
            recordCount: records.count,
            identity   : installed.verifiedIdentity
        )
        growth = try RuntimeArchiveCost.add(
            growth,
            contentBytes
        )
        growth = try RuntimeArchiveCost.add(
            growth,
            assetState.restorationMetadataBytes(
                bindingCount: bindingCount,
                aliasCount  : aliasCount
            )
        )
        growth = try RuntimeArchiveCost.add(
            growth,
            RuntimeArchiveCost.multiply(
                records.count,
                Self.assignmentBytes
            )
        )
        return ArchiveRestorationCandidate(
            records    : records,
            assignments: proposedAssignments,
            aliases    : aliases,
            features   : features,
            date       : date,
            growth     : growth
        )
    }

    /// prepareArchiveRestoration prepays the common owner pool before canonical proposal allocation.
    private func prepareArchiveRestoration(
        _ envelope: RuntimeArchiveEnvelope,
        revision  : UInt64,
        operation : AdmissionOperation,
        installed : InstalledAddon,
        archive   : SwiftDataArchive
    ) async throws -> ArchiveRestorationResult {
        let candidate = try makeArchiveRestorationCandidate(
            envelope,
            operation: operation,
            installed: installed,
            archive  : archive
        )
        try await growPool(
            owner: installed.manifest.id,
            by   : candidate.growth
        )
        pendingArchiveMetadataBytes = candidate.growth
        try validateArchiveRestoration(
            operation,
            installed: installed,
            archive  : archive,
            features : candidate.features
        )
        let publications = try publicationState.prepareRestoration(
            candidate.records,
            identity: installed.verifiedIdentity,
            at      : candidate.date
        )
        var families: [PublicationID: ResourceReservation] = [:]
        do {
            for (id, kind) in publications.newFamilies {
                let reservation = try await resourceAccess.admit(
                    .publication(kind),
                    owner: installed.manifest.id
                )
                families[id] = reservation
                try validateArchiveRestoration(
                    operation,
                    installed: installed,
                    archive  : archive,
                    features : candidate.features
                )
            }
            return try await createArchiveRestorationAssets(
                envelope,
                candidate   : candidate,
                publications: publications,
                families    : families,
                revision    : revision,
                operation   : operation,
                installed   : installed,
                archive     : archive
            )
        } catch {
            for reservation in families.values {
                deferRelease(
                    reservation,
                    owner: installed.manifest.id
                )
            }
            throw error
        }
    }

    /// createArchiveRestorationAssets creates only blobs reached by the prepared live publications.
    /// Each returned backing owns its existing independent actual-lifetime reservation.
    private func createArchiveRestorationAssets(
        _ envelope  : RuntimeArchiveEnvelope,
        candidate   : ArchiveRestorationCandidate,
        publications: PublicationState.PreparedRestoration,
        families    : [PublicationID: ResourceReservation],
        revision    : UInt64,
        operation   : AdmissionOperation,
        installed   : InstalledAddon,
        archive     : SwiftDataArchive
    ) async throws -> ArchiveRestorationResult {
        var needed = Set<Data>()
        publications.forEachRestoredPublication { publication in
            for blob in candidate.aliases[publication.id]?.values ?? [:].values {
                needed.insert(blob)
            }
        }
        var backings: [Data: AssetRasterBacking] = [:]
        for blob in envelope.blobs where needed.contains(blob.id) {
            let backing = try await assetCoordinator.create(
                pixels: blob.pixels,
                width : blob.width,
                height: blob.height,
                owner : installed.manifest.id
            )
            backings[blob.id] = backing
            try validateArchiveRestoration(
                operation,
                installed: installed,
                archive  : archive,
                features : candidate.features
            )
        }
        if hasDeferredCleanup {
            await drainDeferredCleanup()
            try validateArchiveRestoration(
                operation,
                installed: installed,
                archive  : archive,
                features : candidate.features
            )
        }
        var inputs: [PublicationID: [String: AssetRasterBacking]] = [:]
        try publications.forEachRestoredPublication { publication in
            var pins: [String: AssetRasterBacking] = [:]
            for (alias, blob) in candidate.aliases[publication.id] ?? [:] {
                guard let backing = backings[blob] else { throw failure(.invalidPayload) }
                pins[alias] = backing
            }
            if !pins.isEmpty { inputs[publication.id] = pins }
        }
        let assets = try assetState.prepareRestoration(
            publications,
            backings: inputs
        )
        return try commitArchiveRestoration(
            candidate,
            publications: publications,
            assets      : assets,
            families    : families,
            revision    : revision,
            operation   : operation,
            installed   : installed,
            archive     : archive
        )
    }

    /// commitArchiveRestoration validates everything before transferring any canonical ownership.
    /// There is no suspension or fallible operation after the first assignment is installed.
    private func commitArchiveRestoration(
        _ candidate : ArchiveRestorationCandidate,
        publications: PublicationState.PreparedRestoration,
        assets      : AssetState.PreparedOutput,
        families    : [PublicationID: ResourceReservation],
        revision    : UInt64,
        operation   : AdmissionOperation,
        installed   : InstalledAddon,
        archive     : SwiftDataArchive
    ) throws -> ArchiveRestorationResult {
        try validateArchiveRestoration(
            operation,
            installed: installed,
            archive  : archive,
            features : candidate.features
        )
        try publicationState.validatePreparedRestoration(
            publications,
            at: currentInstant().wall
        )
        try assetState.validatePrepared(assets)
        let owner = installed.manifest.id
        guard candidate.assignments.count <= 16 - assignments.values.filter({ $0.owner == owner }).count,
              families.count == publications.newFamilies.count,
              families.allSatisfy({ id, reservation in
                publications.newFamilies[id] != nil && publicationReservations[id] == nil
                    && reservation.owner == owner
              }),
              candidate.assignments.keys.allSatisfy({ id in
                assignments[id] == nil
                    && !assignments.keys.contains(where: { $0.addonID == owner && $0.instanceID == id.instanceID })
              }) else { throw failure(.sessionRevoked) }
        let growth = try RuntimeArchiveCost.add(
            RuntimeArchiveCost.multiply(
                candidate.assignments.count,
                Self.assignmentBytes
            ),
            RuntimeArchiveCost.add(
                publications.additionalBytes,
                assets.requiredGrowth
            )
        )
        guard growth <= pendingArchiveMetadataBytes,
              let pool = ownerPools[owner], pool.reservedBytes >= requiredBytes(owner: owner) else {
            throw failure(.resourceDenied)
        }
        let result = ArchiveRestorationResult.restored(
            revision: revision,
            active  : families.count,
            terminal: candidate.records.count - families.count
        )
        for (id, assignment) in candidate.assignments { assignments[id] = assignment }
        publicationState.commitPreparedRestoration(publications)
        assetState.commitPrepared(assets)
        for (id, reservation) in families { publicationReservations[id] = reservation }
        ownerPools[owner]?.restorationSealed = true
        pendingArchiveMetadataBytes = 0
        return result
    }

    /// ArchiveRasterKey deduplicates only canonical backing identity within one host privacy partition.
    private struct ArchiveRasterKey: Hashable, Sendable {
        let backing  : ObjectIdentifier
        let partition: AssetPrivacyPartition
    }

    /// ArchiveRaster holds an admitted native borrow and inert serialization metadata, never a graph.
    private struct ArchiveRaster: Sendable {
        let id       : Data
        let partition: Data?
        let backing  : AssetRasterBacking
    }

    /// ArchiveCapture owns bounded JSON leaves and raster borrows after synchronous canonical capture.
    private struct ArchiveCapture: Sendable {
        let publisher     : Data
        let addon         : Data
        let digestBytes   : Data
        let records       : [RuntimeArchiveEnvelope.Record]
        let rasters       : [ArchiveRaster]
        let features      : [String]
        let capturedChange: UUID?
    }

    /// ArchivePayload transfers only final encoded bytes and bounded provenance into prepaid output capacity.
    private struct ArchivePayload: Sendable {
        let bytes         : Data
        let features      : [String]
        let capturedChange: UUID?
    }

    /// ArchiveFlushState is a bounded selection hint, never admission or a stored retry payload.
    enum ArchiveFlushState: Equatable, Sendable {
        case unavailable
        case clean
        case pending
        case busy
        case retryRequired
    }

    /// archiveFlushState reports current verified-owner progress without allocating a pending list.
    func archiveFlushState(identity: VerifiedAddonIdentity) -> ArchiveFlushState {
        let owner = identity.addonID
        guard !stopped, archiveQuiescence == nil, !disabledOwners.contains(owner),
            let installed = catalog[owner], installed.enabled,
            installed.verifiedIdentity == identity,
            resolution?.acceptedAddons.contains(owner) == true,
            let progress = ownerPools[owner]?.archiveProgress
        else { return .unavailable }
        guard progress.current != progress.saved else { return .clean }
        if activeOperation != nil || admissionInProgress || cleanupInProgress { return .busy }
        return progress.current == progress.attempted ? .retryRequired : .pending
    }

    /// markArchiveChange replaces one prepaid marker only after a significant canonical transition.
    private func markArchiveChange(owner: AddonID) {
        guard !stopped, !disabledOwners.contains(owner), catalog[owner]?.enabled == true,
            resolution?.acceptedAddons.contains(owner) == true
        else { return }
        ownerPools[owner]?.archiveProgress.current = UUID()
    }

    /// hasPendingArchiveChange ignores this operation's busy flag when checking an admitted attempt.
    private func hasPendingArchiveChange(owner: AddonID) -> Bool {
        guard let progress = ownerPools[owner]?.archiveProgress else { return false }
        return progress.current != progress.saved && progress.current != progress.attempted
    }

    /// savePendingArchive owns lazy startup within the accepted runtime attempt, preventing retry storms.
    /// Pre-admission refusal consumes no marker; a new actual change can supersede a failed attempt.
    func savePendingArchive(
        owner     : AddonID,
        to archive: SwiftDataArchive
    ) async throws -> SwiftDataArchiveSaveOutcome? {
        let installed = try archiveInstalled(
            owner  : owner,
            archive: archive
        )
        guard hasPendingArchiveChange(owner: owner) else { return nil }
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        do {
            try validateArchiveOperation(
                operation,
                installed: installed,
                archive  : archive,
                features : []
            )
            guard hasPendingArchiveChange(owner: owner) else {
                await finishAdmissionAndDrain(operation)
                return nil
            }
            let attemptedChange = ownerPools[owner]?.archiveProgress.current
            ownerPools[owner]?.archiveProgress.attempted = attemptedChange
            _ = try await archive.start()
            try validateArchiveOperation(
                operation,
                installed: installed,
                archive  : archive,
                features : []
            )
            let outcome = try await saveAdmittedArchive(
                operation,
                installed: installed,
                archive  : archive
            )
            await finishAdmissionAndDrain(operation)
            return outcome
        } catch {
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// saveArchive persists one coherent host capture without creating provider or asset authority.
    /// The backend owns its commit boundary; a known committed outcome survives later runtime cleanup.
    func saveArchive(
        owner     : AddonID,
        to archive: SwiftDataArchive
    ) async throws -> SwiftDataArchiveSaveOutcome {
        let installed = try archiveInstalled(
            owner  : owner,
            archive: archive
        )
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        do {
            let outcome = try await saveAdmittedArchive(
                operation,
                installed: installed,
                archive  : archive
            )
            await finishAdmissionAndDrain(operation)
            return outcome
        } catch {
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// saveAdmittedArchive preserves the reviewed capture/save scopes for explicit and pending saves.
    /// Only the captured marker is acknowledged after a known commit; later changes remain pending.
    private func saveAdmittedArchive(
        _ operation: AdmissionOperation,
        installed  : InstalledAddon,
        archive    : SwiftDataArchive
    ) async throws -> SwiftDataArchiveSaveOutcome {
        // Return only the CAS scalar. The backend read callback retains its busy gate,
        // so no write or escaping generation buffer is allowed inside that callback.
        let previous = try await archive.withGeneration { $0?.revision }
        try validateArchiveOperation(
            operation,
            installed: installed,
            archive  : archive,
            features : []
        )
        guard previous != UInt64.max else { throw failure(.resourceDenied) }
        let revision = (previous ?? 0) + 1
        let outcome  = try await governor.withAssetDecodeReservation(
            bytes: RuntimeArchiveEnvelope.maximumPayloadBytes + 65_536 + 128,
            owner: installed.manifest.id
        ) {
            // The outer scope prepays returned payload Data, at most 16 feature labels,
            // and the captured marker.
            // Every capture/encoder scope below ends before the backend adds its workspace.
            let payload = try await self.makeArchivePayload(
                operation: operation,
                installed: installed,
                archive  : archive
            )
            let committed = try await self.commitArchivePayload(
                payload,
                operation: operation,
                installed: installed,
                archive  : archive,
                revision : revision,
                replacing: previous
            )
            return (committed, payload.capturedChange)
        }
        // No authority/cancellation check can undo this known commit or acknowledge a newer graph.
        ownerPools[installed.manifest.id]?.archiveProgress.saved = outcome.1
        return outcome.0
    }

    /// commitArchivePayload validates on the runtime actor immediately before backend handoff.
    /// The caller retains the existing paid output scope until the accepted backend operation returns.
    private func commitArchivePayload(
        _ payload         : ArchivePayload,
        operation         : AdmissionOperation,
        installed         : InstalledAddon,
        archive           : SwiftDataArchive,
        revision          : UInt64,
        replacing previous: UInt64?
    ) async throws -> SwiftDataArchiveSaveOutcome {
        try validateArchiveOperation(
            operation,
            installed: installed,
            archive  : archive,
            features : payload.features
        )
        return try await archive.save(
            SwiftDataArchiveGeneration(
                schemaVersion : 1,
                revision      : revision,
                verifiedDigest: installed.digest,
                payload       : payload.bytes
            ),
            replacing: previous
        )
    }

    /// validateArchiveBinding checks current host binding before storage may provision an owner archive.
    func validateArchiveBinding(
        owner  : AddonID,
        archive: SwiftDataArchive
    ) throws {
        _ = try archiveInstalled(
            owner  : owner,
            archive: archive
        )
    }

    /// archiveInstalled checks immutable backend binding before any runtime or capture admission.
    private func archiveInstalled(
        owner  : AddonID,
        archive: SwiftDataArchive,
        purpose: AdmissionPurpose = .normal
    ) throws -> InstalledAddon {
        try validateAdmissionPurpose(
            purpose,
            owner: owner
        )
        guard let installed = catalog[owner], installed.enabled,
            resolution?.acceptedAddons.contains(owner) == true,
            installed.verifiedIdentity == archive.identity,
            archive.resourceGovernorTarget === governor,
            (1...512).contains(installed.verifiedIdentity.publisher.utf8.count),
            (1...512).contains(installed.digest.utf8.count)
        else { throw failure(.permissionDenied) }
        return installed
    }

    /// validateArchiveOperation rechecks current catalog and captured feature provenance after suspension.
    /// Expiry may remove the original assignment after capture; inert snapshot content remains coherent.
    private func validateArchiveOperation(
        _ operation: AdmissionOperation,
        installed  : InstalledAddon,
        archive    : SwiftDataArchive,
        features   : [String]
    ) throws {
        try validateOperation(
            operation,
            owner: installed.manifest.id
        )
        let current = try archiveInstalled(
            owner  : installed.manifest.id,
            archive: archive,
            purpose: operation.purpose
        )
        guard current.verifiedIdentity == installed.verifiedIdentity, current.digest == installed.digest,
            features.count <= RuntimeArchiveEnvelope.maximumRecords
        else { throw failure(.sessionRevoked) }
        for feature in features {
            try validateArchiveFeature(
                feature,
                installed: current
            )
        }
    }

    /// validateArchiveFeature requires the currently enabled manifest feature for every captured binding.
    private func validateArchiveFeature(
        _ feature: String,
        installed: InstalledAddon
    ) throws {
        guard installed.manifest.features.contains(where: { $0.id == feature }),
            resolution?.enabledFeatures.contains(where: {
                $0.addonID == installed.manifest.id && $0.featureID == feature
            }) == true
        else { throw failure(.permissionDenied) }
    }

    /// makeArchivePayload protects every retained table/leaf before capture and transfers only output.
    /// The additional8MiB scalar/encoder scope exists only during synchronous Publication JSON encoding.
    private func makeArchivePayload(
        operation: AdmissionOperation,
        installed: InstalledAddon,
        archive  : SwiftDataArchive
    ) async throws -> ArchivePayload {
        try validateArchiveOperation(
            operation,
            installed: installed,
            archive  : archive,
            features : []
        )
        return try await governor.withAssetDecodeReservation(
            bytes: RuntimeArchiveEnvelope.retentionReservationBytes(),
            owner: installed.manifest.id
        ) {
            try await self.validateArchiveOperation(
                operation,
                installed: installed,
                archive  : archive,
                features : []
            )
            let capture = try await self.governor.withAssetDecodeReservation(
                bytes: RuntimeArchivePublicationCodec.parserWorkspaceBytes,
                owner: installed.manifest.id
            ) {
                try await self.captureArchive(
                    operation: operation,
                    installed: installed,
                    archive  : archive
                )
            }
            return try await self.copyAndEncodeArchive(
                capture,
                operation: operation,
                installed: installed,
                archive  : archive
            )
        }
    }

    /// captureArchive joins canonical assignments, complete publications and pins without suspension.
    /// JSON conversion ends each borrowed Publication graph's extra lifetime before any copy await.
    private func captureArchive(
        operation: AdmissionOperation,
        installed: InstalledAddon,
        archive  : SwiftDataArchive
    ) throws -> ArchiveCapture {
        try validateArchiveOperation(
            operation,
            installed: installed,
            archive  : archive,
            features : []
        )
        let instant    = try currentInstant()
        let owner      = installed.manifest.id
        let publisher  = Data(installed.verifiedIdentity.publisher.utf8)
        let addon      = Data(owner.rawValue.utf8)
        let digest     = Data(installed.digest.utf8)
        var leafBytes  = publisher.count + addon.count + digest.count
        var aliasCount = 0
        var records : [RuntimeArchiveEnvelope.Record] = []
        var rasters : [ArchiveRaster] = []
        var blobIDs : [ArchiveRasterKey: Data] = [:]
        var features: [String] = []
        func addLeafBytes(_ bytes: Int) throws {
            leafBytes = try RuntimeArchiveCost.add(
                leafBytes,
                bytes
            )
            guard leafBytes <= RuntimeArchiveEnvelope.maximumPayloadBytes else {
                throw failure(.resourceDenied)
            }
        }
        try publicationState.forEachArchivedRecord(
            owner: owner,
            at   : instant.wall
        ) { record in
            guard records.count < RuntimeArchiveEnvelope.maximumRecords,
                let assignment = assignments[record.id], assignment.owner == owner,
                assignment.publisher == installed.verifiedIdentity.publisher,
                assignment.digest == installed.digest
            else { throw failure(.permissionDenied) }
            try validateArchiveFeature(
                assignment.featureID,
                installed: installed
            )
            let partition: Data?
            switch assignment.assetPrivacyPartition {
            case .addonOwned: partition = nil
            case .isolated(let id): partition = RuntimeArchiveEnvelope.uuidBytes(id)
            }
            let feature = Data(assignment.featureID.utf8)
            try addLeafBytes(32 + feature.count + (partition?.count ?? 0))
            var aliases: [RuntimeArchiveEnvelope.Alias] = []
            let json   : Data?
            if let publication = record.publication {
                json = try RuntimeArchivePublicationCodec.encode(publication)
                try addLeafBytes(json?.count ?? 0)
                try assetState.forEachArchivedPin(
                    publication: publication,
                    owner      : owner,
                    at         : instant.wall
                ) {
                    alias,
                    backing,
                    _,
                    _ in
                    guard aliasCount < RuntimeArchiveEnvelope.maximumAliases else {
                        throw failure(.resourceDenied)
                    }
                    aliasCount += 1
                    let key = ArchiveRasterKey(
                        backing  : ObjectIdentifier(backing),
                        partition: assignment.assetPrivacyPartition
                    )
                    let blobID: Data
                    if let existing = blobIDs[key] {
                        blobID = existing
                    } else {
                        guard rasters.count < RuntimeArchiveEnvelope.maximumBlobs else {
                            throw failure(.resourceDenied)
                        }
                        let scratch = try AssetRasterArchiveCopy.scratchBytes(
                            backing: backing,
                            owner  : owner
                        )
                        try addLeafBytes(16 + (partition?.count ?? 0) + scratch / 2)
                        blobID = RuntimeArchiveEnvelope.uuidBytes(UUID())
                        blobIDs[key] = blobID
                        rasters.append(
                            ArchiveRaster(
                                id       : blobID,
                                partition: partition,
                                backing  : backing
                            )
                        )
                    }
                    try addLeafBytes(alias.utf8.count + 16)
                    aliases.append(
                        RuntimeArchiveEnvelope.Alias(
                            name: Data(alias.utf8),
                            blob: blobID
                        )
                    )
                }
            } else {
                json = nil
            }
            records.append(
                RuntimeArchiveEnvelope.Record(
                    instance       : RuntimeArchiveEnvelope.uuidBytes(record.id.instanceID),
                    session        : RuntimeArchiveEnvelope.uuidBytes(record.id.sessionID),
                    feature        : feature,
                    partition      : partition,
                    revision       : record.revision,
                    kind           : record.kind,
                    sessionDeadline: record.sessionDeadline,
                    publication    : json,
                    aliases        : aliases
                )
            )
            features.append(assignment.featureID)
        }
        return ArchiveCapture(
            publisher     : publisher,
            addon         : addon,
            digestBytes   : digest,
            records       : records,
            rasters       : rasters,
            features      : features,
            capturedChange: ownerPools[owner]?.archiveProgress.current
        )
    }

    /// copyAndEncodeArchive keeps copied pixels under capture capacity and uses one copy scratch at a time.
    private func copyAndEncodeArchive(
        _ capture: ArchiveCapture,
        operation: AdmissionOperation,
        installed: InstalledAddon,
        archive  : SwiftDataArchive
    ) async throws -> ArchivePayload {
        try validateArchiveOperation(
            operation,
            installed: installed,
            archive  : archive,
            features : capture.features
        )
        let copier = AssetRasterArchiveCopy()
        var blobs: [RuntimeArchiveEnvelope.Blob] = []
        blobs.reserveCapacity(capture.rasters.count)
        for raster in capture.rasters {
            let scratch = try AssetRasterArchiveCopy.scratchBytes(
                backing: raster.backing,
                owner  : installed.manifest.id
            )
            let pixels = try await governor.withAssetDecodeReservation(
                bytes: scratch,
                owner: installed.manifest.id
            ) {
                try await self.validateArchiveOperation(
                    operation,
                    installed: installed,
                    archive  : archive,
                    features : capture.features
                )
                return try await copier.copy(
                    backing: raster.backing,
                    owner  : installed.manifest.id
                )
            }
            try validateArchiveOperation(
                operation,
                installed: installed,
                archive  : archive,
                features : capture.features
            )
            blobs.append(
                RuntimeArchiveEnvelope.Blob(
                    id       : raster.id,
                    partition: raster.partition,
                    width    : raster.backing.image.width,
                    height   : raster.backing.image.height,
                    pixels   : pixels
                )
            )
        }
        let envelope = RuntimeArchiveEnvelope(
            publisher: capture.publisher,
            addon    : capture.addon,
            digest   : capture.digestBytes,
            records  : capture.records,
            blobs    : blobs
        )
        let quote   = try envelope.encodingReservationBytes()
        let encoded = try await governor.withAssetDecodeReservation(
            bytes: quote,
            owner: installed.manifest.id
        ) {
            try await self.encodeArchive(
                envelope,
                operation: operation,
                installed: installed,
                archive  : archive,
                features : capture.features
            )
        }
        try validateArchiveOperation(
            operation,
            installed: installed,
            archive  : archive,
            features : capture.features
        )
        return ArchivePayload(
            bytes         : encoded,
            features      : capture.features,
            capturedChange: capture.capturedChange
        )
    }

    /// encodeArchive revalidates after encoder admission, then emits bytes into prepaid output capacity.
    private func encodeArchive(
        _ envelope: RuntimeArchiveEnvelope,
        operation : AdmissionOperation,
        installed : InstalledAddon,
        archive   : SwiftDataArchive,
        features  : [String]
    ) throws -> Data {
        try validateArchiveOperation(
            operation,
            installed: installed,
            archive  : archive,
            features : features
        )
        return try envelope.encode()
    }

    /// importAsset imports self-produced data only for the host-issued publication and live connection.
    /// The metadata quote is exact; insertion is the final synchronous admission boundary.
    func importAsset(
        encoded      : Data,
        publicationID: PublicationID,
        connection   : RuntimeConnection
    ) async throws -> AssetState.AssetHandle {
        let initialScope = try importAssetScope(
            publicationID: publicationID,
            connection   : connection
        )
        let owner = initialScope.identity.addonID
        let operation = try await beginAdmission(owner: owner)
        defer {
            pendingAssetMetadataBytes = 0
            finishAdmission(operation)
        }
        do {
            let decoder = assetDecoder
            let alias = try await importBackingAdmitted(
                publicationID: publicationID,
                connection   : connection,
                operation    : operation
            ) {
                try await decoder.decode(
                    encoded: encoded,
                    owner  : owner
                )
            }
            return alias.handle
        } catch {
            pendingAssetMetadataBytes = 0
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// importBackingAdmitted runs the canonical import pipeline under an existing admission.
    /// It never decodes or copies a second time; `decode` supplies the single protected raster.
    private func importBackingAdmitted(
        publicationID: PublicationID,
        connection   : RuntimeConnection,
        operation    : AdmissionOperation,
        decode       : @escaping @Sendable () async throws -> AssetRasterBacking
    ) async throws -> ImportedAlias {
        let owner = connection.identity.addonID
        try validateOperation(
            operation,
            owner: owner
        )
        let scope = try importAssetScope(
            publicationID: publicationID,
            connection   : connection
        )
        let metadataBytes = try assetState.importAdmissionBytes(scope: scope)
        try await growPool(
            owner: owner,
            by   : metadataBytes
        )
        try validateOperation(
            operation,
            owner: owner
        )
        _ = try importAssetScope(
            publicationID: publicationID,
            connection   : connection
        )
        pendingAssetMetadataBytes = metadataBytes
        let backing = try await decode()
        try validateOperation(
            operation,
            owner: owner
        )
        if hasDeferredCleanup {
            // Keep the admission active while the canonical cleanup drain consumes
            // completions received during decode. Its pool reduction includes our quote.
            await drainDeferredCleanup()
            try validateOperation(
                operation,
                owner: owner
            )
        }
        let finalScope = try importAssetScope(
            publicationID: publicationID,
            connection   : connection
        )
        let handle = try assetState.insert(
            backing: backing,
            scope  : finalScope
        )
#if DEBUG
        AssetLifecycleTesting.observer(for: governor)?.aliasCommitted()
#endif
        return ImportedAlias(
            handle: handle,
            scope : finalScope
        )
    }

    /// shareAsset creates a new scoped alias over the same immutable raster.
    /// Host partitions remain immutable, and both publications must retain current authority.
    func shareAsset(
        assetID       : String,
        from sourceID : PublicationID,
        to targetID   : PublicationID,
        connection    : RuntimeConnection
    ) async throws -> AssetState.AssetHandle {
        let initialSource = try importAssetScope(
            publicationID: sourceID,
            connection   : connection
        )
        _ = try importAssetScope(
            publicationID: targetID,
            connection   : connection
        )
        let owner = initialSource.identity.addonID
        let operation = try await beginAdmission(owner: owner)
        defer {
            pendingAssetMetadataBytes = 0
            finishAdmission(operation)
        }
        do {
            let alias = try await shareAssetAdmitted(
                assetID   : assetID,
                sourceID  : sourceID,
                targetID  : targetID,
                connection: connection,
                operation : operation
            )
            return alias.handle
        } catch {
            pendingAssetMetadataBytes = 0
            await shrinkPoolToCurrent(owner: owner)
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// shareAssetAdmitted reuses the canonical sharing metadata quote under an existing admission.
    private func shareAssetAdmitted(
        assetID   : String,
        sourceID  : PublicationID,
        targetID  : PublicationID,
        connection: RuntimeConnection,
        operation : AdmissionOperation
    ) async throws -> ImportedAlias {
        let owner = connection.identity.addonID
        try validateOperation(
            operation,
            owner: owner
        )
        let source = try importAssetScope(
            publicationID: sourceID,
            connection   : connection
        )
        let target = try importAssetScope(
            publicationID: targetID,
            connection   : connection
        )
        let metadataBytes = try assetState.sharingAdmissionBytes(
            assetID: assetID,
            source : source,
            target : target
        )
        try await growPool(
            owner: owner,
            by   : metadataBytes
        )
        try validateOperation(
            operation,
            owner: owner
        )
        _ = try importAssetScope(
            publicationID: sourceID,
            connection   : connection
        )
        _ = try importAssetScope(
            publicationID: targetID,
            connection   : connection
        )
        pendingAssetMetadataBytes = metadataBytes
        if hasDeferredCleanup {
            await drainDeferredCleanup()
            try validateOperation(
                operation,
                owner: owner
            )
        }
        let finalSource = try importAssetScope(
            publicationID: sourceID,
            connection   : connection
        )
        let finalTarget = try importAssetScope(
            publicationID: targetID,
            connection   : connection
        )
        let handle = try assetState.share(
            assetID: assetID,
            source : finalSource,
            target : finalTarget
        )
        return ImportedAlias(
            handle: handle,
            scope : finalTarget
        )
    }

    /// releaseAsset relinquishes an import while leaving published and borrowed images alive.
    /// Release consumes no new metadata and never expands the handle's publication authority.
    func releaseAsset(
        assetID      : String,
        publicationID: PublicationID,
        connection   : RuntimeConnection
    ) async throws {
        let initialScope = try assetScope(
            publicationID: publicationID,
            connection   : connection
        )
        let owner = initialScope.identity.addonID
        let operation = try await beginAdmission(owner: owner)
        defer { finishAdmission(operation) }
        do {
            try await releaseAssetAdmitted(
                assetID      : assetID,
                publicationID: publicationID,
                connection   : connection,
                operation    : operation
            )
            await finishAdmissionAndDrain(operation)
        } catch {
            await finishAdmissionAndDrain(operation)
            throw error
        }
    }

    /// releaseAssetAdmitted reuses scope validation and import release under an existing admission.
    private func releaseAssetAdmitted(
        assetID      : String,
        publicationID: PublicationID,
        connection   : RuntimeConnection,
        operation    : AdmissionOperation
    ) async throws {
        let owner = connection.identity.addonID
        try validateOperation(
            operation,
            owner: owner
        )
        let scope = try assetScope(
            publicationID: publicationID,
            connection   : connection
        )
        try assetState.releaseImport(
            assetID: assetID,
            scope  : scope
        )
        await shrinkPoolToCurrent(owner: owner)
    }

    /// assetImage prevents a stale view from selecting an earlier clock instant or another revision.
    func assetImage(
        assetID            : String,
        publicationID      : PublicationID,
        publicationRevision: UInt64
    ) -> CGImage? {
        guard !stopped, archiveQuiescence == nil, !disabledOwners.contains(publicationID.addonID),
              let instant = try? currentInstant(),
              let publication = publicationState.publication(
                id: publicationID,
                at: instant.wall
              ),
              publication.revision == publicationRevision else { return nil }
        return assetState.image(
            assetID            : assetID,
            publicationID      : publicationID,
            publicationRevision: publicationRevision,
            at                 : instant.wall
        )
    }

    /// assetScope derives asset authority solely from canonical host assignments.
    private func assetScope(
        publicationID: PublicationID,
        connection   : RuntimeConnection
    ) throws -> AssetState.Scope {
        let owner = try connectedOwner(connection)
        guard let assignment = assignments[publicationID],
              assignment.owner == owner, publicationID.addonID == owner,
              assignment.publisher == connection.identity.publisher,
              assignment.digest == connection.digest else { throw failure(.permissionDenied) }
        return AssetState.Scope(
            identity        : connection.identity,
            verifiedDigest  : assignment.digest,
            featureID       : assignment.featureID,
            publicationID   : publicationID,
            connectionToken : connection.token,
            privacyPartition: assignment.assetPrivacyPartition
        )
    }

    /// importAssetScope rejects new imports after the assigned publication ends or expires.
    private func importAssetScope(
        publicationID: PublicationID,
        connection   : RuntimeConnection
    ) throws -> AssetState.Scope {
        let scope = try assetScope(
            publicationID: publicationID,
            connection   : connection
        )
        if assignments[publicationID]?.hasPublished == true {
            guard publicationState.publication(
                id: publicationID,
                at: try currentInstant().wall
            ) != nil else {
                throw failure(.sessionRevoked)
            }
        }
        return scope
    }

    /// commitPublicationAndAssets destroys its proposal before the caller can await pool reduction.
    /// Both components validate before either commits, with no actor suspension between them.
    private func commitPublicationAndAssets(
        _ prepared: PublicationState.PreparedOutput,
        connection: RuntimeConnection,
        at date   : Date
    ) throws -> PublicationAdmission {
        _ = try connectedOwner(connection)
        let assets = try assetState.prepareOutput(
            prepared,
            connectionToken: connection.token
        ) { id in
            try assetScope(
                publicationID: id,
                connection   : connection
            )
        }
        try publicationState.validatePreparedOutput(
            prepared,
            at: date
        )
        try assetState.validatePrepared(assets)
        var changesArchive = false
        prepared.forEachChangedPublication { publication in
            if publication.kind != .notice { changesArchive = true }
        }
        let admission = try publicationState.commitPreparedOutput(
            prepared,
            at: date
        )
        assetState.commitPrepared(assets)
        // Use postcommit kinds: a new publication ended in this same batch has no preimage
        // and is intentionally absent from the changed-publication visitor.
        prepared.forEachEndedPublicationID { id in
            if let record = publicationState.recordAccounting(id: id), record.kind != .notice {
                changesArchive = true
            }
        }
        if changesArchive { markArchiveChange(owner: connection.identity.addonID) }
        return admission
    }

    func diagnostics(owner: AddonID) -> OwnerDiagnostics? {
        guard let pool = ownerPools[owner] else { return nil }
        return OwnerDiagnostics(
            reservedStateBytes    : pool.reservedBytes,
            hasProcess            : processes[owner] != nil,
            hasOutstandingDelivery: processes[owner]?.deliveryOutstanding == true
        )
    }

#if DEBUG
    struct AssetLifecycleSnapshot: Sendable {
        let activeAdmission: Bool
        let cleanupPending: Bool
        let deferredAssemblers: Int
        let cleanupDrains: UInt64
        let assembler: BoundedAssetTransferAssembler.LifecycleSnapshot?
        let transferBinding: AssetTransferBinding?
        let pendingMetadataBytes: Int
        let assetMetadataBytes: Int
        let rasterSlots: Int
        let rasterFaults: Int
        let sessionBytes: Int
        let connectionClosed: Bool
    }

    /// assetLifecycleSnapshotForTesting reads current bounded ownership without retaining
    /// backings, exposing disposal tokens or changing ordinary admission eligibility.
    func assetLifecycleSnapshotForTesting(owner: AddonID) -> AssetLifecycleSnapshot {
        let raster = assetCoordinator.status()
        return AssetLifecycleSnapshot(
            activeAdmission    : activeOperation != nil,
            cleanupPending     : hasDeferredCleanup || cleanupInProgress || activeOperation != nil,
            deferredAssemblers : deferredAssetAssemblers.count,
            cleanupDrains      : assetCleanupDrainCount,
            assembler          : processes[owner]?.assembler.lifecycleSnapshotForTesting(),
            transferBinding    : processes[owner]?.assetTransfer?.binding,
            pendingMetadataBytes: pendingAssetMetadataBytes,
            assetMetadataBytes : assetState.retainedBytes(owner: owner),
            rasterSlots        : raster.slots,
            rasterFaults       : raster.faults,
            sessionBytes       : publicationState.sessionAccounting(owner: owner).connectionBytes,
            connectionClosed   : processes[owner]?.connectionClosed ?? false
        )
    }

    /// flushDisposedAssetsForTesting joins only disposal already queued by actual last use.
    func flushDisposedAssetsForTesting() async throws {
        try await assetCoordinator.flushDisposed()
    }

    /// assetBindingForTesting reads immutable canonical assignment authority, not a token mint.
    func assetBindingForTesting(
        publicationID: PublicationID,
        connection: RuntimeConnection
    ) throws -> AssetTransferBinding {
        try assetBinding(publicationID: publicationID, connection: connection)
    }

    /// endAssetPublicationForTesting delivers one trusted, exact end event while raw ingress
    /// is occupied. The canonical tombstone, asset reconciliation and deferred refunds remain
    /// the production mechanisms. No arbitrary output or replacement registry is accepted.
    func endAssetPublicationForTesting(_ binding: AssetTransferBinding) async throws -> Bool {
        let owner = binding.publicationID.addonID
        guard let process = processes[owner],
              case .connected(let connection) = process.phase,
              (try? assetBinding(publicationID: binding.publicationID, connection: connection)) == binding
        else { return false }
        let instant = try currentInstant()
        let durable = publicationState.recordAccounting(id: binding.publicationID)?.kind != .notice
        try publicationState.remove(id: binding.publicationID, owner: owner)
        assetState.reconcile(publications: publicationState, at: instant.wall)
        reconcileAssetTransfers(at: instant)
        deferInactivePublicationReservations(owner: owner)
        deferredPoolOwners.insert(owner)
        if durable { markArchiveChange(owner: owner) }
        await drainIfNoActiveAdmission()
        return true
    }
#endif

    private func install(
        catalog input: [InstalledAddon],
        environment  : HostEnvironment
    ) async throws {
        guard input.count <= 32,
              environment.hostCapabilities.count <= 128,
              environment.applications.count <= 128,
              environment.grants.count <= 32,
              environment.grants.values.reduce(0, { $0 + $1.count }) <= 256,
              environment.explicitBindings.count <= 128,
              environment.serviceAccessGrants.count <= 128 else {
            throw failure(.resolutionTooComplex)
        }
        guard Self.environmentProjectionBytes(environment) != nil else {
            throw failure(.resourceDenied)
        }
        let encoder = JSONEncoder()
        let projectionBytes = try encoder.encode(environment.hostCapabilities).count
            + encoder.encode(environment.applications).count
            + encoder.encode(environment.grants).count
            + encoder.encode(environment.explicitBindings).count
            + encoder.encode(Array(environment.serviceAccessGrants)).count
        guard projectionBytes <= Self.resolutionBytes else {
            throw failure(.resourceDenied)
        }
        var admitted: [(AddonID, ResourceReservation, Int)] = []
        var resolved: Resolution?
        do {
            for installed in input {
                let encoded = try JSONEncoder().encode(installed.manifest)
                guard encoded.count <= Self.manifestBytes else { throw failure(.resourceDenied) }
                let bytes = Self.ownerMetadataBytes + Self.manifestBytes + Self.resolutionBytes
                    + Self.archiveProgressBytes + Self.archiveQuiescenceBytes
                    + Self.cpuAttributionOwnerBytes
                    + (storageFramesEnabled ? Self.storageOwnerBytes : 0)
                let reservation = try await resourceAccess.admit(
                    .state(bytes: bytes),
                    owner: installed.manifest.id
                )
                admitted.append((installed.manifest.id, reservation, bytes))
            }
            resolved = try ResolutionPlanner.resolve(
                catalog    : input,
                environment: environment,
                prior      : [],
                policy     : ResolutionPolicy(
                    maximumAddons: 32,
                    maximumEdges : 128,
                    maximumDepth : 8
                )
            )
        } catch {
            for (owner, reservation, _) in admitted {
                try? await resourceAccess.release(
                    reservation.id,
                    owner: owner
                )
            }
            throw error
        }
        guard let resolved else { throw failure(.resolutionTooComplex) }
        guard Self.resolutionProjectionBytes(resolved) != nil else {
            for (owner, reservation, _) in admitted {
                try? await resourceAccess.release(
                    reservation.id,
                    owner: owner
                )
            }
            throw failure(.resourceDenied)
        }
        catalog = Dictionary(uniqueKeysWithValues: input.map { ($0.manifest.id, $0) })
        resolution = resolved
        for (owner, reservation, bytes) in admitted {
            ownerPools[owner] = OwnerPool(
                reservation      : reservation,
                baseBytes        : bytes,
                storageOwnGranted: storageFramesEnabled
                    && catalog[owner]?.manifest.permissions.contains(where: {
                        $0.id == .storageOwn && $0.scope == .addon
                    }) == true && environment.grants[owner]?.contains("storage.own") == true,
                reservedBytes: bytes,
                revision     : 0
            )

        }
    }

    /// environmentProjectionBytes is an internal nonmaterializing bound used by focused assembly tests.
    static func environmentProjectionBytes(
        _ environment: HostEnvironment
    ) -> Int? {
        var strings: [String] = []
        appendVersionStrings(
            environment.osVersion,
            to: &strings
        )
        for (key, version) in environment.hostCapabilities {
            strings.append(key)
            appendVersionStrings(
                version,
                to: &strings
            )
        }
        strings.append(contentsOf: environment.applications.keys.map(\.rawValue))
        strings.append(contentsOf: environment.grants.keys.map(\.rawValue))
        for values in environment.grants.values {
            strings.append(contentsOf: values)
        }
        for binding in environment.explicitBindings {
            appendStrings(
                from: binding,
                to  : &strings
            )
        }
        for grant in environment.serviceAccessGrants {
            strings.append(grant.consumer.rawValue)
            strings.append(grant.requirementID)
            strings.append(grant.providerIdentity.publisher)
            strings.append(grant.providerIdentity.addonID.rawValue)
        }
        let versionCount = 1
            + environment.hostCapabilities.count
            + environment.explicitBindings.count
        let scalarCount = environment.hostCapabilities.count
            + environment.applications.count
            + environment.grants.count
            + environment.grants.values.reduce(0, { $0 + $1.count })
            + environment.explicitBindings.count
            + environment.serviceAccessGrants.count
            + versionCount * 3
            + 2
        return checkedProjectionBytes(
            strings    : strings,
            scalarCount: scalarCount,
            limit      : resolutionBytes
        )
    }

    private static func resolutionProjectionBytes(
        _ resolution: Resolution
    ) -> Int? {
        var strings = resolution.acceptedAddons.map(\.rawValue)
        strings.append(contentsOf: resolution.startOrder.map(\.rawValue))
        for blocked in resolution.blockedAddons {
            strings.append(blocked.addonID.rawValue)
            strings.append(blocked.failure.reason)
        }
        for feature in resolution.enabledFeatures {
            strings.append(feature.addonID.rawValue)
            strings.append(feature.featureID)
        }
        for feature in resolution.blockedFeatures {
            strings.append(feature.addonID.rawValue)
            strings.append(feature.featureID)
            strings.append(feature.failure.reason)
        }
        for binding in resolution.bindings {
            appendStrings(
                from: binding,
                to  : &strings
            )
        }
        for (provider, consumers) in resolution.reverseDependents {
            strings.append(provider.rawValue)
            strings.append(contentsOf: consumers.map(\.rawValue))
        }
        let scalarCount = resolution.acceptedAddons.count
            + resolution.blockedAddons.count
            + resolution.enabledFeatures.count
            + resolution.blockedFeatures.count
            + resolution.startOrder.count
            + resolution.bindings.count
            + resolution.reverseDependents.count
            + resolution.reverseDependents.values.reduce(0, { $0 + $1.count })
            + resolution.bindings.count * 3
        return checkedProjectionBytes(
            strings    : strings,
            scalarCount: scalarCount,
            limit      : resolutionBytes
        )
    }

    private static func appendStrings(
        from binding: ServiceBinding,
        to strings  : inout [String]
    ) {
        strings.append(binding.requirementID)
        strings.append(binding.consumer.rawValue)
        strings.append(binding.provider.rawValue)
        strings.append(binding.providerIdentity.publisher)
        strings.append(binding.providerIdentity.addonID.rawValue)
        strings.append(binding.digest)
        appendVersionStrings(
            binding.contractVersion,
            to: &strings
        )
        if let featureID = binding.featureID {
            strings.append(featureID)
        }
    }

    private static func appendVersionStrings(
        _ version: SemanticVersion,
        to strings: inout [String]
    ) {
        if let prerelease = version.prerelease {
            strings.append(prerelease)
        }
        if let buildMetadata = version.buildMetadata {
            strings.append(buildMetadata)
        }
    }

    private static func checkedProjectionBytes(
        strings    : [String],
        scalarCount: Int,
        limit      : Int
    ) -> Int? {
        guard scalarCount >= 0, scalarCount <= limit / 64 else { return nil }
        var total = scalarCount * 64
        for value in strings {
            let bytes = value.utf8.count
            guard bytes <= limit - total else { return nil }
            total += bytes
        }
        return total
    }

    private func beginAdmission(owner: AddonID) async throws -> AdmissionOperation {
        guard
            let operation = try await tryBeginAdmission(
                owner  : owner,
                purpose: .normal
            )
        else {
            throw failure(.resourceDenied)
        }
        return operation
    }

    /// tryBeginAdmission identifies busy at the actual claim seam; no later error is treated as contention.
    private func tryBeginAdmission(
        owner  : AddonID,
        purpose: AdmissionPurpose,
        forServiceRouteDrain: Bool = false
    ) async throws -> AdmissionOperation? {
        try validateAdmissionPurpose(
            purpose,
            owner: owner
        )
        guard activeOperation == nil, !cleanupInProgress,
              !serviceEventDrainInProgress || forServiceRouteDrain else { return nil }
        // The route pass already has an outer cleanup owner. Deferring newly queued
        // cleanup to that owner preserves its once-per-cycle failed-refund budget.
        if !forServiceRouteDrain && (admissionInProgress || hasDeferredCleanup) {
            admissionInProgress = true
            await drainDeferredCleanup()
            admissionInProgress = activeOperation != nil || cleanupInProgress || hasDeferredCleanup
            try validateAdmissionPurpose(
                purpose,
                owner: owner
            )
            guard activeOperation == nil, !cleanupInProgress, !serviceEventDrainInProgress else { return nil }
        }
        admissionInProgress = true
        let operation = AdmissionOperation(
            id               : UUID(),
            owner            : owner,
            authorityRevision: authorityRevision,
            purpose          : purpose
        )
        activeOperation = operation
        return operation
    }

    /// validateAdmissionPurpose keeps all ordinary entry points closed during one-way quiescence.
    private func validateAdmissionPurpose(
        _ purpose: AdmissionPurpose,
        owner    : AddonID
    ) throws {
        try Task.checkCancellation()
        switch purpose {
        case .normal:
            guard archiveQuiescence == nil, !stopped else { throw failure(.sessionRevoked) }
        case .archiveQuiescence(let ticket):
            try validateQuiescence(ticket)
        }
        guard !disabledOwners.contains(owner), catalog[owner] != nil else { throw failure(.sessionRevoked) }
    }

    private func finishAdmission(_ operation: AdmissionOperation) {
        guard activeOperation?.id == operation.id else { return }
        activeOperation = nil
        admissionInProgress = hasDeferredCleanup
    }

    private func finishAdmissionAndDrain(_ operation: AdmissionOperation) async {
        finishAdmission(operation)
        await drainIfNoActiveAdmission()
    }

    private func validateOperation(
        _ operation: AdmissionOperation,
        owner      : AddonID
    ) throws {
        try validateAdmissionPurpose(
            operation.purpose,
            owner: owner
        )
        guard activeOperation?.id == operation.id,
            operation.owner == owner,
            operation.authorityRevision == authorityRevision,
            !stopped, !disabledOwners.contains(owner)
        else {
            throw failure(.sessionRevoked)
        }
    }

    private func validateOperation(
        _ revision: UInt64,
        owner     : AddonID
    ) throws {
        try Task.checkCancellation()
        guard revision == authorityRevision, !stopped, archiveQuiescence == nil,
            !disabledOwners.contains(owner)
        else {
            throw failure(.sessionRevoked)
        }
    }

    private func currentInstant() throws -> RuntimeInstant {
        let instant = clock.now()
        guard instant.wall.timeIntervalSince1970.isFinite,
              instant.monotonic >= .zero else { throw failure(.invalidPayload) }
        return instant
    }

    /// serviceProviderPath derives the selected provider closure in canonical resolver order.
    private func serviceProviderPath(
        to provider: VerifiedAddonIdentity
    ) throws -> [InstalledAddon] {
        guard let resolution, let target = catalog[provider.addonID],
              target.verifiedIdentity == provider else {
            throw failure(.permissionDenied)
        }
        var required: Set<AddonID> = [provider.addonID]
        var changed = true
        while changed {
            changed = false
            for binding in resolution.bindings where required.contains(binding.consumer) {
                guard catalog[binding.provider] != nil else { continue }
                if required.insert(binding.provider).inserted { changed = true }
            }
        }
        let ordered = resolution.startOrder.filter(required.contains)
        guard ordered.count == required.count else { throw failure(.dependencyUnavailable) }
        return try ordered.map { id in
            guard let installed = catalog[id] else { throw failure(.dependencyUnavailable) }
            return installed
        }
    }

    /// admitMissingProviderPath reserves every missing incarnation before the
    /// first start. An acquisition-created consumer interest remains unexposed
    /// until this path returns, so every reservation await and handoff checks
    /// that consumer's fresh resource admission again. Reused interests pass nil.
    private func admitMissingProviderPath(
        _ path               : [InstalledAddon],
        operation            : AdmissionOperation,
        admissionOwner       : AddonID,
        freshConsumerOwner: AddonID? = nil
    ) async throws {
        var missing: [InstalledAddon] = []
        for installed in path {
            if let process = processes[installed.manifest.id] {
                guard process.identity == installed.verifiedIdentity,
                      process.digest == installed.digest,
                      !process.stopRequested else { throw failure(.sessionRevoked) }
            } else {
                try requireLaunchHealthOpen(
                    healthVersion(for: installed),
                    retry: nil
                )
                missing.append(installed)
            }
        }
        guard !missing.isEmpty else { return }
        var prepared: [PreparedLaunch] = []
        do {
            for installed in missing {
                try validatePathOperation(
                    operation,
                    admissionOwner       : admissionOwner,
                    path                 : path,
                    freshConsumerOwner: freshConsumerOwner
                )
                let owner = installed.manifest.id
                let reservation = try await resourceAccess.admit(
                    .provider,
                    owner: owner
                )
                do {
                    try validatePathOperation(
                        operation,
                        admissionOwner       : admissionOwner,
                        path                 : path,
                        freshConsumerOwner: freshConsumerOwner
                    )
                    try await growPool(
                        owner: owner,
                        by   : processAdmissionBytes
                    )
                } catch {
                    try? await resourceAccess.release(
                        reservation.id,
                        owner: owner
                    )
                    throw error
                }
                prepared.append(PreparedLaunch(
                    owner        : owner,
                    installed    : installed,
                    reservation  : reservation,
                    launchID     : RuntimeLaunchID(),
                    incarnation  : RuntimeIncarnation(),
                    isHandedOff  : false
                ))
            }
            for index in prepared.indices {
                try validatePathOperation(
                    operation,
                    admissionOwner       : admissionOwner,
                    path                 : path,
                    freshConsumerOwner: freshConsumerOwner
                )
                let item = prepared[index]
                let version = try healthVersion(for: item.installed)
                try requireLaunchHealthOpen(version, retry: nil)
                var preparedHealth = healthStore
                _ = try preparedHealth.register(version)
                let healthSession = try preparedHealth.bind(
                    version,
                    generation: ConnectionGeneration()
                )
                let instant = try currentInstant()
                let delivery = RuntimeStartDelivery(
                    launchID                  : item.launchID,
                    incarnation               : item.incarnation,
                    identity                  : item.installed.verifiedIdentity,
                    digest                    : item.installed.digest,
                    maximumIngressBytes       : maximumEnvelopeBytes,
                    maximumStorageIngressBytes: storageIngressCapacity,
                    maximumAssetIngressBytes  : assetIngressCapacity,
                maximumServiceIngressBytes: serviceFramesEnabled ? ServiceFrameCodec.maximumEncodedBytes : 0,
                    maximumDeliveryBytes      : deliveryCapacity
                )
                processes[item.owner] = ProcessRecord(
                    launchID          : item.launchID,
                    incarnation       : item.incarnation,
                    identity          : item.installed.verifiedIdentity,
                    digest            : item.installed.digest,
                    providerReservation: item.reservation,
                    coldStartDeadline : instant.monotonic + .seconds(2),
                    assembler         : BoundedAssetTransferAssembler(
                        incarnation: item.incarnation,
                        clock      : clock,
                        decoder    : assetDecoder
                    ),
                    phase             : .pending,
                    stopRequested     : false,
                    healthSession     : healthSession
                )
                launches[item.launchID] = item.owner
                healthStore = preparedHealth
                delegatedHealthSessions.removeValue(forKey: item.owner)
                guard adapter.tryHandoff(
                    incarnation: item.incarnation,
                    delivery   : .start(delivery)
                ) == .accepted else {
                    processes.removeValue(forKey: item.owner)
                    launches.removeValue(forKey: item.launchID)
                    healthStore.cancel(owner: item.owner)
                    throw failure(.dependencyUnavailable)
                }
                ownerPools[item.owner]?.restorationSealed = true
                prepared[index].isHandedOff = true
            }
        } catch {
            for item in prepared where !item.isHandedOff {
                if processes[item.owner]?.incarnation == item.incarnation {
                    processes.removeValue(forKey: item.owner)
                    launches.removeValue(forKey: item.launchID)
                }
                try? await resourceAccess.release(
                    item.reservation.id,
                    owner: item.owner
                )
                await shrinkPoolToCurrent(owner: item.owner)
            }
            throw error
        }
    }

    private func validatePathOperation(
        _ operation         : AdmissionOperation,
        admissionOwner      : AddonID,
        path                : [InstalledAddon],
        freshConsumerOwner: AddonID?
    ) throws {
        try validateOperation(
            operation,
            owner: admissionOwner
        )
        if let freshConsumerOwner {
            try requireFreshAdmissionOpen(owner: freshConsumerOwner)
        }
        guard path.allSatisfy({ installed in
            let owner = installed.manifest.id
            return !disabledOwners.contains(owner)
                && installed.enabled
                && resolution?.acceptedAddons.contains(owner) == true
                && catalog[owner]?.verifiedIdentity == installed.verifiedIdentity
                && catalog[owner]?.digest == installed.digest
        }) else { throw failure(.sessionRevoked) }
    }

    private func actionContext(
        _ id   : PublicationID,
        at date: Date
    ) throws -> ActionAuthorizer.Context {
        guard let assignment = assignments[id],
              let installed = catalog[assignment.owner],
              let resolution else { throw failure(.permissionDenied) }
        return ActionAuthorizer.Context(
            installed  : installed,
            resolution : resolution,
            featureID  : assignment.featureID,
            publication: publicationState.publication(
                id: id,
                at: date
            ),
            eligibility: disabledOwners.contains(assignment.owner)
                ? .unavailable
                : assignment.eligibility
        )
    }

    private func connectedOwner(_ connection: RuntimeConnection) throws -> AddonID {
        let owner = connection.identity.addonID
        guard !stopped, archiveQuiescence == nil, !disabledOwners.contains(owner),
              let process = processes[owner],
              process.incarnation == connection.incarnation,
              case .connected(let current) = process.phase,
              current.token == connection.token,
              current.identity == connection.identity,
              current.digest == connection.digest,
              current.authorityRevision == connection.authorityRevision else {
            throw failure(.sessionRevoked)
        }
        return owner
    }

    private func growPool(
        owner: AddonID,
        by bytes: Int
    ) async throws {
        guard bytes >= 0, let pool = ownerPools[owner], bytes <= Int.max - pool.reservedBytes else {
            throw failure(.resourceDenied)
        }
        let target = pool.reservedBytes + bytes
        guard try await resourceAccess.resizeStateReservation(
            pool.reservation.id,
            owner    : owner,
            fromBytes: pool.reservedBytes,
            toBytes  : target
        ) else { throw failure(.resourceDenied) }
        guard var current = ownerPools[owner], current.reservation.id == pool.reservation.id,
              current.revision == pool.revision,
              current.reservedBytes == pool.reservedBytes else {
            throw failure(.sessionRevoked)
        }
        guard current.revision < UInt64.max else { throw failure(.resourceDenied) }
        current.reservedBytes = target
        current.revision += 1
        ownerPools[owner] = current
    }

    private func requiredBytes(owner: AddonID) -> Int {
        guard let pool = ownerPools[owner] else { return 0 }
        var total = pool.baseBytes
        total += assetState.retainedBytes(owner: owner)
        if activeOperation?.owner == owner {
            total += pendingAssetMetadataBytes + pendingArchiveMetadataBytes + pendingServiceMetadataBytes
        }
        total += assignments.values.filter({ $0.owner == owner }).count * Self.assignmentBytes
        if processes[owner] != nil {
            total += processAdmissionBytes
        }
        let session = publicationState.sessionAccounting(owner: owner)
        total += session.connectionBytes + session.namespaceBytes
        for id in assignments.keys where id.addonID == owner {
            if let accounting = publicationState.recordAccounting(id: id) {
                total += accounting.contentBytes + accounting.tombstoneBytes
            }
        }
        dispatcher.visitRecordAccounting { accounting in
            guard accounting.owner == owner else { return }
            total += accounting.journalBytes + accounting.schedulerBytes
                + accounting.bindingBytes + Self.actionRowBytes
        }
        total += servicePermissions.values.filter({ $0.owner == owner }).count
            * Self.servicePermissionBytes
        total += serviceGrants.values.filter({ $0.owner == owner }).count
            * Self.serviceGrantBytes
        total += serviceExecutions.values.filter({ $0.consumer == owner }).count
            * Self.serviceExecutionBytes
        total += invocationExchange.retainedBytes(owner: owner)
        total += serviceConnections.retainedBytes(owner: owner)
        total += serviceSubscriptions.retainedBytes(owner: owner)
        total += serviceSources.values.filter { $0.key.provider.addonID == owner }.count * RuntimeServiceSourceBinding.bytes
        total += serviceCache.retainedBytes(owner: owner)
        total += sourceExecutions.values.filter({ $0.provider == owner }).count
            * Self.sourceExecutionBytes
        return total
    }

    private func shrinkPoolToCurrent(owner: AddonID) async {
        guard let pool = ownerPools[owner] else { return }
        let required = requiredBytes(owner: owner)
        guard required < pool.reservedBytes,
              await resourceAccess.reduceStateReservation(
                pool.reservation.id,
                owner  : owner,
                toBytes: required
              ) else { return }
        guard var current = ownerPools[owner],
              current.reservation.id == pool.reservation.id,
              current.revision == pool.revision,
              current.reservedBytes == pool.reservedBytes else { return }
        guard current.revision < UInt64.max else {
            stopped = true
            return
        }
        current.reservedBytes = required
        current.revision += 1
        ownerPools[owner] = current
    }

    private func shrinkAllPools() async {
        for owner in Array(ownerPools.keys) {
            await shrinkPoolToCurrent(owner: owner)
        }
    }

    private func connection(from phase: ProcessPhase) -> RuntimeConnection? {
        switch phase {
        case .pending: return nil
        case .connected(let connection): return connection
        case .stopping(let connection): return connection
        }
    }

    private func advanceAuthority() {
        if authorityRevision == UInt64.max {
            stopped = true
        } else {
            authorityRevision += 1
        }
    }

    private var hasDeferredCleanup: Bool {
        !pendingMetricDetaches.isEmpty
            || !deferredDisabledProviders.isEmpty
            || !deferredServiceCompletions.isEmpty
            || !deferredExits.isEmpty
            || !pendingCrashDecisions.isEmpty
            || !deferredConnectionCloses.isEmpty
            || !deferredAssetAssemblers.isEmpty
            || !deferredReleases.isEmpty
            || !deferredPoolOwners.isEmpty
            || deferredBrokerReconcileReason != nil
            || deferredBrokerExpiry != nil
            || deferredBrokerShutdown
    }

    private func deferRelease(
        _ reservation: ResourceReservation,
        owner        : AddonID
    ) {
        deferredReleases[reservation.id] = owner
    }

    private func deferBrokerReconciliation(_ reason: RuntimeStopReason) {
        func rank(_ value: RuntimeStopReason) -> Int {
            switch value {
            case .stopped: return 4
            case .disabled: return 3
            case .connectionLost: return 2
            case .deadlineExceeded: return 1
            }
        }
        guard let current = deferredBrokerReconcileReason else {
            deferredBrokerReconcileReason = reason
            return
        }
        if rank(reason) > rank(current) {
            deferredBrokerReconcileReason = reason
        }
    }

    @discardableResult
    private func drainIfNoActiveAdmission(
        reportingServiceCompletion workID: UUID? = nil
    ) async -> ServiceCompletionDrainOutcome? {
        // Coalesce over the actual outer owner's lifetime, including the cleanup tail
        // after its work loop but before the final assembler refund returns. A nested
        // caller may return pending; only this owner consumes the requested next pass.
        if serviceEventDrainInProgress {
            serviceEventDrainRequested = true
            return nil
        }
        guard activeOperation == nil, !cleanupInProgress else { return nil }
        serviceEventDrainInProgress = true
        defer { serviceEventDrainInProgress = false }
        var outcome: ServiceCompletionDrainOutcome?
        var failedAssetCleanups: Set<RuntimeIncarnation> = []
        repeat {
            serviceEventDrainRequested = false
            if hasDeferredCleanup {
                admissionInProgress = true
                let drained = await drainDeferredCleanup(reportingServiceCompletion: workID,
                                                         skippingAssetCleanups: failedAssetCleanups)
                if let reported = drained.outcome { outcome = reported }
                // Tail events can queue an assembler that has never been attempted.
                // Only actual failures join this cycle's no-retry set.
                failedAssetCleanups.formUnion(drained.failedAssetCleanups)
                admissionInProgress = false
            }
            await drainInvocationRoutes()
            await drainSubscriptionRoutes()
            // Only an observed event (or exact route settlement) requests another
            // pass. Retained failed refunds alone never drive this loop. New public
            // admissions cannot replenish routes throughout this outer owner's awaits.
        } while serviceEventDrainRequested && activeOperation == nil && !cleanupInProgress
        return outcome
    }

    @discardableResult
    private func drainDeferredCleanup(
        reportingServiceCompletion reportedWorkID: UUID? = nil,
        skippingAssetCleanups: Set<RuntimeIncarnation> = []
    ) async -> (outcome: ServiceCompletionDrainOutcome?, failedAssetCleanups: Set<RuntimeIncarnation>) {
        guard !cleanupInProgress else { return (nil, []) }
        var reportedOutcome: ServiceCompletionDrainOutcome?
        var failedAssetCleanups: Set<RuntimeIncarnation> = []
        cleanupInProgress = true
#if DEBUG
        if assetCleanupDrainCount < UInt64.max { assetCleanupDrainCount += 1 }
#endif
        // A failed protected refund retains its exact assembler here. Each one is attempted
        // once per drain invocation and a failure is re-retained without re-entering the
        // loop, so an unrefundable reservation cannot spin the deferred cleanup.
        var retainedAssemblers = deferredAssetAssemblers
        deferredAssetAssemblers.removeAll(keepingCapacity: true)
        while hasDeferredCleanup {
            await drainPendingMetricDetaches()
            // Lifecycle work in this iteration may revoke another process; move its
            // assembler aside before the loop condition is checked again.
            if !deferredAssetAssemblers.isEmpty {
                retainedAssemblers.merge(deferredAssetAssemblers) { _, new in new }
                deferredAssetAssemblers.removeAll(keepingCapacity: true)
            }
            let completions = deferredServiceCompletions
            deferredServiceCompletions.removeAll(keepingCapacity: true)
            for (workID, completion) in completions {
                var preparation: ServiceBroker.CompletionPreparation?
                do {
                    try validateDeferredServiceCompletion(
                        workID,
                        completion: completion
                    )
                    let preparedCompletion = try await serviceDecisionAccess.prepareInvocationCompletion(
                        workID,
                        response  : completion.response,
                        receivedAt: completion.receivedAt
                    )
                    preparation = preparedCompletion
                    try validateDeferredServiceCompletion(
                        workID,
                        completion: completion
                    )
                    if let preparedCompletion = completion.preparedCompletion {
                        try publicationState.validatePreparedCompletion(preparedCompletion)
                    }
                    _ = try await broker.commitInvocationCompletion(preparedCompletion)
                    try validateDeferredServiceCompletion(
                        workID,
                        completion: completion
                    )
                    let admission: PublicationAdmission?
                    if let preparedCompletion = completion.preparedCompletion {
                        admission = try publicationState.commitPreparedCompletion(preparedCompletion)
                    } else {
                        admission = nil
                    }
                    if let claim = completion.ingressClaim {
                        disposeIngress(
                            claim,
                            owner      : completion.provider,
                            incarnation: completion.providerIncarnation,
                            disposition: .finish
                        )
                    }
                    inFlightServiceCompletionIDs.remove(workID)
                    invocationExchange.mark(workID: workID, terminal: .completed)
                    deferServiceExecutionRelease(workID)
                    if workID == reportedWorkID {
                        reportedOutcome = .accepted(admission)
                    }
                } catch {
                    if let preparation {
                        await broker.cancelInvocationCompletion(preparation)
                    }
                    if let claim = completion.ingressClaim {
                        disposeIngress(
                            claim,
                            owner      : completion.provider,
                            incarnation: completion.providerIncarnation,
                            disposition: .cancel
                        )
                    }
                    if let execution = serviceExecutions[workID] {
                        requestStopOnce(
                            owner : execution.provider,
                            reason: .deadlineExceeded
                        )
                    }
                    if workID == reportedWorkID {
                        reportedOutcome = .refused
                    }
                }
            }

            let disabled = deferredDisabledProviders
            deferredDisabledProviders.removeAll(keepingCapacity: true)
            for identity in disabled.values {
                _ = await broker.disableAddon(identity)
            }

            let closes = deferredConnectionCloses
            deferredConnectionCloses.removeAll(keepingCapacity: true)
            for connection in closes.values {
                await broker.disconnect(connection.serviceSession)
            }

            let exits = deferredExits
            deferredExits.removeAll(keepingCapacity: true)
            for exit in exits.values {
                if let connection = exit.connection {
                    await broker.providerExitedPreservingInterests(exit.process.identity)
                    await broker.disconnect(connection.serviceSession)
                }
                // Join the same per-drain collection as stop and exact revocation. Trying
                // here and again in the final loop would retry a failed token twice in one
                // invocation. A live native finish still owns its own eventual disposal.
                retainedAssemblers[exit.process.incarnation] = exit.process.assembler
            }

            if let instant = deferredBrokerExpiry {
                deferredBrokerExpiry = nil
                _ = await broker.expire(now: instant)
            }
            if deferredBrokerShutdown {
                deferredBrokerShutdown = false
                _ = await broker.shutdown()
            }
            if let reason = deferredBrokerReconcileReason {
                deferredBrokerReconcileReason = nil
                await reconcileBrokerAuthority(stopReason: reason)
            }

            // The cleanup lane owns broker mutations while this exact crash
            // decision reads canonical demand. An exit queued behind another
            // admission remains unresolved and cannot admit fallback/launch.
            for (owner, decision) in Array(pendingCrashDecisions) {
                let demanded = await hasCurrentRecoveryDemand(
                    owner   : owner,
                    provider: decision.identity
                )
                guard pendingCrashDecisions[owner]?.incarnation == decision.incarnation,
                      pendingCrashDecisions[owner]?.session == decision.session else { continue }
                pendingCrashDecisions.removeValue(forKey: owner)
                guard processes[owner] == nil,
                      !stopped, !disabledOwners.contains(owner),
                      let installed = catalog[owner], installed.enabled,
                      installed.verifiedIdentity == decision.identity,
                      installed.digest == decision.digest,
                      let instant = try? currentInstant() else {
                    healthStore.cancel(owner: owner)
                    continue
                }
                do {
                    _ = try healthStore.crashed(
                        decision.session,
                        demandExists: demanded,
                        at          : instant
                    )
                } catch {
                    healthStore.cancel(owner: owner)
                }
            }

            let releases = deferredReleases
            deferredReleases.removeAll(keepingCapacity: true)
            for (id, owner) in releases {
                try? await resourceAccess.release(
                    id,
                    owner: owner
                )
            }

            let owners = deferredPoolOwners
            deferredPoolOwners.removeAll(keepingCapacity: true)
            for owner in owners {
                await shrinkPoolToCurrent(owner: owner)
            }
        }
        for (incarnation, assembler) in retainedAssemblers {
            guard !skippingAssetCleanups.contains(incarnation) else {
                deferredAssetAssemblers[incarnation] = assembler
                continue
            }
            do {
                // Terminal retention closes; an exact nonterminal revocation only finishes its
                // refund and leaves the assembler idle and reusable for the live process.
#if DEBUG
                // Before the actual assembler call, not inside its governor refund hop.
                await Self.serviceInvocationObserver?(.cleanupTailBeforeAssembler)
#endif
                try await assembler.drainPendingCleanup()
            } catch {
                deferredAssetAssemblers[incarnation] = assembler
                failedAssetCleanups.insert(incarnation)
            }
        }
        cleanupInProgress = false
        return (reportedOutcome, failedAssetCleanups)
    }

    private func validateDeferredServiceCompletion(
        _ workID   : UUID,
        completion : DeferredServiceCompletion
    ) throws {
        guard completion.authorityRevision == authorityRevision,
              !stopped, archiveQuiescence == nil,
              let execution = serviceExecutions[workID], execution.isHandedOff,
              execution.consumer == completion.consumer,
              execution.grantID == completion.grantID,
              execution.connectionToken == completion.connectionToken,
              execution.providerIncarnation == completion.providerIncarnation,
              serviceGrants[completion.grantID]?.owner == completion.consumer,
              let consumerProcess = processes[completion.consumer],
              case .connected(let consumerConnection) = consumerProcess.phase,
              consumerConnection.token == completion.connectionToken else {
            throw failure(.sessionRevoked)
        }
    }

    private func requestStopOnce(
        owner : AddonID,
        reason: RuntimeStopReason
    ) {
        if reason != .connectionLost {
            let unresolved = pendingCrashDecisions.removeValue(forKey: owner)
            if unresolved != nil || processes[owner]?.pendingCrashSession != nil {
                healthStore.cancel(owner: owner)
                processes[owner]?.pendingCrashSession = nil
            }
        }
        guard var process = processes[owner], !process.stopRequested else { return }
        revokeMetricProcess(
            owner               : owner,
            process             : process,
            preserveCrashSession: reason == .connectionLost
        )
        process = processes[owner] ?? process
        invocationExchange.invalidate(owner: owner)
        invalidateSubscriptionConnection(process.incarnation)
        process = processes[owner] ?? process
        process.stopRequested = true
        process.phase = .stopping(connection(from: process.phase))
        // Synchronous revocation is separate from async disposal so a suspended or native
        // finish cannot return authority after stop; live decode keeps its own cleanup.
        process.assembler.invalidate()
        process.assetTransfer = nil
        processes[owner] = process
        // Retain the exact assembler for bounded deferred disposal even if this process
        // never physically exits, so a stopped incarnation cannot keep assembly charged.
        deferredAssetAssemblers[process.incarnation] = process.assembler
        adapter.requestStop(
            incarnation: process.incarnation,
            reason     : reason
        )
    }

    private func releaseTerminalActionResources(owner: AddonID) async {
        for key in Array(actionResources.keys) where key.owner == owner {
            guard dispatcher.recordAccounting(
                owner    : owner,
                requestID: key.requestID
            )?.jobID == nil,
            let resources = actionResources.removeValue(forKey: key) else { continue }
            if let job = resources.job {
                try? await resourceAccess.release(
                    job.id,
                    owner: owner
                )
            }
            try? await resourceAccess.release(
                resources.command.id,
                owner: owner
            )
        }
    }

    private func deferTerminalActionResources(owner: AddonID) {
        for key in Array(actionResources.keys) where key.owner == owner {
            guard dispatcher.recordAccounting(
                owner    : owner,
                requestID: key.requestID
            )?.jobID == nil,
            let resources = actionResources.removeValue(forKey: key) else { continue }
            if let job = resources.job {
                deferRelease(
                    job,
                    owner: owner
                )
            }
            deferRelease(
                resources.command,
                owner: owner
            )
        }
        deferredPoolOwners.insert(owner)
    }

    private func releaseInactivePublicationReservations(owner: AddonID) async {
        for id in Array(publicationReservations.keys) where id.addonID == owner {
            guard publicationState.recordAccounting(id: id)?.contentBytes ?? 0 == 0,
                  let reservation = publicationReservations.removeValue(forKey: id) else { continue }
            try? await resourceAccess.release(
                reservation.id,
                owner: owner
            )
        }
    }

    private func deferInactivePublicationReservations(owner: AddonID) {
        for id in Array(publicationReservations.keys) where id.addonID == owner {
            guard publicationState.recordAccounting(id: id)?.contentBytes ?? 0 == 0,
                  let reservation = publicationReservations.removeValue(forKey: id) else { continue }
            deferRelease(
                reservation,
                owner: owner
            )
        }
        deferredPoolOwners.insert(owner)
    }

    private func deferServiceExecutionRelease(_ id: UUID) {
        invocationExchange.mark(workID: id, terminal: .unknown)
        guard let execution = serviceExecutions.removeValue(forKey: id) else { return }
        inFlightServiceCompletionIDs.remove(id)
        deferredServiceCompletions.removeValue(forKey: id)
        deferRelease(
            execution.job,
            owner: execution.provider
        )
        deferRelease(
            execution.command,
            owner: execution.consumer
        )
        deferredPoolOwners.insert(execution.consumer)
    }

    private func pruneAssignments(owner: AddonID) {
        guard processes[owner] == nil else { return }
        for id in Array(assignments.keys) where id.addonID == owner {
            guard assignments[id]?.hasPublished == true else { continue }
            let publication = publicationState.recordAccounting(id: id)
            guard publication?.contentBytes ?? 0 == 0,
                  !dispatcher.hasRecord(publicationID: id) else { continue }
            publicationState.removeHistory(id: id)
            assignments.removeValue(forKey: id)
            if let publication, publication.kind != .notice { markArchiveChange(owner: owner) }
        }
    }

    private func reconcileBrokerAuthority(stopReason: RuntimeStopReason) async {
        let activeGrants = await broker.activeGrantIDs()
        let activeSources = await broker.activeSourceIDs()
        serviceGrants = serviceGrants.filter { activeGrants.contains($0.key) }
        for id in Array(serviceSubscriptions.aliases.keys) {
            guard let alias = serviceSubscriptions.aliases[id], !activeGrants.contains(alias.grantID) else { continue }
            serviceSubscriptions.aliases.removeValue(forKey: id)
            if let receipt = alias.receipt { releaseDelivery(.subscriptionAccepted(receipt), owner: alias.connection.identity.addonID, incarnation: alias.connection.incarnation) }
            deferredPoolOwners.insert(alias.connection.identity.addonID)
        }
        for id in Array(serviceSources.keys) where !activeSources.contains(id) {
            if let source = removeSubscriptionSource(id) {
                requestStopOnce(owner: source.key.provider.addonID, reason: stopReason)
                deferredPoolOwners.insert(source.key.provider.addonID)
            }
        }
        for id in Array(serviceCache.entries.keys) where !activeSources.contains(id) {
            if let cached = serviceCache.entries.removeValue(forKey: id) { deferredPoolOwners.insert(cached.key.provider.addonID) }
        }
        for route in invocationExchange.routes.values where serviceGrants[route.grantID] == nil {
            var ready = route; ready.terminal = .unknown; invocationExchange.update(ready)
        }
        for id in Array(serviceExecutions.keys) {
            guard let execution = serviceExecutions[id],
                  !activeGrants.contains(execution.grantID) else { continue }
            if execution.isHandedOff {
                requestStopOnce(
                    owner : execution.provider,
                    reason: stopReason
                )
            } else {
                await releaseServiceExecution(id)
            }
        }
        for id in Array(sourceExecutions.keys) {
            guard let execution = sourceExecutions[id], !activeSources.contains(id) else { continue }
            if execution.isHandedOff {
                requestStopOnce(
                    owner : execution.provider,
                    reason: stopReason
                )
            } else {
                sourceExecutions.removeValue(forKey: id)
                try? await resourceAccess.release(
                    execution.job.id,
                    owner: execution.provider
                )
                deferredPoolOwners.insert(execution.provider)
            }
        }
    }

    private func releaseServiceExecution(
        _ id         : UUID,
        reconcilePool: Bool = true
    ) async {
        invocationExchange.mark(workID: id, terminal: .unknown)
        guard let execution = serviceExecutions.removeValue(forKey: id) else { return }
        inFlightServiceCompletionIDs.remove(id)
        deferredServiceCompletions.removeValue(forKey: id)
        try? await resourceAccess.release(
            execution.job.id,
            owner: execution.provider
        )
        try? await resourceAccess.release(
            execution.command.id,
            owner: execution.consumer
        )
        if reconcilePool {
            await shrinkPoolToCurrent(owner: execution.consumer)
        }
    }

    private func refreshDeadline(
        _ id              : UUID,
        owner             : AddonID,
        deadline          : DeadlineQueue.Deadline?
    ) throws {
        if let deadline {
            try deadlines.schedule(
                id,
                owner   : owner,
                deadline: deadline
            )
        } else {
            try deadlines.cancel(
                id,
                owner: owner
            )
        }
    }

    /// migrateAggregateDeadlines transfers the fixed host keys after authority
    /// revalidation, preserving DeadlineQueue's authenticated replacement rule.
    private func migrateAggregateDeadlines(to owner: AddonID) {
        guard aggregateDeadlineOwner != owner else { return }
        if let previousOwner = aggregateDeadlineOwner {
            deadlines.remove(owner: previousOwner)
        }
        aggregateDeadlineOwner = owner
    }

    /// clearAggregateDeadlines removes the fixed host keys when runtime authority
    /// no longer has an eligible aggregate owner.
    private func clearAggregateDeadlines() {
        if let owner = aggregateDeadlineOwner {
            deadlines.remove(owner: owner)
        }
        aggregateDeadlineOwner = nil
    }

    /// metricRetryDeadline keeps a deferred resource pass inside the same finite
    /// monotonic horizon accepted by ProcessMetricsCoordinator before adding cadence.
    private func metricRetryDeadline(after instant: Duration) throws -> Duration {
        let maximum = Duration.nanoseconds(Int64.max)
        guard instant <= maximum - .seconds(1) else { throw failure(.invalidPayload) }
        return instant + .seconds(1)
    }

    private func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(
            code  : code,
            reason: "The addon runtime rejected this operation."
        )
    }
}
