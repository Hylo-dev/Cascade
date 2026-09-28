//
//  AssetRasterBackingTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AssetRasterBackingTests {
    let owner = AddonID(rawValue: "com.example.raster")!
    let pixels = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0])

    @Test func lastRealImageReferenceOwnsPixelsAndCharges() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var backing: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        var first: CGImage? = backing?.image
        var second: CGImage? = first
        #expect(first?.width == 2)
        #expect(first?.height == 2)
        #expect(first?.bytesPerRow == 8)
        #expect(first?.bitsPerPixel == 32)
        backing = nil
        first = nil
        #expect(await governor.usage(.assetBytes) == 16)
        #expect(await governor.usage(.admittedMemoryBytes) == 4_112)
        #expect(second?.dataProvider?.data as Data? == pixels)
        second = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 0)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func closeKeepsLiveImageAndEventuallyBreaksCoordinatorRetention() async throws {
        let governor = ResourceGovernor()
        var coordinator: AssetDisposalCoordinator? = AssetDisposalCoordinator(governor: governor)
        weak let weakCoordinator = coordinator
        var backing: AssetRasterBacking? = try await coordinator!.create(pixels: pixels, width: 2, height: 2, owner: owner)
        var image: CGImage? = backing?.image
        backing = nil
        coordinator!.close()
        await #expect(throws: AddonFailure.self) { try await coordinator!.create(pixels: pixels, width: 2, height: 2, owner: owner) }
        coordinator = nil
        #expect(weakCoordinator != nil)
        #expect(image?.width == 2)
        #expect(await governor.usage(.assetBytes) == 16)
        image = nil
        try await weakCoordinator?.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 0)
        #expect(weakCoordinator == nil)
    }
}

private actor RasterGate {
    private var entered = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        arrival?.resume()
        arrival = nil
        if !released { await withCheckedContinuation { waiter = $0 } }
    }
    func reached() async {
        if !entered { await withCheckedContinuation { arrival = $0 } }
    }
    func open() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}

private actor RasterAccess: AssetReservationAccess {
    nonisolated let assetGovernor: ResourceGovernor
    var admissionGate: RasterGate?
    var refundGate: RasterGate?
    var failRefund = false
    private(set) var lastToken: RetainedAssetToken?
    private(set) var admissions = 0
    private(set) var refunds = 0
    init(_ governor: ResourceGovernor, admission: RasterGate? = nil,
         refund: RasterGate? = nil, failRefund: Bool = false) {
        assetGovernor = governor
        admissionGate = admission
        refundGate = refund
        self.failRefund = failRefund
    }
    func reserveRaster(bytes: Int, owner: AddonID) async throws -> RetainedAssetToken {
        let result = try await assetGovernor.admitRetainedAsset(bytes: bytes, owner: owner)
        lastToken = result
        admissions += 1
        if let gate = admissionGate { admissionGate = nil; await gate.pause() }
        return result
    }
    func disposeRaster(_ token: RetainedAssetToken) async throws {
        refunds += 1
        if let gate = refundGate { refundGate = nil; await gate.pause() }
        if failRefund { throw AddonFailure(code: .resourceDenied, reason: "Injected before the real refund.") }
        try await assetGovernor.completeRetainedAsset(token, owner: token.reservation.owner)
    }
}

