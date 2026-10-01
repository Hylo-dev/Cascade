//
//  InvocationMessageAdapter.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// InvocationMessageAdapter owns exactly one shared raw slot and one compact payload per
/// incarnation, paid by start.
/// Stops synchronously dispose payloads; runtime charges physical work until modeled exit.
final class InvocationMessageAdapter: AddonRuntimeServiceSubscriptionAdapter, AddonRuntimeStorageAdapter,
                                      AddonRuntimeAssetAdapter, @unchecked Sendable {

    private enum Input: Equatable {

        case service    (RuntimeServiceIngressHandle)
        case storage    (RuntimeStorageIngressHandle)
        case asset      (RuntimeAssetIngressHandle)
        case publication(RuntimeIngressHandle)
    }

    private struct Slot {

        let start                    : RuntimeStartDelivery
        var input                    : Input?
        var bytes                    : Data?
        var transferred               = false
        var output                   : RuntimeAdapterDelivery?
        var stopped                   = false
        var stopReason               : RuntimeStopReason?
        var serviceInvocationHandoffs = 0
        var finishedServiceIngresses  = 0
        var cancelledServiceIngresses = 0
    }

    let providerEvent = InvocationByteEvent()
    let consumerEvent = InvocationByteEvent()

    private let lock                = NSLock()
    private var slots              : [RuntimeIncarnation: Slot] = [:]
    private var startInventory     : [RuntimeStartDelivery] = []
    private var rejectedStartOwners: Set<AddonID> = []

    var rejectStartOwners: Set<AddonID> {
        get { lock.withLock { rejectedStartOwners } }
        set { lock.withLock { rejectedStartOwners = newValue } }
    }

    private var rejectProvider = false
    private var rejectReply    = false
    private var rejectControl  = false
    private var settlements   : [RuntimeServiceSettlement] = []

    var starts: [RuntimeStartDelivery] { lock.withLock { startInventory } }

    var settled: [RuntimeServiceSettlement] { lock.withLock { settlements } }

    func stopReason(_ incarnation: RuntimeIncarnation) -> RuntimeStopReason? {
        lock.withLock { slots[incarnation]?.stopReason }
    }

    var rejectProviderHandoff: Bool {
        get { lock.withLock { rejectProvider } }
        set { lock.withLock { rejectProvider = newValue } }
    }

    var rejectReplyHandoff: Bool {
        get { lock.withLock { rejectReply } }
        set { lock.withLock { rejectReply = newValue } }
    }

    var rejectControlHandoff: Bool {
        get { lock.withLock { rejectControl } }
        set { lock.withLock { rejectControl = newValue } }
    }

    func payload(_ incarnation: RuntimeIncarnation) -> RuntimeAdapterDelivery? {
        lock.withLock { slots[incarnation]?.output }
    }

    func hasIngress(_ incarnation: RuntimeIncarnation) -> Bool {
        lock.withLock { slots[incarnation]?.input != nil }
    }

    func serviceInvocationHandoffs(_ incarnation: RuntimeIncarnation) -> Int {
        lock.withLock { slots[incarnation]?.serviceInvocationHandoffs ?? 0 }
    }

    func finishedServiceIngresses(_ incarnation: RuntimeIncarnation) -> Int {
        lock.withLock { slots[incarnation]?.finishedServiceIngresses ?? 0 }
    }

    func cancelledServiceIngresses(_ incarnation: RuntimeIncarnation) -> Int {
        lock.withLock { slots[incarnation]?.cancelledServiceIngresses ?? 0 }
    }

    func stage(
        _ bytes        : Data,
        connection     : RuntimeConnection,
        sequence       : UInt64,
        kind           : RuntimeServiceIngressKind,
        advertisedBytes: Int? = nil
    ) -> RuntimeServiceIngressHandle? {
        lock.withLock {
            guard var slot = slots[connection.incarnation],
                  !slot.stopped,
                  slot.input == nil,
                  bytes.count <= slot.start.maximumIngressBytes
            else { return nil }

            let handle = RuntimeServiceIngressHandle(
                token       : UUID(),
                incarnation : connection.incarnation,
                encodedBytes: advertisedBytes ?? bytes.count,
                sequence    : sequence,
                kind        : kind
            )
            slot.input                    = .service(handle)
            slot.bytes                    = bytes.withUnsafeBytes { Data($0) }
            slot.transferred              = false
            slots[connection.incarnation] = slot
            return handle
        }
    }

    private func take(
        _ input    : Input,
        incarnation: RuntimeIncarnation
    ) -> Data? {
        lock.withLock {
            guard var slot = slots[incarnation], slot.input == input, !slot.transferred else { return nil }

            slot.transferred   = true
            slots[incarnation] = slot
            return slot.bytes
        }
    }

    private func dispose(
        _ input         : Input,
        incarnation     : RuntimeIncarnation,
        taken           : Bool,
        finishedService : Bool = false,
        cancelledService: Bool = false
    ) {
        lock.withLock {
            guard var slot = slots[incarnation], slot.input == input, slot.transferred == taken else { return }

            if finishedService { slot.finishedServiceIngresses += 1 }
            if cancelledService { slot.cancelledServiceIngresses += 1 }
            slot.input         = nil
            slot.bytes         = nil
            slot.transferred   = false
            slots[incarnation] = slot
        }
    }

    func takeServiceIngress(
        _ handle   : RuntimeServiceIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data? {
        take(.service(handle), incarnation: incarnation)
    }

    func rejectServiceIngress(
        _ handle   : RuntimeServiceIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .service(handle),
            incarnation: incarnation,
            taken      : false
        )
    }

    func cancelServiceIngress(
        _ handle   : RuntimeServiceIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .service(handle),
            incarnation     : incarnation,
            taken           : true,
            cancelledService: true
        )
    }

    func finishServiceIngress(
        _ handle   : RuntimeServiceIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .service(handle),
            incarnation    : incarnation,
            taken          : true,
            finishedService: true
        )
    }

    private func stageShared(
        _ bytes   : Data,
        input     : Input,
        connection: RuntimeConnection,
        cap       : Int
    ) -> Bool {
        lock.withLock {
            guard var slot = slots[connection.incarnation],
                  !slot.stopped,
                  slot.input == nil,
                  !bytes.isEmpty,
                  bytes.count <= cap
            else { return false }

            slot.input                    = input
            slot.bytes                    = bytes.withUnsafeBytes { Data($0) }
            slot.transferred              = false
            slots[connection.incarnation] = slot
            return true
        }
    }

    func stageStorage(
        _ bytes   : Data,
        connection: RuntimeConnection,
        sequence  : UInt64
    ) -> RuntimeStorageIngressHandle? {
        let handle = RuntimeStorageIngressHandle(
            token       : UUID(),
            incarnation : connection.incarnation,
            encodedBytes: bytes.count,
            sequence    : sequence
        )
        let cap = lock.withLock { slots[connection.incarnation]?.start.maximumStorageIngressBytes ?? 0 }

        return stageShared(bytes, input: .storage(handle), connection: connection, cap: cap) ? handle : nil
    }

    func stageAsset(
        _ bytes   : Data,
        connection: RuntimeConnection,
        sequence  : UInt64
    ) -> RuntimeAssetIngressHandle? {
        let handle = RuntimeAssetIngressHandle(
            token       : UUID(),
            incarnation : connection.incarnation,
            encodedBytes: bytes.count,
            sequence    : sequence
        )
        let cap = lock.withLock { slots[connection.incarnation]?.start.maximumAssetIngressBytes ?? 0 }

        return stageShared(bytes, input: .asset(handle), connection: connection, cap: cap) ? handle : nil
    }

    func stagePublication(
        _ value   : ProviderOutput,
        connection: RuntimeConnection
    ) throws -> RuntimeIngressHandle? {
        let bytes  = try JSONEncoder().encode(value)
        let handle = RuntimeIngressHandle(
            token           : UUID(),
            incarnation     : connection.incarnation,
            encodedBytes    : bytes.count,
            isCompletionOnly: value.completion != nil
        )
        let cap = lock.withLock { slots[connection.incarnation]?.start.maximumIngressBytes ?? 0 }

        return stageShared(bytes, input: .publication(handle), connection: connection, cap: cap) ? handle : nil
    }

    func settleServiceExchange(_ settlement: RuntimeServiceSettlement) {
        lock.withLock { settlements.append(settlement) }
        consumerEvent.signal()
    }

    func tryHandoff(
        incarnation: RuntimeIncarnation,
        delivery   : RuntimeAdapterDelivery
    ) -> RuntimeHandoffResult {
        lock.withLock {
            if case .start(let start) = delivery {
                guard !rejectedStartOwners.contains(start.identity.addonID), slots[incarnation] == nil else {
                    return .rejectedBeforeHandoff
                }

                slots[incarnation] = Slot(start: start)
                startInventory.append(start)
                return .accepted
            }

            guard var slot = slots[incarnation], !slot.stopped, slot.output == nil else {
                return .rejectedBeforeHandoff
            }

            if case .serviceInvocation = delivery, rejectProvider { return .rejectedBeforeHandoff }
            if case .serviceReply = delivery, rejectReply { return .rejectedBeforeHandoff }
            if case .serviceControl = delivery, rejectControl { return .rejectedBeforeHandoff }

            // Compact copies are paid by the single delivery slot, never queued.
            switch delivery {
                case .serviceInvocation(let received):
                    slot.serviceInvocationHandoffs += 1
                    slot.output = .serviceInvocation(RuntimeServiceDelivery(
                        receipt: received.receipt,
                        payload: received.payload.withUnsafeBytes { Data($0) }
                    ))

                case .serviceReply(let received):
                    slot.output = .serviceReply(RuntimeServiceDelivery(
                        receipt: received.receipt,
                        payload: received.payload.withUnsafeBytes { Data($0) }
                    ))

                case .storageResponse(let received):
                    slot.output = .storageResponse(RuntimeStorageResponseDelivery(
                        receipt: received.receipt,
                        payload: received.payload.withUnsafeBytes { Data($0) }
                    ))

                case .assetResponse(let received):
                    slot.output = .assetResponse(RuntimeAssetResponseDelivery(
                        receipt: received.receipt,
                        payload: received.payload.withUnsafeBytes { Data($0) }
                    ))

                default: slot.output = delivery
            }

            slots[incarnation] = slot
            if case .serviceInvocation = delivery { providerEvent.signal() }
            if case .serviceReply = delivery { consumerEvent.signal() }
            return .accepted
        }
    }

    func requestStop(
        incarnation: RuntimeIncarnation,
        reason     : RuntimeStopReason
    ) {
        lock.withLock {
            guard var slot = slots[incarnation] else { return }

            slot.stopReason    = reason
            slot.stopped       = true
            slot.input         = nil
            slot.bytes         = nil
            slot.output        = nil
            slot.transferred   = false
            slots[incarnation] = slot
        }
    }

    func deliveryWasReceived(incarnation: RuntimeIncarnation) {
        lock.withLock { slots[incarnation]?.output = nil }
    }

    func processDidExit(incarnation: RuntimeIncarnation) {
        lock.withLock { _ = slots.removeValue(forKey: incarnation) }
    }

    func takeIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> ProviderOutput? {
        guard let bytes = take(.publication(handle), incarnation: incarnation) else { return nil }

        return try? ProviderOutput.decode(bytes)
    }

    func rejectIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .publication(handle),
            incarnation: incarnation,
            taken      : false
        )
    }

    func cancelIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .publication(handle),
            incarnation: incarnation,
            taken      : true
        )
    }

    func finishIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .publication(handle),
            incarnation: incarnation,
            taken      : true
        )
    }

    func takeStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data? {
        take(.storage(handle), incarnation: incarnation)
    }

    func rejectStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .storage(handle),
            incarnation: incarnation,
            taken      : false
        )
    }

    func cancelStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .storage(handle),
            incarnation: incarnation,
            taken      : true
        )
    }

    func finishStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .storage(handle),
            incarnation: incarnation,
            taken      : true
        )
    }

    func takeAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data? {
        take(.asset(handle), incarnation: incarnation)
    }

    func rejectAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .asset(handle),
            incarnation: incarnation,
            taken      : false
        )
    }

    func cancelAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .asset(handle),
            incarnation: incarnation,
            taken      : true
        )
    }

    func finishAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .asset(handle),
            incarnation: incarnation,
            taken      : true
        )
    }
}
