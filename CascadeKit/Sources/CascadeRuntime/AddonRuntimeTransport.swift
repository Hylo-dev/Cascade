//
//  AddonRuntimeTransport.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeClock supplies trusted synchronous wall and monotonic time samples.
protocol RuntimeClock: Sendable {
    func now() -> RuntimeInstant
}

/// SystemRuntimeClock is the production clock for runtime deadline decisions.
struct SystemRuntimeClock: RuntimeClock {
    func now() -> RuntimeInstant {
        RuntimeInstant(
            wall     : Date(),
            monotonic: .seconds(ProcessInfo.processInfo.systemUptime)
        )
    }
}

/// RuntimeIncarnation is an opaque physical-process identity minted by the host.
struct RuntimeIncarnation: Hashable, Sendable {
    fileprivate let token = UUID()
}

/// RuntimeLaunchID identifies one reserved cold launch before its single attachment.
struct RuntimeLaunchID: Hashable, Sendable {
    fileprivate let token = UUID()
}

/// RuntimeIngressHandle identifies one adapter-owned, bounded provider-output slot.
struct RuntimeIngressHandle: Hashable, Sendable {
    let token           : UUID
    let incarnation     : RuntimeIncarnation
    let encodedBytes    : Int
    let isCompletionOnly: Bool
}

/// RuntimeStartDelivery carries bounded host authority for one cold-start request.
struct RuntimeStartDelivery: Equatable, Sendable {
    let launchID                  : RuntimeLaunchID
    let incarnation               : RuntimeIncarnation
    let identity                  : VerifiedAddonIdentity
    let digest                    : String
    let maximumIngressBytes       : Int
    let maximumStorageIngressBytes: Int
    let maximumServiceIngressBytes: Int
    let maximumAssetIngressBytes  : Int
    let maximumDeliveryBytes      : Int

    init(
        launchID                  : RuntimeLaunchID,
        incarnation               : RuntimeIncarnation,
        identity                  : VerifiedAddonIdentity,
        digest                    : String,
        maximumIngressBytes       : Int,
        maximumStorageIngressBytes: Int = 0,
        maximumAssetIngressBytes  : Int = 0,
        maximumServiceIngressBytes: Int = 0,
        maximumDeliveryBytes      : Int = 80 * 1_024
    ) {
        self.launchID = launchID
        self.incarnation = incarnation
        self.identity = identity
        self.digest = digest
        self.maximumIngressBytes = maximumIngressBytes
        self.maximumStorageIngressBytes = maximumStorageIngressBytes
        self.maximumAssetIngressBytes = maximumAssetIngressBytes
        self.maximumServiceIngressBytes = maximumServiceIngressBytes
        self.maximumDeliveryBytes = maximumDeliveryBytes
    }
}

/// RuntimeAdapterDelivery is the bounded synchronous handoff vocabulary of this cut.
enum RuntimeAdapterDelivery: Equatable, Sendable {
    case start(RuntimeStartDelivery)
    case action(ActionDispatcher.Delivery)
    case source(ServiceSourceDescriptor)
    case service(ServiceWork)
    case serviceInvocation(RuntimeServiceDelivery)
    case serviceReply(RuntimeServiceDelivery)
    case serviceControl(RuntimeServiceSubscriptionDelivery)
    case serviceSourceStart(RuntimeServiceSubscriptionDelivery)
    case serviceEvent(RuntimeServiceSubscriptionDelivery)
    case storageResponse(RuntimeStorageResponseDelivery)
    case assetResponse(RuntimeAssetResponseDelivery)
}

/// RuntimeStopReason explains why the adapter should withdraw queued work and stop a process.
enum RuntimeStopReason: Equatable, Sendable {
    case disabled
    case stopped
    case connectionLost
    case deadlineExceeded
}

/// RuntimeHandoffResult linearizes whether a bounded delivery reached adapter ownership.
enum RuntimeHandoffResult: Equatable, Sendable {
    case accepted
    case rejectedBeforeHandoff
}

/// AddonRuntimeAdapter is a synchronous host transport boundary with no production conformer yet.
/// Implementations must not run addon code, wait for IPC or invoke AddonRuntime recursively.
/// rejectedBeforeHandoff guarantees the delivery was neither exposed nor retained.
/// Accepted data occupies one bounded incarnation slot until receipt, stop or exit.
/// Runtime keeps an exact work credit until its matching synchronous receipt. An action
/// acknowledgment releases that payload but does not terminate the provider job.
protocol AddonRuntimeAdapter: Sendable {
    func takeIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> ProviderOutput?

