//
//  TransferIntegrityDecoder.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// TransferIntegrityDecoder verifies arbitrary byte assembly at a controlled decoder boundary.
/// Its real decoder imports a separate valid fixture; this is not a claim that 1 MiB is a PNG.
final class TransferIntegrityDecoder: AssetImageDecoding, @unchecked Sendable {

    let real   : BoundedAssetImageDecoder
    let fixture: Data

    private let lock  = NSLock()
    private var exact = false

    var wasExact: Bool { lock.withLock { exact } }

    var assetGovernor: ResourceGovernor { real.assetGovernor }

    init(
        real   : BoundedAssetImageDecoder,
        fixture: Data
    ) {
        self.real    = real
        self.fixture = fixture
    }

    func decode(
        encoded: Data,
        owner  : AddonID
    ) async throws -> AssetRasterBacking {
        let matches = encoded.count == 1_048_576
            && encoded.enumerated().allSatisfy { $0.element == UInt8($0.offset / 65_536) }
        lock.withLock { exact = matches }

        return try await real.decode(encoded: fixture, owner: owner)
    }

    func close() { real.close() }
}
