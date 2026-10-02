//
//  BoundedContractArrayTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct BoundedContractArrayTests {

    @Test
    func supportsUnknownUnkeyedCountWithoutLosingBounds() throws {
        let small = try JSONDecoder().decode(
            CountlessProbe.self,
            from: Data("[1,2,3]".utf8)
        )
        #expect(small.values == [1, 2, 3])
        #expect(throws: AddonFailure.self) {
            try JSONDecoder().decode(
                CountlessProbe.self,
                from: Data("[1,2,3,{}]".utf8)
            )
        }
    }
}