    /// rejectIngress removes only a staged value; it cannot revoke another caller's transfer.
    func rejectIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    )

    /// cancelIngress is available only to the invocation that successfully took the transfer.
    func cancelIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    )

    /// finishIngress disposes only the successful taker's transfer. Runtime retains its exact
    /// invocation claim through this call, including when deferred cleanup owns that claim.
    func finishIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    )

    func tryHandoff(
        incarnation: RuntimeIncarnation,
        delivery   : RuntimeAdapterDelivery
    ) -> RuntimeHandoffResult

    func requestStop(
        incarnation: RuntimeIncarnation,
        reason     : RuntimeStopReason
    )

    /// deliveryWasReceived is called only after runtime matches the exact current work credit.
    /// It must dispose the occupied payload synchronously without recursively entering runtime.
    func deliveryWasReceived(incarnation: RuntimeIncarnation)
    func processDidExit(incarnation: RuntimeIncarnation)
}

/// RuntimeStorageIngressHandle identifies one raw frame in the shared typed ingress slot.
/// encodedBytes is checked before transfer and against the actual compact value after taking it.
/// sequence is strictly increasing per canonical connection; a request UUID grants no replay.
struct RuntimeStorageIngressHandle: Hashable, Sendable {
    let token       : UUID
    let incarnation : RuntimeIncarnation
    let encodedBytes: Int
    let sequence    : UInt64
}

/// RuntimeStorageReceipt binds one accepted reply to its host nonce and canonical connection.
struct RuntimeStorageReceipt: Equatable, Sendable {
    let token          : UUID
    let incarnation    : RuntimeIncarnation
    let connectionToken: UUID
    let sequence       : UInt64
    let requestID      : UUID
    let operation      : StorageOperation
}

/// RuntimeStorageResponseDelivery retains encoded bytes only in prepaid adapter payload capacity.
struct RuntimeStorageResponseDelivery: Equatable, Sendable {
    let receipt: RuntimeStorageReceipt
    let payload: Data
}

/// AddonRuntimeStorageAdapter refines the same single ingress slot with raw storage frames.
/// Staging owns a compact bounded copy under launch capacity; no response history is retained.
/// Publication and storage share one slot. Reject disposes only staged bytes; cancel/finish
/// require the successful taker's exact handle. Receipt applies only to accepted delivery,
/// never a runtime-only reservation. Stop/exit follow the base transport's synchronous rules.
protocol AddonRuntimeStorageAdapter: AddonRuntimeAdapter {
    func takeStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data?
    func rejectStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    )
    func cancelStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    )
    func finishStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    )
}

/// RuntimeAssetIngressHandle identifies one raw asset frame in the shared typed ingress slot.
/// encodedBytes is checked before transfer and against the actual compact value after taking it.
/// sequence is strictly increasing per canonical connection; a request UUID grants no replay.
struct RuntimeAssetIngressHandle: Hashable, Sendable {
    let token       : UUID
    let incarnation : RuntimeIncarnation
    let encodedBytes: Int
    let sequence    : UInt64
}

/// RuntimeAssetReceipt binds one accepted asset reply to its host nonce and canonical connection.
struct RuntimeAssetReceipt: Equatable, Sendable {
    let token          : UUID
    let incarnation    : RuntimeIncarnation
    let connectionToken: UUID
    let sequence       : UInt64
    let requestID      : UUID
    let operation      : AssetTransferOperation
}

/// RuntimeAssetResponseDelivery retains encoded bytes only in prepaid adapter payload capacity.
struct RuntimeAssetResponseDelivery: Equatable, Sendable {
    let receipt: RuntimeAssetReceipt
    let payload: Data
}

/// AddonRuntimeAssetAdapter refines the same single ingress slot with raw asset frames.
/// Staging owns a compact bounded copy under launch capacity; no response history is retained.
/// Publication, storage and asset frames share one slot. Reject disposes only staged bytes;
/// cancel/finish require the successful taker's exact handle. Receipt applies only to accepted
/// delivery, never a runtime-only reservation. Stop/exit follow the base transport's rules.
protocol AddonRuntimeAssetAdapter: AddonRuntimeAdapter {
    func takeAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data?
    func rejectAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    )
    func cancelAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    )
    func finishAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    )
}

