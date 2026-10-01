//
//  RuntimeArchiveCost.swift
//  CascadeKit
//

import CascadeContracts

/// RuntimeArchiveCost rejects overflow before callers form quota requests or retain controlled values.
enum RuntimeArchiveCost {

    static func require(_ condition: Bool) throws {
        guard condition else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Invalid or oversized runtime archive value"
            )
        }
    }

    static func add(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        try require(lhs >= 0 && rhs >= 0 && !overflow)

        return result
    }

    static func multiply(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        try require(lhs >= 0 && rhs >= 0 && !overflow)

        return result
    }
}
