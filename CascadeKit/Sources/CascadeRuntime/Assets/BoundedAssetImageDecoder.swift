//
//  BoundedAssetImageDecoder.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

#if DEBUG
/// AssetLifecycleTestObserver observes real operations; it cannot supply authorization,
/// reservations, decoded pixels or refund decisions. Task-local scope also covers both
/// runtime assembler construction paths without mutable per-runtime test configuration.
protocol AssetLifecycleTestObserver: Sendable {
    var governor: ResourceGovernor { get }
    func admittedTransfer(reservationID: UUID, binding: AssetTransferBinding) async
    func decodeEntered()
    func decodeReservationEntered()
    func nativeDrawCompleted()
    func nativeScopeReturned()
    func aliasCommitted()
}

enum AssetLifecycleTesting {
    @TaskLocal static var observer: (any AssetLifecycleTestObserver)?

    static func observer(for governor: ResourceGovernor) -> (any AssetLifecycleTestObserver)? {
        guard let observer, observer.governor === governor else { return nil }
        return observer
    }
}
#endif

/// AssetImageDecoding imports bounded encoded images for trusted host callers.
/// Accounting attribution does not authorize an addon to publish or read an asset.
protocol AssetImageDecoding: Sendable {
    var assetGovernor: ResourceGovernor { get }
    func decode(encoded: Data, owner: AddonID) async throws -> AssetRasterBacking
    func close()
}

/// BoundedAssetImageDecoder admits one operation before crossing an async worker boundary.
/// One instance belongs to the runtime, alongside its shared raster coordinator. Busy calls
/// fail immediately instead of retaining encoded Data in a per-image actor or dispatch queue.
/// The lock protects only constant-sized admission state; native work never holds it.
final class BoundedAssetImageDecoder: AssetImageDecoding, @unchecked Sendable {
    var assetGovernor: ResourceGovernor { coordinator.assetGovernor }

    static let maximumEncodedBytes = 1_024 * 1_024

    // Two encoded-sized allowances cover retained input and CFData bridging, 8 MB cover
    // decoded/normalized RGBA overlap, and 64 KiB cover admitted control work. The final
    // raster has a separate protected reservation. ImageIO's private allocations and
    // codec CPU are not a strict footprint or execution-time guarantee of this budget.
    private static let temporaryBytes = 2 * maximumEncodedBytes + 8_000_000 + 65_536

    private let lock = NSLock()
    private let coordinator: AssetDisposalCoordinator
    private let worker = NativeAssetImageWorker()
    private var busy = false
    private var closed = false

    init(coordinator: AssetDisposalCoordinator) { self.coordinator = coordinator }

    /// decode accounts for the accepted input lifetime; callers still own their original Data.
    /// Cancellation cannot interrupt a synchronous native codec, so admission stays occupied
    /// until that codec returns, all staging is released and the scoped reservation refunds.
    func decode(encoded: Data, owner: AddonID) async throws -> AssetRasterBacking {
#if DEBUG
        AssetLifecycleTesting.observer(for: assetGovernor)?.decodeEntered()
#endif
        try lock.withLock {
            try Task.checkCancellation()
            guard !closed else { throw Self.failure("The image decoder is closed.") }
            guard !busy else {
                throw AddonFailure(code: .rateLimited, reason: "The image decoder is busy.")
            }
            guard !encoded.isEmpty, encoded.count <= Self.maximumEncodedBytes else {
                throw Self.failure("Encoded images must contain at most one mebibyte.")
            }
            busy = true
        }
        defer { lock.withLock { busy = false } }
        let result = try await coordinator.assetGovernor.withAssetDecodeReservation(
            bytes: Self.temporaryBytes,
            owner: owner
        ) {
            try self.validateOperation()
#if DEBUG
            AssetLifecycleTesting.observer(for: self.assetGovernor)?.decodeReservationEntered()
#endif
            return try await self.worker.create(
                encoded    : encoded,
                owner      : owner,
                coordinator: self.coordinator,
                decoder    : self
            )
        }
        // The worker's scope has ended before staging refunds. Only the protected raster
        // may cross this final authority check, including a close during governor cleanup.
        try validateOperation()
        return result
    }

    /// close invalidates in-flight return authority without prematurely refunding live work.
    func close() { lock.withLock { closed = true } }

    /// validateOperation rejects cancellation or close across each native/actor boundary.
    func validateOperation() throws {
        try lock.withLock {
            try Task.checkCancellation()
            guard !closed else { throw Self.failure("The image decoder is closed.") }
        }
    }

    private static func failure(_ reason: String) -> AddonFailure {
        AddonFailure(code: .resourceDenied, reason: reason)
    }
}
