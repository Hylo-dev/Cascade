//
//  AddonFailureTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@Suite
struct AddonFailureTests {

    @Test
    func boundsSwiftFailureReasonsByUTF8() throws {
        // This byte fixture is independent of the production truncation algorithm:
        // 4,096 ASCII bytes are permitted, while one combining cluster can exceed it.
        let byteBoundary     = String(decoding: Data(repeating: 0x61, count: 4096), as: UTF8.self)
        let combiningCluster = "e" + String(repeating: "\u{0301}", count: 4096)
        let reasons          = ["", String(repeating: "👨‍👩‍👧‍👦", count: 1024), combiningCluster, byteBoundary]

        for reason in reasons {
            let failure = AddonFailure(code: .permissionDenied, reason: reason)
            #expect(!failure.reason.isEmpty)
            #expect(failure.reason.utf8.count <= 4096)
        }

        #expect(AddonFailure(code: .permissionDenied, reason: byteBoundary).reason == byteBoundary)

        let familyReason = AddonFailure(
            code  : .permissionDenied,
            reason: String(repeating: "👨‍👩‍👧‍👦", count: 1024)
        )
        #expect(familyReason.reason == String(repeating: "👨‍👩‍👧‍👦", count: 163))
    }
}
