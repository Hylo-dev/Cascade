//
//  RasterConstruction.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

final class RasterConstruction: AssetRasterConstruction, @unchecked Sendable {

    enum Boundary: CaseIterable {

        case allocate
        case providerBefore
        case providerAfter
        case colorSpace
        case image
    }

    private let lock   = NSLock()
    private let native = NativeAssetRasterConstruction()

    let fail  : Boundary?
    let cancel: Boundary?

    private var allocated       = 0
    private var freed           = 0
    private var allocatedOnMain = false

    init(
        fail  : Boundary? = nil,
        cancel: Boundary? = nil
    ) {
        self.fail   = fail
        self.cancel = cancel
    }

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
            lock.withLock {
                allocated += 1
                allocatedOnMain = allocatedOnMain || Thread.isMainThread
            }
        }

        return result
    }

    func deallocate(
        _ pointer: UnsafeMutableRawPointer,
        bytes    : Int
    ) {
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

    func image(
        layout    : AssetRasterLayout,
        provider  : CGDataProvider,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        visit(.image)
        return fail == .image ? nil : native.image(layout: layout, provider: provider, colorSpace: colorSpace)
    }
}
