//
//  AssetRasterArchiveCopy.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation

/// AssetRasterArchiveCopy copies canonical RGBA8 on its own non-MainActor executor.
/// The caller prepays output Data retention and the separately quoted copy overlap before
/// crossing this actor. Neither the backing's protected native charge nor the returned Data
/// is released or admitted here. Serial caller use needs only twice the largest raster as
/// transient copy capacity; simultaneous callers must each protect their own operation.
actor AssetRasterArchiveCopy {
    /// scratchBytes quotes checked CoreGraphics-copy and Data-bridge overlap, excluding output.
    /// It validates metadata without copying pixels, so admission precedes provider.data.
    static func scratchBytes(
        backing: AssetRasterBacking,
        owner  : AddonID
    ) throws -> Int {
        let layout = try canonicalLayout(
            backing: backing,
            owner  : owner
        )
        // AssetRasterLayout caps each raster at four million bytes.
        return layout.byteCount * 2
    }

    /// copy rechecks immutable metadata and copies the provider bytes without image decoding.
    /// The CoreGraphics copy and any bridge overlap remain within caller scratch until return;
    /// returned Data remains inside the caller's separate retained-output scope.
    func copy(
        backing: AssetRasterBacking,
        owner  : AddonID
    ) throws -> Data {
        try Task.checkCancellation()
        let layout = try Self.canonicalLayout(
            backing: backing,
            owner  : owner
        )
        guard let copied = backing.image.dataProvider?.data,
              CFDataGetLength(copied) == layout.byteCount else {
            throw Self.failure("The canonical raster provider has an unexpected byte count.")
        }
        let result = copied as Data
        try Task.checkCancellation()
        return result
    }

    /// canonicalLayout accepts only the existing native constructor's immutable raster format.
    /// Owner attribution is checked here as accounting metadata, never a publication grant.
    private static func canonicalLayout(
        backing: AssetRasterBacking,
        owner  : AddonID
    ) throws -> AssetRasterLayout {
        let image = backing.image
        let (byteCount, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard backing.owner == owner,
              !overflow,
              image.bitsPerComponent == 8,
              image.bitsPerPixel == 32,
              image.bitmapInfo.rawValue == bitmapInfo,
              image.colorSpace?.name == CGColorSpace.sRGB,
              image.decode == nil,
              !image.shouldInterpolate,
              image.renderingIntent == .defaultIntent else {
            throw Self.failure("The archive requires an owner-matched canonical RGBA8 raster.")
        }
        let layout = try AssetRasterLayout(
            width    : image.width,
            height   : image.height,
            byteCount: byteCount
        )
        guard image.bytesPerRow == layout.rowBytes else {
            throw Self.failure("The archive raster must use tightly packed RGBA8 rows.")
        }
        return layout
    }

    /// failure rejects noncanonical inputs without allocating archive pixel storage.
    private static func failure(_ reason: String) -> AddonFailure {
        AddonFailure(
            code  : .invalidPayload,
            reason: reason
        )
    }
}
