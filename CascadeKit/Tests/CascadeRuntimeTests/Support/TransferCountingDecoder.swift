//
//  TransferCountingDecoder.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// TransferCountingDecoder observes attempted decode entry while forwarding real codec work.
final class TransferCountingDecoder: AssetImageDecoding, @unchecked Sendable {

    private let real : BoundedAssetImageDecoder
    private let lock  = NSLock()
    private var count = 0

    var calls: Int { lock.withLock { count } }

    var assetGovernor: ResourceGovernor { real.assetGovernor }

    init(real: BoundedAssetImageDecoder) { self.real = real }

    func decode(
        encoded: Data,
        owner  : AddonID
    ) async throws -> AssetRasterBacking {
        lock.withLock { count += 1 }

        return try await real.decode(encoded: encoded, owner: owner)
    }

    func close() { real.close() }
}