private final class RasterConstruction: AssetRasterConstruction, @unchecked Sendable {
    enum Boundary: CaseIterable { case allocate, providerBefore, providerAfter, colorSpace, image }
    private let lock = NSLock()
    private let native = NativeAssetRasterConstruction()
    let fail: Boundary?
    let cancel: Boundary?
    private var allocated = 0
    private var freed = 0
    private var allocatedOnMain = false
    init(fail: Boundary? = nil, cancel: Boundary? = nil) { self.fail = fail; self.cancel = cancel }
    var counts: (allocated: Int, freed: Int, onMain: Bool) {
        lock.withLock { (allocated, freed, allocatedOnMain) }
    }
    private func visit(_ boundary: Boundary) {
        if cancel == boundary { withUnsafeCurrentTask { $0?.cancel() } }
    }
    func allocate(bytes: Int) -> UnsafeMutableRawPointer? {
        visit(.allocate)
        if fail == .allocate { return nil }
        let result = native.allocate(bytes: bytes)
        if result != nil {
            lock.withLock { allocated += 1; allocatedOnMain = allocatedOnMain || Thread.isMainThread }
        }
        return result
    }
    func deallocate(_ pointer: UnsafeMutableRawPointer, bytes: Int) {
        native.deallocate(pointer, bytes: bytes)
        lock.withLock { freed += 1 }
    }
    func provider(context: AssetRasterProviderContext) -> CGDataProvider? {
        visit(.providerBefore)
        if fail == .providerBefore { return nil }
        let result = native.provider(context: context)
        visit(.providerAfter)
        if fail == .providerAfter { return nil } // Real provider final callback, never a fabricated info pointer.
        return result
    }
    func colorSpace() -> CGColorSpace? {
        visit(.colorSpace)
        return fail == .colorSpace ? nil : native.colorSpace()
    }
    func image(layout: AssetRasterLayout, provider: CGDataProvider, colorSpace: CGColorSpace) -> CGImage? {
        visit(.image)
        return fail == .image ? nil : native.image(layout: layout, provider: provider, colorSpace: colorSpace)
    }
}

