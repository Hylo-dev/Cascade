//
//  NativeAssetImageWorker.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO

/// NativeAssetImageWorker keeps ImageIO parsing and CGContext normalization off MainActor.
/// Only the owning decoder can enqueue work after its synchronous single-operation gate.
actor NativeAssetImageWorker {
    private struct Pixels {
        let data  : Data
        let width : Int
        let height: Int
    }

    /// create destroys native source/context state before handing normalized pixels to the
    /// existing actual-lifetime raster factory. No compressed provider escapes this actor.
    func create(
        encoded    : Data,
        owner      : AddonID,
        coordinator: AssetDisposalCoordinator,
        decoder    : BoundedAssetImageDecoder
    ) async throws -> AssetRasterBacking {
        try decoder.validateOperation()
        let pixels = try autoreleasepool { try normalize(encoded, decoder: decoder) }
#if DEBUG
        AssetLifecycleTesting.observer(for: decoder.assetGovernor)?.nativeScopeReturned()
#endif
        try decoder.validateOperation()
        let result = try await coordinator.create(
            pixels: pixels.data,
            width : pixels.width,
            height: pixels.height,
            owner : owner
        )
        try decoder.validateOperation()
        return result
    }

    /// normalize accepts complete single-frame RGB PNG/JPEG images with 8-bit channels.
    /// Orientation must already be upright. ICC profiles must resolve to native sRGB;
    /// wider-gamut, grayscale/CMYK, HDR and animated inputs are intentionally unsupported.
    /// Metadata is inspected through ImageIO and never attached to the normalized raster.
    private func normalize(_ encoded: Data, decoder: BoundedAssetImageDecoder) throws -> Pixels {
        let expectedType = try containerType(encoded)
        let options = [
            kCGImageSourceShouldCache           : false,
            kCGImageSourceShouldAllowFloat      : false,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(encoded as CFData, options),
              let type = CGImageSourceGetType(source) as String?,
              type == expectedType,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              properties[kCGImagePropertyDepth] as? Int == 8,
              properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String,
              (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
              (properties[kCGImagePropertyIsFloat] as? Bool ?? false) == false else {
            throw failure("Only complete, upright, single-frame RGB8 PNG and JPEG images are supported.")
        }
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow, count <= 1_000_000 else {
            throw failure("Decoded images must contain at most one million pixels.")
        }
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
           png[kCGImagePropertyAPNGLoopCount] != nil
            || png[kCGImagePropertyAPNGDelayTime] != nil
            || png[kCGImagePropertyAPNGUnclampedDelayTime] != nil {
            throw failure("Animated PNG images are not supported.")
        }
        if let profile = properties[kCGImagePropertyProfileName] as? String,
           profile != "sRGB IEC61966-2.1", profile != "sRGB" {
            throw failure("Only the sRGB color profile is supported.")
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              image.width == width, image.height == height,
              image.bitsPerComponent == 8, image.bitsPerPixel <= 32,
              !image.bitmapInfo.contains(.floatComponents),
              let imageSpace = image.colorSpace,
              CFEqual(imageSpace, colorSpace),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw failure("The native image cannot be safely normalized to RGBA8 sRGB.")
        }
        try Task.checkCancellation()
        let rowBytes = width * 4
        var data = Data(count: count * 4)
        // Data owns this bounded mutable buffer for the duration of the closure. CGContext
        // neither outlives nor escapes it; the returned Data is immutable to its consumers.
        try data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data            : baseAddress,
                    width           : width,
                    height          : height,
                    bitsPerComponent: 8,
                    bytesPerRow     : rowBytes,
                    space           : colorSpace,
                    bitmapInfo      : CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                throw failure("The normalization context could not be allocated.")
            }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            // ImageIO can report completeness until draw forces its lazy decoder to
            // consume the scan. Keep this check in the same native frame as that draw.
            guard CGImageSourceGetStatus(source) == .statusComplete,
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
                throw failure("The native decoder reported incomplete image data.")
            }
#if DEBUG
            // Hold real source/image/context/allocation lifetimes, not a metadata hop.
            // This does not pretend to interrupt the interior of an ImageIO C call.
            withExtendedLifetime((source, image, context)) {
                AssetLifecycleTesting.observer(for: decoder.assetGovernor)?.nativeDrawCompleted()
            }
#endif
        }
        try Task.checkCancellation()
        return Pixels(data: data, width: width, height: height)
    }

    /// containerType requires fixed signature and terminal markers for this narrow profile.
    /// ImageIO accepts missing terminal markers even with eager decoding, so require the fixed
    /// signature and terminal bytes before invoking it. This is not a chunk, scan or CRC
    /// parser; payload validity still relies on native decoding and its completion status.
    private func containerType(_ encoded: Data) throws -> String {
        if encoded.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
           encoded.suffix(12).elementsEqual([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]) {
            return "public.png"
        }
        if encoded.starts(with: [0xFF, 0xD8, 0xFF]),
           encoded.suffix(2).elementsEqual([0xFF, 0xD9]) {
            return "public.jpeg"
        }
        throw failure("Only PNG and JPEG images with complete terminal markers are supported.")
    }

    private func failure(_ reason: String) -> AddonFailure {
        AddonFailure(code: .resourceDenied, reason: reason)
    }
}
