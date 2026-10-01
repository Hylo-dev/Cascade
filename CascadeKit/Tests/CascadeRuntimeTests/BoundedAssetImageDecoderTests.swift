//
//  BoundedAssetImageDecoderTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1))) struct BoundedAssetImageDecoderTests {
    let owner = AddonID(rawValue: "com.example.decoder")!

#if DEBUG
    /// cancellationInsideNativeFrameKeepsStagingUntilWorkerReturns observes actual native
    /// execution and joins the cancelled task; cancellation is not used as a disposal signal.
    @Test func cancellationInsideNativeFrameKeepsStagingUntilWorkerReturns() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let observer = AssetLifecycleObserver(governor: governor, point: .native)
        let encoded = try imageFixture()
        let worker = Task {
            let succeeded = await AssetLifecycleTesting.$observer.withValue(observer) {
                do {
                    _ = try await decoder.decode(encoded: encoded, owner: owner)
                    return true
                } catch { return false }
            }
            observer.gate.finished()
            return succeeded
        }
        do {
            try #require(await observer.gate.waitForArrival())
            worker.cancel()
            #expect(observer.snapshot().nativeDraws == 1)
            #expect(observer.snapshot().nativeReturns == 0)
            #expect(await governor.usage(.admittedMemoryBytes) == 2 * 1_024 * 1_024 + 8_000_000 + 65_536)
            observer.gate.release()
            #expect(await worker.value == false)
            try await coordinator.flushDisposed()
            #expect(await governor.usage(.admittedMemoryBytes) == 0)
            #expect(await governor.usage(.assetBytes) == 0)
        } catch {
            observer.gate.release()
            _ = await worker.value
            decoder.close()
            throw error
        }
        decoder.close()
    }
#endif

    @Test func pngNormalizesAlphaAndRetainsChargeUntilLastImageUse() async throws {
        let encoded = try imageFixture()
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let decoder: any AssetImageDecoding = BoundedAssetImageDecoder(coordinator: coordinator)
        var backing: AssetRasterBacking? = try await decoder.decode(encoded: encoded, owner: owner)
        var image: CGImage? = backing?.image
        #expect(backing?.owner == owner)
        #expect(image?.width == 2)
        #expect(image?.height == 1)
        #expect(image?.bitsPerComponent == 8)
        #expect(image?.bitsPerPixel == 32)
        #expect(image?.bytesPerRow == 8)
        #expect(image?.alphaInfo == .premultipliedLast)
        #expect(image?.colorSpace?.name == CGColorSpace.sRGB)
        #expect(image?.dataProvider?.data as Data? == Data([128, 0, 0, 128, 0, 255, 0, 255]))
        decoder.close()
        backing = nil
        #expect(await governor.usage(.assetBytes) == 8)
        #expect(await governor.usage(.admittedMemoryBytes) == 4_104)
        #expect(image?.height == 1)
        image = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func jpegProducesOpaqueSRGBWithoutRetainingTemporaryMemory() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let encoded = try imageFixture(type: "public.jpeg", width: 8, height: 8)
        var backing: AssetRasterBacking? = try await decoder.decode(encoded: encoded, owner: owner)
        #expect(backing?.image.width == 8)
        #expect(backing?.image.height == 8)
        #expect(backing?.image.colorSpace?.name == CGColorSpace.sRGB)
        let bytes = try #require(backing?.image.dataProvider?.data as Data?)
        #expect(bytes.enumerated().filter { $0.offset % 4 == 3 }.allSatisfy { $0.element == 255 })
        #expect(await governor.usage(.admittedMemoryBytes) == 4_352)
        backing = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func rejectsMalformedOversizeAnimatedAndUnsupportedInputsWithoutLeaking() async throws {
        let valid = try imageFixture()
        let jpeg = try imageFixture(type: "public.jpeg", width: 64, height: 64)
        let repairedJPEG = Data(jpeg.dropLast(16)) + Data([0xFF, 0xD9])
        let inputs: [Data] = try [
            Data(), Data([0, 1, 2, 3]), Data(repeating: 0, count: 1_048_577),
            Data(valid.prefix(valid.count / 2)), Data(valid.dropLast()),
            Data(valid.dropLast(12)), Data(try imageFixture(type: "public.jpeg").dropLast(2)),
            repairedJPEG,
            imageFixture(type: "com.compuserve.gif"),
            imageFixture(type: "public.tiff"),
            imageFixture(width: 1_001, height: 1_000),
            imageFixture(frames: 2),
            imageFixture(orientation: 6),
            imageFixture(bits: 16),
            imageFixture(spaceName: CGColorSpace.displayP3)
        ]
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        for (index, input) in inputs.enumerated() {
            await #expect(throws: AddonFailure.self, "Rejected fixture \(index)") {
                try await decoder.decode(encoded: input, owner: owner)
            }
            try await coordinator.flushDisposed()
            #expect(await governor.usage(.admittedMemoryBytes) == 0)
            #expect(await governor.usage(.retainedStateBytes) == 0)
        }
        // A rejection must return the busy permit to the next valid caller.
        let result = try await decoder.decode(encoded: valid, owner: owner)
        #expect(result.image.width == 2)
    }

    @Test func admissionDenialLeavesExistingQuotaIntact() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let held = try await governor.admit(.temporaryMemory(bytes: 127 * 1_024 * 1_024), owner: owner)
        await #expect(throws: AddonFailure.self) {
            try await decoder.decode(encoded: imageFixture(), owner: owner)
        }
        #expect(await governor.usage(.admittedMemoryBytes) == 127 * 1_024 * 1_024)
        #expect(coordinator.status().slots == 0)
        try await governor.release(held.id, owner: owner)
        let result = try await decoder.decode(encoded: imageFixture(), owner: owner)
        #expect(result.image.width == 2)
    }

    @Test func closeAndAlreadyCancelledRejectBeforeAdmission() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let encoded = try imageFixture()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await decoder.decode(encoded: encoded, owner: owner)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        decoder.close()
        await #expect(throws: AddonFailure.self) { try await decoder.decode(encoded: encoded, owner: owner) }
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }
}

