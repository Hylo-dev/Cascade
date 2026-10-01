//
//  ArchiveRasterConstruction.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

/// ArchiveRasterConstruction preserves native provider ownership while varying image metadata.
struct ArchiveRasterConstruction: AssetRasterConstruction {

    enum Mode: CaseIterable, Sendable {

        case alpha
        case colorSpace
        case interpolation
    }

    let mode: Mode

    private let native = NativeAssetRasterConstruction()

    func allocate(bytes: Int) -> UnsafeMutableRawPointer? {
        native.allocate(bytes: bytes)
    }

    func deallocate(
        _ pointer: UnsafeMutableRawPointer,
        bytes    : Int
    ) {
        native.deallocate(pointer, bytes: bytes)
    }

    func provider(context: AssetRasterProviderContext) -> CGDataProvider? {
        native.provider(context: context)
    }

    func colorSpace() -> CGColorSpace? {
        mode == .colorSpace ? CGColorSpace(name: CGColorSpace.displayP3) : native.colorSpace()
    }

    func image(
        layout    : AssetRasterLayout,
        provider  : CGDataProvider,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        let alphaInfo = mode == .alpha ? CGImageAlphaInfo.last : CGImageAlphaInfo.premultipliedLast

        return CGImage(
            width            : layout.width,
            height           : layout.height,
            bitsPerComponent : 8,
            bitsPerPixel     : 32,
            bytesPerRow      : layout.rowBytes,
            space            : colorSpace,
            bitmapInfo       : CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | alphaInfo.rawValue),
            provider         : provider,
            decode           : nil,
            shouldInterpolate: mode == .interpolation,
            intent           : .defaultIntent
        )
    }
}
