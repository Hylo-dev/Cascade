//
//  RecordingRuntimeAdapter.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class RecordingRuntimeAdapter: AddonRuntimeStorageAdapter, AddonRuntimeAssetAdapter, @unchecked Sendable {

    private enum IngressValue {

        case publication(RuntimeIngressHandle, ProviderOutput)
        case storage    (RuntimeStorageIngressHandle, Data)
        case asset      (RuntimeAssetIngressHandle, Data)
    }

    private struct IngressSlot {

        let value        : IngressValue
        var isTransferred = false
    }

    private var ingressSlots     : [RuntimeIncarnation: IngressSlot] = [:]
    private var ingressCapacities: [RuntimeIncarnation: (publication: Int, storage: Int, asset: Int, delivery: Int)] = [:]

    var rejectStorageReplies = false

    /// rejectedAssetOperations forces the bounded adapter to refuse the handoff of an exact asset
    /// reply operation, so tests can exercise the runtime's real rollback of a committed transfer
    /// or alias. It is test support only: the production handoff path is never bypassed.
    var rejectedAssetOperations: Set<AssetTransferOperation> = []

    private(set) var deliveryReceiptCount = 0

    private var dataSlots               : [RuntimeIncarnation: RuntimeAdapterDelivery] = [:]
    private var starts                  : [AddonID: RuntimeStartDelivery] = [:]
    private var liveIncarnations        : Set<RuntimeIncarnation> = []
    private var startAttemptCounts      : [AddonID: Int] = [:]
    private var startOrder              : [AddonID] = []
    private var stopCounts              : [RuntimeIncarnation: Int] = [:]
    private var stopReasons             : [RuntimeIncarnation: RuntimeStopReason] = [:]
    private var stopOrder               : [RuntimeIncarnation] = []
    private(set) var ingressTakeAttempts = 0
    private var serviceCount             = 0
    private var sourceCount              = 0
    private let rejectedStartOwners     : Set<AddonID>

    init(rejectedStartOwners: Set<AddonID> = []) {
        self.rejectedStartOwners = rejectedStartOwners
    }

    var lastAction: ActionDispatcher.Delivery? {
        dataSlots.values.compactMap { slot -> ActionDispatcher.Delivery? in
            guard case .action(let delivery) = slot else { return nil }

            return delivery
        }.first
    }

    var serviceDeliveryCount: Int { serviceCount }

    var sourceDeliveryCount: Int { sourceCount }

    func lastStart(owner: AddonID) -> RuntimeStartDelivery? {
        starts[owner]
    }

    func startCount(owner: AddonID) -> Int {
        startAttemptCounts[owner, default: 0]
    }

    var startOwners: [AddonID] { startOrder }

    /// ingressIsTransferred reads only the current typed slot, without retaining history.
    func ingressIsTransferred(_ handle: RuntimeIngressHandle) -> Bool {
        guard let slot = ingressSlots[handle.incarnation],
              case .publication(let current, _) = slot.value
        else { return false }

        return current == handle && slot.isTransferred
    }

    func storageIngressIsTransferred(_ handle: RuntimeStorageIngressHandle) -> Bool {
        guard let slot = ingressSlots[handle.incarnation],
              case .storage(let current, _) = slot.value
        else { return false }

        return current == handle && slot.isTransferred
    }

    func assetIngressIsTransferred(_ handle: RuntimeAssetIngressHandle) -> Bool {
        guard let slot = ingressSlots[handle.incarnation],
              case .asset(let current, _) = slot.value
        else { return false }

        return current == handle && slot.isTransferred
    }

    func hasIngress(incarnation: RuntimeIncarnation) -> Bool { ingressSlots[incarnation] != nil }

    func currentDelivery(incarnation: RuntimeIncarnation) -> RuntimeAdapterDelivery? {
        dataSlots[incarnation]
    }

    func stageIngress(
        _ output    : ProviderOutput,
        incarnation : RuntimeIncarnation,
        maximumBytes: Int = .max
    ) -> RuntimeIngressHandle? {
        guard liveIncarnations.contains(incarnation),
              ingressSlots[incarnation] == nil,
              let capacity = ingressCapacities[incarnation],
              let bytes    = try? JSONEncoder().encode(output).count,
              bytes <= min(capacity.publication, maximumBytes)
        else { return nil }

        let handle = RuntimeIngressHandle(
            token           : UUID(),
            incarnation     : incarnation,
            encodedBytes    : bytes,
            isCompletionOnly: output.completion != nil && output.publications.isEmpty && output.operations.isEmpty
        )
        ingressSlots[incarnation] = IngressSlot(value: .publication(handle, output))

        return handle
    }

    /// stageStorageIngress compacts caller bytes only after the launch's prepaid count guard.
    /// advertisedBytes is a bounded fixture fault, allowing a real count-mismatch refusal test.
    func stageStorageIngress(
        _ raw          : Data,
        incarnation    : RuntimeIncarnation,
        sequence       : UInt64,
        advertisedBytes: Int? = nil
    ) -> RuntimeStorageIngressHandle? {
        guard liveIncarnations.contains(incarnation),
              ingressSlots[incarnation] == nil,
              let capacity = ingressCapacities[incarnation],
              raw.count <= capacity.storage,
              capacity.storage > 0
        else { return nil }

        let handle = RuntimeStorageIngressHandle(
            token       : UUID(),
            incarnation : incarnation,
            encodedBytes: advertisedBytes ?? raw.count,
            sequence    : sequence
        )
        let compact = raw.withUnsafeBytes { Data($0) }
        ingressSlots[incarnation] = IngressSlot(value: .storage(handle, compact))

        return handle
    }

    func takeIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> ProviderOutput? {
        if ingressTakeAttempts < Int.max { ingressTakeAttempts += 1 }
        guard var slot = ingressSlots[incarnation],
              !slot.isTransferred,
              case .publication(let current, let output) = slot.value,
              current == handle
        else { return nil }

        slot.isTransferred        = true
        ingressSlots[incarnation] = slot
        return output
    }

    func takeStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data? {
        if ingressTakeAttempts < Int.max { ingressTakeAttempts += 1 }
        guard var slot = ingressSlots[incarnation],
              !slot.isTransferred,
              case .storage(let current, let raw) = slot.value,
              current == handle
        else { return nil }

        slot.isTransferred        = true
        ingressSlots[incarnation] = slot
        return raw
    }

    /// stageAssetIngress compacts caller bytes only after the launch's prepaid count guard.
    /// advertisedBytes is a bounded fixture fault, allowing a real count-mismatch refusal test.
    func stageAssetIngress(
        _ raw          : Data,
        incarnation    : RuntimeIncarnation,
        sequence       : UInt64,
        advertisedBytes: Int? = nil
    ) -> RuntimeAssetIngressHandle? {
        guard liveIncarnations.contains(incarnation),
              ingressSlots[incarnation] == nil,
              let capacity = ingressCapacities[incarnation],
              raw.count <= capacity.asset,
              capacity.asset > 0
        else { return nil }

        let handle = RuntimeAssetIngressHandle(
            token       : UUID(),
            incarnation : incarnation,
            encodedBytes: advertisedBytes ?? raw.count,
            sequence    : sequence
        )
        let compact = raw.withUnsafeBytes { Data($0) }
        ingressSlots[incarnation] = IngressSlot(value: .asset(handle, compact))

        return handle
    }

    func takeAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data? {
        if ingressTakeAttempts < Int.max { ingressTakeAttempts += 1 }
        guard var slot = ingressSlots[incarnation],
              !slot.isTransferred,
              case .asset(let current, let raw) = slot.value,
              current == handle
        else { return nil }

        slot.isTransferred        = true
        ingressSlots[incarnation] = slot
        return raw
    }

    func rejectIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        guard let slot = ingressSlots[incarnation],
              !slot.isTransferred,
              case .publication(let current, _) = slot.value,
              current == handle
        else { return }

        ingressSlots.removeValue(forKey: incarnation)
    }

    func cancelIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        guard let slot = ingressSlots[incarnation],
              slot.isTransferred,
              case .publication(let current, _) = slot.value,
              current == handle
        else { return }

        ingressSlots.removeValue(forKey: incarnation)
    }

    func finishIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        cancelIngress(handle, incarnation: incarnation)
    }

    func rejectStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        guard let slot = ingressSlots[incarnation],
              !slot.isTransferred,
              case .storage(let current, _) = slot.value,
              current == handle
        else { return }

        ingressSlots.removeValue(forKey: incarnation)
    }

    func cancelStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        guard let slot = ingressSlots[incarnation],
              slot.isTransferred,
              case .storage(let current, _) = slot.value,
              current == handle
        else { return }

        ingressSlots.removeValue(forKey: incarnation)
    }

    func finishStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        cancelStorageIngress(handle, incarnation: incarnation)
    }

    func rejectAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        guard let slot = ingressSlots[incarnation],
              !slot.isTransferred,
              case .asset(let current, _) = slot.value,
              current == handle
        else { return }

        ingressSlots.removeValue(forKey: incarnation)
    }

    func cancelAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        guard let slot = ingressSlots[incarnation],
              slot.isTransferred,
              case .asset(let current, _) = slot.value,
              current == handle
        else { return }

        ingressSlots.removeValue(forKey: incarnation)
    }

    func finishAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        cancelAssetIngress(handle, incarnation: incarnation)
    }

    func tryHandoff(
        incarnation: RuntimeIncarnation,
        delivery   : RuntimeAdapterDelivery
    ) -> RuntimeHandoffResult {
        if case .start(let start) = delivery {
            let owner    = start.identity.addonID
            let attempts = startAttemptCounts[owner, default: 0]
            if attempts < Int.max { startAttemptCounts[owner] = attempts + 1 }
            if startOrder.count < 32 { startOrder.append(owner) }
            guard !rejectedStartOwners.contains(start.identity.addonID) else {
                return .rejectedBeforeHandoff
            }

            starts[start.identity.addonID] = start
            liveIncarnations.insert(incarnation)
            ingressCapacities[incarnation] = (
                start.maximumIngressBytes,
                start.maximumStorageIngressBytes,
                start.maximumAssetIngressBytes,
                start.maximumDeliveryBytes
            )
            return .accepted
        }

        guard liveIncarnations.contains(incarnation), dataSlots[incarnation] == nil else {
            return .rejectedBeforeHandoff
        }

        if case .storageResponse(let response) = delivery {
            guard !rejectStorageReplies,
                  response.receipt.incarnation == incarnation,
                  response.payload.count <= (ingressCapacities[incarnation]?.delivery ?? 0)
            else { return .rejectedBeforeHandoff }
        }

        if case .assetResponse(let response) = delivery {
            guard !rejectedAssetOperations.contains(response.receipt.operation),
                  response.receipt.incarnation == incarnation,
                  response.payload.count <= (ingressCapacities[incarnation]?.delivery ?? 0)
            else { return .rejectedBeforeHandoff }
        }

        dataSlots[incarnation] = delivery
        if case .service = delivery { serviceCount += 1 }
        if case .source = delivery { sourceCount += 1 }
        return .accepted
    }

    func requestStop(
        incarnation: RuntimeIncarnation,
        reason     : RuntimeStopReason
    ) {
        stopReasons[incarnation] = reason
        if stopCounts[incarnation] == nil {
            if stopOrder.count == 32, let retired = stopOrder.first {
                stopOrder.removeFirst()
                stopCounts.removeValue(forKey: retired)
                stopReasons.removeValue(forKey: retired)
            }

            stopOrder.append(incarnation)
        }

        let count = stopCounts[incarnation, default: 0]
        if count < Int.max { stopCounts[incarnation] = count + 1 }

        dataSlots.removeValue(forKey: incarnation)
        ingressSlots.removeValue(forKey: incarnation)
        ingressCapacities.removeValue(forKey: incarnation)
        liveIncarnations.remove(incarnation)
    }

    func stopCount(incarnation: RuntimeIncarnation) -> Int {
        stopCounts[incarnation, default: 0]
    }

    func stopReason(incarnation: RuntimeIncarnation) -> RuntimeStopReason? {
        stopReasons[incarnation]
    }

    func deliveryWasReceived(incarnation: RuntimeIncarnation) {
        if deliveryReceiptCount < Int.max { deliveryReceiptCount += 1 }
        dataSlots.removeValue(forKey: incarnation)
    }

    func processDidExit(incarnation: RuntimeIncarnation) {
        dataSlots.removeValue(forKey: incarnation)
        ingressSlots.removeValue(forKey: incarnation)
        ingressCapacities.removeValue(forKey: incarnation)
        liveIncarnations.remove(incarnation)
    }
}
