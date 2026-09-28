//
//  BoundedContractArray.swift
//  CascadeKit
//

import Foundation

/// BoundedContractArray checks known counts before allocation and unknown counts before each element.
/// The shared traversal preserves generic Decoder support without permitting unbounded arrays.
enum BoundedContractArray {
    static func decode<Value: Decodable>(
        _ type      : Value.Type,
        from decoder: any Decoder,
        maximum     : Int
    ) throws -> [Value] {
        var container = try decoder.unkeyedContainer()
        try ContractValidation.require(
            container.count.map { $0 <= maximum } ?? true,
            "Contract collection exceeds element budget"
        )
        var values: [Value] = []
        if let count = container.count { values.reserveCapacity(count) }
        while !container.isAtEnd {
            try ContractValidation.require(
                values.count < maximum,
                "Contract collection exceeds element budget"
            )
            values.append(try container.decode(type))
        }
        return values
    }
}
