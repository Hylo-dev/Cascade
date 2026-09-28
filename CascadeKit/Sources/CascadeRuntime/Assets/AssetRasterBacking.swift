//
//  AssetRasterBacking.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation

/// AssetRasterBacking is an immutable host raster; attribution is not a publication permission.
/// The image retains the provider, which retains its one pixel allocation until final use. No
/// mutable pointer or governor disposal capability escapes in this wrapper.
final class AssetRasterBacking: @unchecked Sendable {
    let image: CGImage
    let owner: AddonID
    fileprivate init(image: CGImage, owner: AddonID) {
        self.image = image
        self.owner = owner
    }
}

struct AssetRasterLayout: Sendable {
    let width: Int
    let height: Int
    let rowBytes: Int
    let byteCount: Int

    init(width: Int, height: Int, byteCount: Int) throws {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (required, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, !pixelOverflow, !rowOverflow, !byteOverflow,
              pixels <= 1_000_000, byteCount == required else {
            throw AddonFailure(code: .resourceDenied, reason: "The raster must contain at most one million tightly packed RGBA8 pixels.")
        }
        self.width = width
        self.height = height
        self.rowBytes = rowBytes
        self.byteCount = required
    }
}

/// AssetRasterConstruction is the trusted construction boundary, not an addon callback. A nil
/// provider result MUST retain neither context nor provider and cannot schedule a later
/// callback. A builder may drop a successfully built provider before returning nil; the
/// context's one-shot disposal handles that real callback as well as no callback.
protocol AssetRasterConstruction: Sendable {
    func allocate(bytes: Int) -> UnsafeMutableRawPointer?
    func deallocate(_ pointer: UnsafeMutableRawPointer, bytes: Int)
    func provider(context: AssetRasterProviderContext) -> CGDataProvider?
    func colorSpace() -> CGColorSpace?
    func image(layout: AssetRasterLayout, provider: CGDataProvider, colorSpace: CGColorSpace) -> CGImage?
}

struct NativeAssetRasterConstruction: AssetRasterConstruction {
    func allocate(bytes: Int) -> UnsafeMutableRawPointer? { malloc(bytes) }
    func deallocate(_ pointer: UnsafeMutableRawPointer, bytes: Int) { free(pointer) }
    func provider(context: AssetRasterProviderContext) -> CGDataProvider? { context.makeProvider() }
    func colorSpace() -> CGColorSpace? { CGColorSpace(name: CGColorSpace.sRGB) }
    func image(layout: AssetRasterLayout, provider: CGDataProvider, colorSpace: CGColorSpace) -> CGImage? {
        CGImage(width: layout.width, height: layout.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: layout.rowBytes, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// AssetRasterProviderContext owns one pixel allocation and frees it exactly once through the data
/// provider's release callback. The callback retain is distinct from the factory's local strong
/// reference. On nullable provider failure the factory still owns a strong context and disposes it
/// locally. A callback during a failed construction may already have consumed that retain: the
/// locked one-shot state detects that, rather than assuming nil alone means that no release
/// callback ran. No freed context is ever used to inject failures or duplicate callbacks.
final class AssetRasterProviderContext: @unchecked Sendable {
    private let lock = NSLock()
    private let pointer: UnsafeMutableRawPointer
    private let byteCount: Int
    private let allocation: any AssetRasterConstruction
    private let coordinator: AssetDisposalCoordinator
    private let slot: AssetDisposalCoordinator.Slot
    private var disposed = false
    private var callbackRetain = false

    fileprivate init(pointer: UnsafeMutableRawPointer, byteCount: Int,
                     allocation: any AssetRasterConstruction,
                     coordinator: AssetDisposalCoordinator, slot: AssetDisposalCoordinator.Slot) {
        self.pointer = pointer
        self.byteCount = byteCount
        self.allocation = allocation
        self.coordinator = coordinator
        self.slot = slot
    }

    func makeProvider() -> CGDataProvider? {
        let mayCreate = lock.withLock {
            guard !disposed, !callbackRetain else { return false }
            callbackRetain = true
            return true
        }
        guard mayCreate else { return nil }
        let info = Unmanaged.passRetained(self).toOpaque()
        let result = CGDataProvider(dataInfo: info, data: pointer, size: byteCount) { info, _, _ in
            guard let info else { return }
            let context = Unmanaged<AssetRasterProviderContext>.fromOpaque(info).takeUnretainedValue()
            context.dispose()
        }
        if result == nil { dispose() }
        return result
    }

    fileprivate func dispose() {
        let ownership: (Bool, Bool) = lock.withLock {
            guard !disposed else { return (false, false) }
            disposed = true
            let retained = callbackRetain
            callbackRetain = false
            return (true, retained)
        }
        guard ownership.0 else { return }
        allocation.deallocate(pointer, bytes: byteCount)
        coordinator.disposed(slot)
        if ownership.1 { Unmanaged.passUnretained(self).release() }
        withExtendedLifetime(self) {}
    }
}

/// AssetRasterFactory is the explicit non-MainActor executor for validation, destination
/// allocation/copy, and actual CoreGraphics construction. Input Data remains caller-owned and
/// separately accounted; no retained Data copy is attached to the result.
actor AssetRasterFactory {
    let construction: any AssetRasterConstruction
    init(construction: any AssetRasterConstruction) { self.construction = construction }

    func create(pixels: Data, width: Int, height: Int, owner: AddonID,
                coordinator: AssetDisposalCoordinator,
                access: any AssetReservationAccess) async throws -> AssetRasterBacking {
        let layout = try AssetRasterLayout(width: width, height: height, byteCount: pixels.count)
        try coordinator.validateCreation()
        let token = try await access.reserveRaster(bytes: layout.byteCount, owner: owner)
        let slot = coordinator.install(token)
        do { try coordinator.validateCreation() }
        catch { coordinator.disposed(slot); throw error }
        guard let pointer = construction.allocate(bytes: layout.byteCount) else {
            coordinator.disposed(slot)
            throw AddonFailure(code: .resourceDenied, reason: "The raster allocation failed.")
        }
        let context = AssetRasterProviderContext(pointer: pointer, byteCount: layout.byteCount,
            allocation: construction, coordinator: coordinator, slot: slot)
        pixels.withUnsafeBytes { source in
            pointer.copyMemory(from: source.baseAddress!, byteCount: layout.byteCount)
        }
        guard let provider = construction.provider(context: context) else {
            context.dispose()
            throw AddonFailure(code: .resourceDenied, reason: "The raster provider could not be created.")
        }
        guard let colorSpace = construction.colorSpace(),
              let image = construction.image(layout: layout, provider: provider, colorSpace: colorSpace) else {
            throw AddonFailure(code: .resourceDenied, reason: "The raster image could not be created.")
        }
        try coordinator.validateCreation()
        return AssetRasterBacking(image: image, owner: owner)
    }
}
