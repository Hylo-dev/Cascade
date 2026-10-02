//
//  ResourcePolicy.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// ResourcePolicy is host policy, which can only tighten ceilings. Package origin and publisher do
/// not select a policy.
public struct ResourcePolicy: Sendable {

    // Includes the reservation, bounded charge map and owner-index overhead.
    static let reservationCharge = 1_024
    static let mebibyte          = 1_024 * 1_024

    public let maximumRetainedStateBytes: Int

    public init(maximumRetainedStateBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumRetainedStateBytes = min(8 * 1_024 * 1_024, max(0, maximumRetainedStateBytes))
    }

    func ceiling(
        _ dimension: ResourceDimension,
        perOwner   : Bool
    ) -> Int {
        let mebibyte = Self.mebibyte

        switch dimension {
            case .retainedStateBytes : return maximumRetainedStateBytes
            case .assetBytes         : return (perOwner ? 8 : 32) * mebibyte
            case .admittedMemoryBytes: return (perOwner ? 128 : 256) * mebibyte
            case .diskStateBytes     : return (perOwner ? 10 : 100) * mebibyte
            case .diskCacheBytes     : return (perOwner ? 20 : 100) * mebibyte
            case .diskBytes          : return (perOwner ? 30 : 100) * mebibyte
        }
    }

    func charges(for request: ResourceRequest) throws -> [ResourceDimension: Int] {
        var result: [ResourceDimension: Int] = [.retainedStateBytes: Self.reservationCharge]

        func bytes(
            _ value  : Int,
            dimension: ResourceDimension
        ) throws {
            // Check before addition, including malformed host requests and Int.max.
            let previous = result[dimension, default: 0]

            guard value >= 0,
                  previous <= ceiling(dimension, perOwner: true),
                  value <= ceiling(dimension, perOwner: true) - previous
            else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The requested resource amount exceeds its budget."
                )
            }

            result[dimension] = previous + value
        }

        switch request {
            case .state(let count): try bytes(count, dimension: .retainedStateBytes)

            case .asset(let count):
                try bytes(count, dimension: .assetBytes)
                try bytes(count, dimension: .admittedMemoryBytes)

            case .temporaryMemory(let count): try bytes(count, dimension: .admittedMemoryBytes)

            case .diskState(let count):
                try bytes(count, dimension: .diskStateBytes)
                try bytes(count, dimension: .diskBytes)

            case .diskCache(let count):
                try bytes(count, dimension: .diskCacheBytes)
                try bytes(count, dimension: .diskBytes)
        }

        return result
    }
}
