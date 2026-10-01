//
//  AssetDisposalCoordinator.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AssetDisposalCoordinator is the one host-owned bridge per runtime. Its empty lock/control
/// object is host baseline state; every proportional slot, context and in-flight record is
/// admitted as 4096 bytes plus the governor's separate 1024-byte entry charge. Slots own only
/// accounting tokens, never images/providers/contexts.
final class AssetDisposalCoordinator: @unchecked Sendable {

    static let maximumSlots = (8 * 1_024 * 1_024) / (4_096 + 1_024)

    struct Status: Sendable {

        let slots      : Int
        let pending    : Int
        let faults     : Int
        let closed     : Bool
        let creating   : Bool
        let drainStarts: UInt64
    }

    fileprivate enum Phase {

        case live, pending, refunding, fault, retired
    }

    /// Slot is one individually allocated admitted record. Intrusive links avoid a dictionary/array
    /// retaining uncharged peak capacity after partial refunds. Weak backward and strong forward
    /// links make insertion/removal O(1), with no active-list scan, table copy or strong-link
    /// cycle. A drain borrows one strongly held node across the real refund; it unlinks and marks
    /// that same node retired under the lock before dropping its bounded local reference.
    final class Slot: @unchecked Sendable {

        fileprivate let token        : RetainedAssetToken
        fileprivate let coordinatorID: UUID
        fileprivate var phase        : Phase = .live
        fileprivate weak var previous: Slot?
        fileprivate var next         : Slot?
        fileprivate var pendingNext  : Slot?

        fileprivate init(
            token        : RetainedAssetToken,
            coordinatorID: UUID
        ) {
            self.token         = token
            self.coordinatorID = coordinatorID
        }
    }

    private let lock      = NSLock()
    private let access   : any AssetReservationAccess
    private let factory  : AssetRasterFactory
    private let slotLimit: Int
    private let identity  = UUID()

    private var first       : Slot?
    private var slotCount    = 0
    private var faultCount   = 0
    private var pendingCount = 0
    private var head        : Slot?
    private var tail        : Slot?
    private var refunding   : Slot?

    private var closed    = false
    private var creating  = false
    private var observing = false

    private var drain      : Task<Void, Never>?
    private var drainStarts: UInt64 = 0

    /// assetGovernor keeps decoder staging and retained pixels in the same canonical budget.
    var assetGovernor: ResourceGovernor { access.assetGovernor }

    init(
        governor    : ResourceGovernor,
        maximumSlots: Int = maximumSlots,
        construction: any AssetRasterConstruction = NativeAssetRasterConstruction()
    ) {
        self.access    = governor
        self.slotLimit = min(Self.maximumSlots, max(0, maximumSlots))
        self.factory   = AssetRasterFactory(construction: construction)
    }

