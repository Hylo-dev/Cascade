//
//  StorageMessageAdapter.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// StorageMessageAdapter holds a single current incarnation with typed ingress and delivery;
/// all mutable access uses this lock. Capacity comes only from the real runtime's prepaid start
/// delivery. No receipt history/queue.
final class StorageMessageAdapter: AddonRuntimeStorageAdapter, AddonRuntimeAssetAdapter, @unchecked Sendable {

    private enum Handle: Equatable {

        case storage(RuntimeStorageIngressHandle)
        case asset(RuntimeAssetIngressHandle)
        case publication(RuntimeIngressHandle)
    }

    private enum Input {

        case storage(RuntimeStorageIngressHandle, Data)
        case asset(RuntimeAssetIngressHandle, Data)
        case publication(RuntimeIngressHandle, ProviderOutput)

        var handle: Handle {
            switch self {
                case .storage(let handle, _): .storage(handle)
                case .asset(let handle, _): .asset(handle)
                case .publication(let handle, _): .publication(handle)
            }
        }
    }

    private let lock        = NSLock()
    private var start      : RuntimeStartDelivery?
    private var stopped     = false
    private var input      : Input?
    private var transferred = false
    private var output     : RuntimeAdapterDelivery?
    private var reject      = false
    private var receipts    = 0
    private var takes       = 0
    private var stops       = 0

    var rejectReplies: Bool {
        get { lock.withLock { reject } }
        set { lock.withLock { reject = newValue } }
    }

    var incarnation: RuntimeIncarnation? { lock.withLock { start?.incarnation } }

    var receivedCount: Int { lock.withLock { receipts } }

    var takeCount: Int { lock.withLock { takes } }

    var stopCount: Int { lock.withLock { stops } }

    var hasIngress: Bool { lock.withLock { input != nil } }

    var reply: RuntimeStorageResponseDelivery? {
        lock.withLock {
            if case .storageResponse(let value) = output { return value }
            return nil
        }
    }

    func stage(
        _ bytes    : Data,
        sequence   : UInt64,
        incarnation: RuntimeIncarnation
    ) -> RuntimeStorageIngressHandle? {
        lock.withLock {
            guard let start,
                  incarnation == start.incarnation,
                  !stopped,
                  input == nil,
                  !bytes.isEmpty,
                  bytes.count <= start.maximumStorageIngressBytes
            else { return nil }

            let handle = RuntimeStorageIngressHandle(
                token       : UUID(),
                incarnation : start.incarnation,
                encodedBytes: bytes.count,
                sequence    : sequence
            )
            input       = .storage(handle, bytes.withUnsafeBytes { Data($0) })
            transferred = false

            return handle
        }
    }

    func stageAsset(
        _ bytes : Data,
        sequence: UInt64
    ) -> RuntimeAssetIngressHandle? {
        lock.withLock {
            guard let start,
                  !stopped,
                  input == nil,
                  !bytes.isEmpty,
                  bytes.count <= start.maximumAssetIngressBytes
            else { return nil }

            let handle = RuntimeAssetIngressHandle(
                token       : UUID(),
                incarnation : start.incarnation,
                encodedBytes: bytes.count,
                sequence    : sequence
            )
            input       = .asset(handle, bytes.withUnsafeBytes { Data($0) })
            transferred = false

            return handle
        }
    }

    func stagePublication(_ value: ProviderOutput) -> RuntimeIngressHandle? {
        lock.withLock {
            guard let start,
                  !stopped,
                  input == nil,
                  let count = try? JSONEncoder().encode(value).count,
                  count <= start.maximumIngressBytes
            else { return nil }

            let handle = RuntimeIngressHandle(
                token           : UUID(),
                incarnation     : start.incarnation,
                encodedBytes    : count,
                isCompletionOnly: false
            )
            input       = .publication(handle, value)
            transferred = false

            return handle
        }
    }

    func takeStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data? {
        lock.withLock {
            takes += 1
            guard incarnation == start?.incarnation,
                  !transferred,
                  case .storage(let current, let bytes) = input,
                  current == handle
            else { return nil }

            transferred = true

            return bytes
        }
    }

    func takeAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data? {
        lock.withLock {
            guard incarnation == start?.incarnation,
                  !transferred,
                  case .asset(let current, let bytes) = input,
                  current == handle
            else { return nil }

            transferred = true

            return bytes
        }
    }

    func takeIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> ProviderOutput? {
        lock.withLock {
            guard incarnation == start?.incarnation,
                  !transferred,
                  case .publication(let current, let value) = input,
                  current == handle
            else { return nil }

            transferred = true

            return value
        }
    }

    private func dispose(
        _ handle      : Handle,
        incarnation   : RuntimeIncarnation,
        wasTransferred: Bool
    ) {
        lock.withLock {
            guard incarnation == start?.incarnation,
                  input?.handle == handle,
                  transferred == wasTransferred
            else { return }

            input       = nil
            transferred = false
        }
    }

    func rejectStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .storage(handle),
            incarnation   : incarnation,
            wasTransferred: false
        )
    }

    func cancelStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .storage(handle),
            incarnation   : incarnation,
            wasTransferred: true
        )
    }

    func finishStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .storage(handle),
            incarnation   : incarnation,
            wasTransferred: true
        )
    }

    func rejectAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .asset(handle),
            incarnation   : incarnation,
            wasTransferred: false
        )
    }

    func cancelAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .asset(handle),
            incarnation   : incarnation,
            wasTransferred: true
        )
    }

    func finishAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .asset(handle),
            incarnation   : incarnation,
            wasTransferred: true
        )
    }

    func rejectIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .publication(handle),
            incarnation   : incarnation,
            wasTransferred: false
        )
    }

    func cancelIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .publication(handle),
            incarnation   : incarnation,
            wasTransferred: true
        )
    }

    func finishIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        dispose(
            .publication(handle),
            incarnation   : incarnation,
            wasTransferred: true
        )
    }

    func tryHandoff(
        incarnation: RuntimeIncarnation,
        delivery   : RuntimeAdapterDelivery
    ) -> RuntimeHandoffResult {
        lock.withLock {
            if case .start(let value) = delivery {
                guard start == nil, incarnation == value.incarnation else { return .rejectedBeforeHandoff }

                start   = value
                stopped = false
                return .accepted
            }

            guard let start, incarnation == start.incarnation, !stopped, output == nil else {
                return .rejectedBeforeHandoff
            }

            if case .storageResponse(let value) = delivery {
                guard !reject,
                      value.receipt.incarnation == incarnation,
                      value.payload.count <= start.maximumDeliveryBytes
                else { return .rejectedBeforeHandoff }
            }

            output = delivery

            return .accepted
        }
    }

    func requestStop(
        incarnation: RuntimeIncarnation,
        reason     : RuntimeStopReason
    ) {
        lock.withLock {
            guard incarnation == start?.incarnation, !stopped else { return }

            stops += 1
            stopped = true
            input   = nil
            output  = nil
        }
    }

    func deliveryWasReceived(incarnation: RuntimeIncarnation) {
        lock.withLock {
            guard incarnation == start?.incarnation else { return }

            receipts += 1
            output = nil
        }
    }

    func discardTransportReply(incarnation: RuntimeIncarnation) {
        lock.withLock {
            if incarnation == start?.incarnation { output = nil }
            // This is buffer disposal, not a receipt or a release of runtime credit/quota.
        }
    }

    func processDidExit(incarnation: RuntimeIncarnation) {
        lock.withLock {
            guard incarnation == start?.incarnation else { return }

            input  = nil
            output = nil
            start  = nil
        }
    }
}