extension AssetRasterBackingTests {
    @Test func invalidLayoutsRejectBeforeAnyDestinationAllocation() async throws {
        let governor = ResourceGovernor()
        let construction = RasterConstruction()
        let coordinator = AssetDisposalCoordinator(governor: governor, construction: construction)
        for (width, height, bytes) in [(0, 2, 16), (-2, 2, 16), (2, -2, 16),
                                      (Int.max, 2, 16), (Int.max / 2, 1, 16),
                                      (1_001, 1_000, 16), (2, 2, 15), (2, 2, 17)] {
            await #expect(throws: AddonFailure.self) {
                try await coordinator.create(pixels: Data(count: bytes), width: width, height: height, owner: owner)
            }
        }
        #expect(construction.counts.allocated == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(coordinator.status().slots == 0)
        var maximum: AssetRasterBacking? = try await coordinator.create(
            pixels: Data(count: 4_000_000), width: 1_000, height: 1_000, owner: owner)
        #expect(maximum?.image.width == 1_000)
        #expect(await governor.usage(.assetBytes) == 4_000_000)
        maximum = nil
        try await coordinator.flushDisposed()
        #expect(construction.counts.allocated == 1)
        #expect(construction.counts.freed == 1)
    }

    @Test @MainActor func allocationAndNativeConstructionLeaveMainActor() async throws {
        let governor = ResourceGovernor()
        let construction = RasterConstruction()
        let coordinator = AssetDisposalCoordinator(governor: governor, construction: construction)
        var backing: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        #expect(backing?.image.alphaInfo == .premultipliedLast)
        #expect(backing?.image.colorSpace?.name == CGColorSpace.sRGB)
        #expect(construction.counts.allocated == 1)
        #expect(!construction.counts.onMain)
        backing = nil
        try await coordinator.flushDisposed()
        #expect(construction.counts.freed == 1)
    }

    @Test func replacingHolderKeepsOldImageChargedUntilItsLastReference() async throws {
        let governor = ResourceGovernor()
        let construction = RasterConstruction()
        let coordinator = AssetDisposalCoordinator(governor: governor, construction: construction)
        var holder: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        var old: CGImage? = holder?.image
        holder = try await coordinator.create(pixels: Data(repeating: 0, count: 16), width: 2, height: 2, owner: owner)
        #expect(await governor.usage(.assetBytes) == 32)
        #expect(construction.counts.freed == 0)
        #expect(old?.dataProvider?.data as Data? == pixels)
        old = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 16)
        #expect(construction.counts.freed == 1)
        #expect(holder?.image.width == 2)
        holder = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(construction.counts.freed == 2)
    }

    @Test func constructionFailuresDisposeRealAllocationsAndRefundExactlyOnce() async throws {
        for boundary in RasterConstruction.Boundary.allCases {
            let governor = ResourceGovernor()
            let construction = RasterConstruction(fail: boundary)
            let access = RasterAccess(governor)
            let coordinator = try AssetDisposalCoordinator(governor: governor, access: access, construction: construction)
            await #expect(throws: AddonFailure.self) {
                try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
            }
            try await coordinator.flushDisposed()
            let count = boundary == .allocate ? 0 : 1
            #expect(construction.counts.allocated == count)
            #expect(construction.counts.freed == count)
            #expect(await access.admissions == 1)
            #expect(await access.refunds == 1)
            #expect(await governor.usage(.assetBytes) == 0)
            #expect(await governor.usage(.admittedMemoryBytes) == 0)
            #expect(await governor.usage(.retainedStateBytes) == 0)
            #expect(coordinator.status().slots == 0)
        }
    }

    @Test func cancellationAtEveryOwnershipBoundaryDisposesOnce() async throws {
        for boundary in RasterConstruction.Boundary.allCases {
            let governor = ResourceGovernor()
            let construction = RasterConstruction(cancel: boundary)
            let coordinator = AssetDisposalCoordinator(governor: governor, construction: construction)
            let task = Task { try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
            await #expect(throws: CancellationError.self) { try await task.value }
            try await coordinator.flushDisposed()
            #expect(construction.counts.allocated == 1)
            #expect(construction.counts.freed == 1)
            #expect(await governor.usage(.assetBytes) == 0)
            #expect(await governor.usage(.retainedStateBytes) == 0)
        }
    }

    @Test func delayedAdmissionRecordsThenRefundsCancelledOrClosedCreation() async throws {
        for closes in [false, true] {
            let governor = ResourceGovernor()
            let gate = RasterGate()
            let access = RasterAccess(governor, admission: gate)
            let construction = RasterConstruction()
            let coordinator = try AssetDisposalCoordinator(governor: governor, access: access, construction: construction)
            let task = Task { try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
            await gate.reached()
            #expect(await governor.usage(.assetBytes) == 16)
            #expect(construction.counts.allocated == 0)
            await #expect(throws: AddonFailure.self) { try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
            if closes { coordinator.close() } else { task.cancel() }
            await gate.open()
            if closes {
                await #expect(throws: AddonFailure.self) { try await task.value }
            } else {
                await #expect(throws: CancellationError.self) { try await task.value }
            }
            try await coordinator.flushDisposed()
            #expect(await access.admissions == 1)
            #expect(await access.refunds == 1)
            #expect(construction.counts.allocated == 0)
            #expect(await governor.usage(.retainedStateBytes) == 0)
        }
    }

    @Test func cancellationAfterSuccessfulReturnCannotRefundLiveImage() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var task: Task<AssetRasterBacking, Error>? = Task {
            try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        }
        var backing: AssetRasterBacking? = try await task!.value
        task!.cancel()
        #expect(await governor.usage(.assetBytes) == 16)
        #expect(backing?.image.width == 2)
        task = nil
        backing = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 0)
    }

    @Test func delayedRefundKeepsDisposedBufferChargeAndBoundedSlot() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 5_120))
        let gate = RasterGate()
        let access = RasterAccess(governor, refund: gate)
        let construction = RasterConstruction()
        let coordinator = try AssetDisposalCoordinator(governor: governor, access: access, construction: construction)
        var backing: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        #expect(backing?.image.width == 2)
        backing = nil
        await gate.reached()
        #expect(construction.counts.freed == 1)
        #expect(await governor.usage(.assetBytes) == 16)
        #expect(await governor.usage(.admittedMemoryBytes) == 4_112)
        #expect(await governor.usage(.retainedStateBytes) == 5_120)
        #expect(coordinator.status().pending == 1)
        await #expect(throws: AddonFailure.self) { try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
        #expect(construction.counts.allocated == 1)
        await gate.open()
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(coordinator.status().slots == 0)
    }

    @Test func callbacksDuringLastRefundUseSameDrainAndNoWakeupIsLost() async throws {
        let governor = ResourceGovernor()
        let gate = RasterGate()
        let access = RasterAccess(governor, refund: gate)
        let coordinator = try AssetDisposalCoordinator(governor: governor, access: access)
        var first: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        var second: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        #expect(first?.image.width == second?.image.width)
        first = nil
        await gate.reached()
        #expect(coordinator.status().drainStarts == 1)
        second = nil
        #expect(coordinator.status().pending == 2)
        #expect(coordinator.status().drainStarts == 1)
        await gate.open()
        try await coordinator.flushDisposed()
        #expect(await access.refunds == 2)
        #expect(coordinator.status().drainStarts == 1)
        #expect(coordinator.status().slots == 0)
        var third: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        #expect(third?.image.width == 2)
        third = nil
        try await coordinator.flushDisposed()
        #expect(await access.refunds == 3)
        #expect(coordinator.status().drainStarts == 2)
    }

    @Test func impossibleRefundFaultPreservesChargeWithoutRetryLoop() async throws {
        let governor = ResourceGovernor()
        let access = RasterAccess(governor, failRefund: true)
        let construction = RasterConstruction()
        let coordinator = try AssetDisposalCoordinator(governor: governor, access: access, construction: construction)
        var backing: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        #expect(backing?.image.width == 2)
        backing = nil
        await #expect(throws: AddonFailure.self) { try await coordinator.flushDisposed() }
        #expect(await access.refunds == 1)
        #expect(construction.counts.freed == 1)
        #expect(coordinator.status().faults == 1)
        #expect(coordinator.status().slots == 1)
        #expect(await governor.usage(.assetBytes) == 16)
        #expect(await governor.usage(.retainedStateBytes) == 5_120)
        await #expect(throws: AddonFailure.self) { try await coordinator.flushDisposed() }
        #expect(await access.refunds == 1)
    }

    @Test func metadataAndHostSlotLimitsRejectBeforeAllocation() async throws {
        for limit in [0, 1] {
            let governor = ResourceGovernor()
            let construction = RasterConstruction()
            let coordinator = AssetDisposalCoordinator(governor: governor, maximumSlots: limit, construction: construction)
            var held: AssetRasterBacking?
            if limit == 1 { held = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
            await #expect(throws: AddonFailure.self) { try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
            #expect(construction.counts.allocated == limit)
            #expect(coordinator.status().slots == limit)
            #expect(held?.image.width == (limit == 1 ? 2 : nil))
            held = nil
            try await coordinator.flushDisposed()
            #expect(await governor.usage(.retainedStateBytes) == 0)
        }
        #expect(AssetDisposalCoordinator.maximumSlots == 1_638)
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 5_119))
        let construction = RasterConstruction()
        let coordinator = AssetDisposalCoordinator(governor: governor, construction: construction)
        await #expect(throws: AddonFailure.self) { try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
        #expect(construction.counts.allocated == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func aggregateOwnerAndGlobalMemoryDenialPrecedesRasterAllocation() async throws {
        for global in [false, true] {
            let governor = ResourceGovernor()
            let construction = RasterConstruction()
            let coordinator = AssetDisposalCoordinator(governor: governor, construction: construction)
            if global {
                for index in 0..<3 {
                    _ = try await governor.admit(.provider, owner: AddonID(rawValue: "com.example.p\(index)")!)
                }
                _ = try await governor.admit(.scene, owner: AddonID(rawValue: "com.example.scene")!)
            } else {
                _ = try await governor.admit(.provider, owner: owner)
                _ = try await governor.admit(.temporaryMemory(bytes: 64 * 1_024 * 1_024 - 4_111), owner: owner)
            }
            let memory = await governor.usage(.admittedMemoryBytes)
            let state = await governor.usage(.retainedStateBytes)
            await #expect(throws: AddonFailure.self) { try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
            #expect(construction.counts.allocated == 0)
            #expect(await governor.usage(.assetBytes) == 0)
            #expect(await governor.usage(.admittedMemoryBytes) == memory)
            #expect(await governor.usage(.retainedStateBytes) == state)
        }
    }

    @Test func ownerAndGlobalRasterCeilingsAreAtomicWithExistingAssets() async throws {
        for global in [false, true] {
            let governor = ResourceGovernor()
            let construction = RasterConstruction()
            let coordinator = AssetDisposalCoordinator(governor: governor, construction: construction)
            if global {
                for index in 0..<4 {
                    _ = try await governor.admit(.asset(bytes: 8 * 1_024 * 1_024), owner: AddonID(rawValue: "com.example.asset\(index)")!)
                }
            } else {
                _ = try await governor.admit(.asset(bytes: 8 * 1_024 * 1_024 - 15), owner: owner)
            }
            let asset = await governor.usage(.assetBytes)
            let memory = await governor.usage(.admittedMemoryBytes)
            let state = await governor.usage(.retainedStateBytes)
            await #expect(throws: AddonFailure.self) { try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner) }
            #expect(construction.counts.allocated == 0)
            #expect(await governor.usage(.assetBytes) == asset)
            #expect(await governor.usage(.admittedMemoryBytes) == memory)
            #expect(await governor.usage(.retainedStateBytes) == state)
        }
    }

    @Test func mismatchedGovernorForwarderIsRejected() throws {
        #expect(throws: AddonFailure.self) {
            try AssetDisposalCoordinator(governor: ResourceGovernor(), access: RasterAccess(ResourceGovernor()))
        }
    }
}