/// imageFixture uses Apple's encoder; the tiny RGBA fixture has hand-derived premultiplied bytes.
private func imageFixture(
    type       : String = "public.png",
    width      : Int = 2,
    height     : Int = 1,
    frames     : Int = 1,
    orientation: Int = 1,
    bits       : Int = 8,
    spaceName  : CFString = CGColorSpace.sRGB,
    pixelBytes : Data? = nil
) throws -> Data {
    let space = try #require(CGColorSpace(name: spaceName))
    let context = try #require(CGContext(
        data            : nil,
        width           : width,
        height          : height,
        bitsPerComponent: bits,
        bytesPerRow     : width * 4 * (bits / 8),
        space           : space,
        bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
            | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : CGBitmapInfo.byteOrder32Big.rawValue)
    ))
    context.setFillColorSpace(space)
    context.setFillColor([1, 0, 0, 0.5])
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor([0, 1, 0, 1])
    context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
    let image: CGImage
    if let pixelBytes {
        let provider = try #require(CGDataProvider(data: pixelBytes as CFData))
        image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    } else {
        image = try #require(context.makeImage())
    }
    let buffer = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(buffer, type as CFString, frames, nil))
    for _ in 0..<frames {
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    return buffer as Data
}

extension BoundedAssetImageDecoderTests {
    @Test func busyAndBulkCleanupKeepInFlightDecodeCharged() async throws {
        let governor = ResourceGovernor()
        let access = DecoderRasterGate(governor: governor)
        let coordinator = try AssetDisposalCoordinator(governor: governor, access: access)
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let encoded = try imageFixture()
        let first = Task { try await decoder.decode(encoded: encoded, owner: owner) }
        await access.reached()
        let memory = await governor.usage(.admittedMemoryBytes)
        #expect(memory > 8_000_000)
        do {
            _ = try await decoder.decode(encoded: encoded, owner: owner)
            Issue.record("Concurrent decode unexpectedly succeeded.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .rateLimited)
        }
        await governor.releaseAll(owner: owner)
        #expect(await governor.usage(.admittedMemoryBytes) == memory)
        await access.open()
        var backing: AssetRasterBacking? = try await first.value
        #expect(backing?.image.width == 2)
        #expect(await governor.usage(.admittedMemoryBytes) == 4_104)
        // Task itself retains its result; the separate lifetime test covers final disposal.
        backing = nil
    }

    @Test func closeOrCancellationDuringRasterAdmissionDiscardsOutputAndRefunds() async throws {
        for cancellation in [false, true] {
            let governor = ResourceGovernor()
            let access = DecoderRasterGate(governor: governor)
            let coordinator = try AssetDisposalCoordinator(governor: governor, access: access)
            let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
            let encoded = try imageFixture()
            let first = Task { try await decoder.decode(encoded: encoded, owner: owner) }
            await access.reached()
            if cancellation { first.cancel() } else { decoder.close() }
            #expect(await governor.usage(.admittedMemoryBytes) > 8_000_000)
            await access.open()
            if cancellation {
                await #expect(throws: CancellationError.self) { try await first.value }
            } else {
                await #expect(throws: AddonFailure.self) { try await first.value }
            }
            try await coordinator.flushDisposed()
            #expect(await governor.usage(.admittedMemoryBytes) == 0)
            #expect(await governor.usage(.retainedStateBytes) == 0)
        }
    }
}

extension BoundedAssetImageDecoderTests {
    @Test func normalizationPreservesDistinctRowsWithoutVerticalFlip() async throws {
        let pixels = Data([255, 0, 0, 255, 0, 255, 0, 255,
                           0, 0, 255, 255, 0, 0, 0, 0])
        let encoded = try imageFixture(width: 2, height: 2, pixelBytes: pixels)
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let backing = try await decoder.decode(encoded: encoded, owner: owner)
        #expect(backing.image.dataProvider?.data as Data? == pixels)
    }

    @Test func exactlyOneMillionPixelsIsAcceptedAndCharged() async throws {
        let encoded = try imageFixture(width: 1_000, height: 1_000)
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        var backing: AssetRasterBacking? = try await decoder.decode(encoded: encoded, owner: owner)
        #expect(backing?.image.width == 1_000)
        #expect(backing?.image.height == 1_000)
        #expect(await governor.usage(.assetBytes) == 4_000_000)
        #expect(await governor.usage(.admittedMemoryBytes) == 4_004_096)
        backing = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
    }
}
