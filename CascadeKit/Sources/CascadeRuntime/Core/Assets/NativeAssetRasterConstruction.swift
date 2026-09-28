//
//  NativeAssetRasterConstruction.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation

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