/// RuntimeConnection binds both independently minted component sessions to one incarnation.
struct RuntimeConnection: Sendable {
    let token                : UUID
    let incarnation          : RuntimeIncarnation
    let identity             : VerifiedAddonIdentity
    let digest               : String
    let publicationConnection: PublicationConnection
    let serviceSession       : ServiceSession
    let authorityRevision    : UInt64

    init(
        token                : UUID,
        incarnation          : RuntimeIncarnation,
        identity             : VerifiedAddonIdentity,
        digest               : String,
        publicationConnection: PublicationConnection,
        serviceSession       : ServiceSession,
        authorityRevision    : UInt64
    ) {
        self.token = token
        self.incarnation = incarnation
        self.identity = identity
        self.digest = digest
        self.publicationConnection = publicationConnection
        self.serviceSession = serviceSession
        self.authorityRevision = authorityRevision
    }
}

/// Dedicated service bodies share the incarnation's single ingress slot. Kind is
/// part of the exact claim; completion sequence belongs to publication, not consumer service.
enum RuntimeServiceIngressKind: Hashable, Sendable { case invocation, completion, control, sourceOutput }
struct RuntimeServiceIngressHandle: Hashable, Sendable {
    let token: UUID
    let incarnation: RuntimeIncarnation
    let encodedBytes: Int
    let sequence: UInt64
    let kind: RuntimeServiceIngressKind
}
enum RuntimeServiceReceiptKind: Equatable, Sendable {
    case consumerReply
    case providerInvocation(workID: UUID)
}
struct RuntimeServiceReceipt: Equatable, Sendable {
    let token: UUID
    let incarnation: RuntimeIncarnation
    let connectionToken: UUID
    let sequence: UInt64
    let requestID: UUID
    let kind: RuntimeServiceReceiptKind
}
struct RuntimeServiceDelivery: Equatable, Sendable {
    let receipt: RuntimeServiceReceipt
    let payload: Data
}
/// One scalar settlement withdraws an admitted consumer route without disclosing history.
struct RuntimeServiceSettlement: Equatable, Sendable {
    let routeID: UUID
    let incarnation: RuntimeIncarnation
    let connectionToken: UUID
    let sequence: UInt64
}
protocol AddonRuntimeServiceAdapter: AddonRuntimeAdapter {
    func takeServiceIngress(_ handle: RuntimeServiceIngressHandle, incarnation: RuntimeIncarnation) -> Data?
    func rejectServiceIngress(_ handle: RuntimeServiceIngressHandle, incarnation: RuntimeIncarnation)
    func cancelServiceIngress(_ handle: RuntimeServiceIngressHandle, incarnation: RuntimeIncarnation)
    func finishServiceIngress(_ handle: RuntimeServiceIngressHandle, incarnation: RuntimeIncarnation)
    /// Synchronous disposal and terminal physical settlement, including revoked transport.
    func settleServiceExchange(_ settlement: RuntimeServiceSettlement)
}

/// Cumulative subscription transport uses the same physical ingress/delivery slots.
/// Receipts release staging before SDK event handlers run; handoff never calls user code.
protocol AddonRuntimeServiceSubscriptionAdapter: AddonRuntimeServiceAdapter {}

enum RuntimeServiceSubscriptionReceiptKind: Equatable, Sendable {
    case control(requestID: UUID, kind: ServiceControlKind, phase: ServiceControlPhase)
    case sourceStart(sourceID: UUID, startNonce: UUID)
    case event(subscriptionID: UUID, bindingRevision: UInt64, cacheRevision: UInt64)
}
struct RuntimeServiceSubscriptionReceipt: Equatable, Sendable {
    let token: UUID
    let incarnation: RuntimeIncarnation
    let connectionToken: UUID
    let sequence: UInt64
    let kind: RuntimeServiceSubscriptionReceiptKind
}
struct RuntimeServiceSubscriptionDelivery: Equatable, Sendable {
    let receipt: RuntimeServiceSubscriptionReceipt
    let payload: Data
}
enum RuntimeServiceSourceOutputResult: Equatable, Sendable {
    case accepted
    case refused(AddonFailure.Code)
}