extension AssetRasterBackingTests {
    @Test func maximumSlotCeilingIsEnforcedWithRealTinyImages() async throws {
        let governor = ResourceGovernor()
        let construction = RasterConstruction()
        let coordinator = AssetDisposalCoordinator(governor: governor, maximumSlots: Int.max, construction: construction)
        let tiny = Data([0, 0, 0, 0])
        var held: [AssetRasterBacking] = []
        for _ in 0..<1_638 {
            held.append(try await coordinator.create(pixels: tiny, width: 1, height: 1, owner: owner))
        }
        #expect(coordinator.status().slots == 1_638)
        #expect(await governor.usage(.assetBytes) == 6_552)
        #expect(await governor.usage(.retainedStateBytes) == 1_638 * 5_120)
        #expect(await governor.usage(.admittedMemoryBytes) == 1_638 * 4_100)
        await #expect(throws: AddonFailure.self) { try await coordinator.create(pixels: tiny, width: 1, height: 1, owner: owner) }
        #expect(construction.counts.allocated == 1_638)
        var survivor: AssetRasterBacking? = held.first
        held.removeAll()
        try await coordinator.flushDisposed()
        #expect(coordinator.status().slots == 1)
        #expect(construction.counts.freed == 1_637)
        #expect(await governor.usage(.retainedStateBytes) == 5_120)
        #expect(survivor?.image.width == 1)
        survivor = nil
        try await coordinator.flushDisposed()
        #expect(construction.counts.freed == 1_638)
        #expect(coordinator.status().slots == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }
}

extension AssetRasterBackingTests {
    @Test func generalAndBulkCleanupCannotRefundActuallyLiveImage() async throws {
        let governor = ResourceGovernor()
        let access = RasterAccess(governor)
        let construction = RasterConstruction()
        let coordinator = try AssetDisposalCoordinator(governor: governor, access: access, construction: construction)
        var backing: AssetRasterBacking? = try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        let token = try #require(await access.lastToken)
        let other = AddonID(rawValue: "com.example.other")!
        do {
            try await governor.release(token.reservation.id, owner: other)
            Issue.record("Another owner released a live backing.")
        } catch let failure as AddonFailure { #expect(failure.code == .permissionDenied) }
        do {
            try await governor.release(token.reservation.id, owner: owner)
            Issue.record("General release refunded a live backing.")
        } catch let failure as AddonFailure { #expect(failure.code == .resourceDenied) }
        _ = try await governor.admit(.job, owner: owner)
        await governor.releaseAll(owner: owner)
        #expect(await governor.usage(.jobs) == 0)
        #expect(await governor.usage(.assetBytes) == 16)
        #expect(await governor.usage(.admittedMemoryBytes) == 4_112)
        #expect(await governor.usage(.retainedStateBytes) == 5_120)
        #expect(construction.counts.freed == 0)
        #expect(backing?.image.dataProvider?.data as Data? == pixels)
        backing = nil
        try await coordinator.flushDisposed()
        #expect(construction.counts.freed == 1)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func alreadyCancelledCreatorNeverAdmitsOrAllocates() async throws {
        let governor = ResourceGovernor()
        let construction = RasterConstruction()
        let access = RasterAccess(governor)
        let coordinator = try AssetDisposalCoordinator(governor: governor, access: access, construction: construction)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.create(pixels: pixels, width: 2, height: 2, owner: owner)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await access.admissions == 0)
        #expect(construction.counts.allocated == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }
}