    init(
        governor    : ResourceGovernor,
        access      : any AssetReservationAccess,
        maximumSlots: Int = maximumSlots,
        construction: any AssetRasterConstruction = NativeAssetRasterConstruction()
    ) throws {
        guard access.assetGovernor === governor else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "Raster accounting must use the runtime governor."
            )
        }

        self.access    = access
        self.slotLimit = min(Self.maximumSlots, max(0, maximumSlots))
        self.factory   = AssetRasterFactory(construction: construction)
    }

    func create(
        pixels: Data,
        width : Int,
        height: Int,
        owner : AddonID
    ) async throws -> AssetRasterBacking {
        try lock.withLock {
            try Task.checkCancellation()
            guard !closed else { throw Self.failure("The raster coordinator is closed.") }
            guard !creating else { throw Self.failure("Raster creation is busy.") }
            guard slotCount < slotLimit else { throw Self.failure("The raster slot budget is full.") }

            creating = true
        }
        defer { lock.withLock { creating = false } }

        let result = try await factory.create(
            pixels     : pixels,
            width      : width,
            height     : height,
            owner      : owner,
            coordinator: self,
            access     : access
        )

        // The allocation and CoreGraphics work have completed on the private
        // factory actor. This final synchronous authority check also covers the
        // return from that actor; cancellation after this boundary cannot refund
        // an image that has already escaped.
        return try lock.withLock {
            try Task.checkCancellation()
            guard !closed else { throw Self.failure("The raster coordinator is closed.") }

            return result
        }
    }

    func install(_ token: RetainedAssetToken) -> Slot {
        lock.withLock {
            // Creation is serialized, and no other operation inserts a slot.
            // Even a closed/cancelled admission MUST be recorded before cleanup.
            let slot        = Slot(token: token, coordinatorID: identity)
            slot.next       = first
            first?.previous = slot
            first           = slot
            slotCount += 1
            return slot
        }
    }

    func validateCreation() throws {
        try lock.withLock {
            try Task.checkCancellation()
            guard !closed else { throw Self.failure("The raster coordinator is closed.") }
        }
    }

    /// disposed queues a slot for refund. It is called only after the actual allocation has been
    /// freed, or after an admitted construction failed before any allocation existed.
    func disposed(_ slot: Slot) {
        lock.withLock {
            guard slot.coordinatorID == identity, slot.phase == .live else { return }

            slot.phase = .pending
            pendingCount += 1
            if let tail { tail.pendingNext = slot } else { head = slot }
            tail = slot
            scheduleLocked()
        }
    }

    private func scheduleLocked() {
        guard drain == nil, head != nil else { return }

        if drainStarts < UInt64.max { drainStarts += 1 }
        // One shared, cancellation-independent worker. Callbacks only link their
        // already-admitted slots; they create neither tasks nor queue entries
        // while this worker is scheduled. Never inherits a creator's cancellation.
        drain = Task.detached(priority: .utility) { await self.drainBatch() }
    }

    private func drainBatch() async {
        // Finite FIFO batch. New callbacks append behind existing pending work.
        // This makes a captured pending-watermark observable in at most two
        // bounded batches even with concurrent future producers.
        for _ in 0..<slotLimit {
            let item: Slot? = lock.withLock {
                guard let slot = head else { return nil }

                head = slot.pendingNext
                if head == nil { tail = nil }
                slot.pendingNext = nil
                slot.phase       = .refunding
                refunding        = slot
                return slot
            }
            guard let slot = item else { break }

            do {
                try await access.disposeRaster(slot.token)
                lock.withLock {
                    if let previous = slot.previous {
                        previous.next = slot.next
                    } else {
                        first = slot.next
                    }
                    slot.next?.previous = slot.previous
                    slot.previous       = nil
                    slot.next           = nil
                    slot.phase          = .retired
                    slotCount -= 1
                    pendingCount -= 1
                    refunding = nil
                }
            } catch {
                // Impossible canonical failures remain observable and charged.
                // No retry loop and no dropped record; unrelated queued disposal
                // is still allowed to progress once through the same batch.
                lock.withLock {
                    slot.phase = .fault
                    faultCount += 1
                    pendingCount -= 1
                    refunding = nil
                }
            }
        }

        lock.withLock {
            // Same lock as callback enqueue: no gap can lose a last callback.
            drain = nil
            scheduleLocked()
        }
    }

    func close() { lock.withLock { closed = true } }

    func status() -> Status {
        lock.withLock {
            Status(
                slots      : slotCount,
                pending    : pendingCount,
                faults     : faultCount,
                closed     : closed,
                creating   : creating,
                drainStarts: drainStarts
            )
        }
    }

    /// flushDisposed admits one observer at a time and fails fast rather than keeping an unbounded
    /// waiter list. Waits only for disposal already queued at entry, never for live images. At most
    /// two finite FIFO batches cover that watermark. Governor suspension can delay it; this is an
    /// async barrier, never a blocking MainActor wait.
    func flushDisposed() async throws {
        let target: Slot? = try lock.withLock {
            guard !observing else { throw Self.failure("Raster disposal observation is busy.") }
            guard faultCount == 0 else {
                throw Self.failure("A raster refund fault requires host attention.")
            }

            observing = true
            return tail ?? refunding
        }
        defer { lock.withLock { observing = false } }
        guard let target else { return }

        for _ in 0..<2 {
            let worker = lock.withLock { drain }
            await worker?.value
            let complete = try lock.withLock {
                guard faultCount == 0 else {
                    throw Self.failure("A raster refund fault requires host attention.")
                }

                return target.phase == .retired
            }
            if complete { return }
        }

        throw Self.failure("The bounded raster disposal barrier did not complete.")
    }

    private static func failure(_ reason: String) -> AddonFailure {
        AddonFailure(code: .resourceDenied, reason: reason)
    }
}
