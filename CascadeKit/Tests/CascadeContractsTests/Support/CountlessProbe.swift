//
//  CountlessProbe.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

/// CountlessProbe forwards actual Foundation values while exercising the generic unknown-count path.
struct CountlessProbe: Decodable {

    let values: [Int]

    init(from decoder: any Decoder) throws {
        values = try BoundedContractArray.decode(
            Int.self,
            from   : CountlessDecoder(base: decoder),
            maximum: 3
        )
    }
}
