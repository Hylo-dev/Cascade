//
//  FileWorkspaceWire.swift
//  CascadeKit
//

import Foundation

/// FileWorkspaceWire contains only validation shared by the small file workspace values.
enum FileWorkspaceWire {
    static func validateTypeIdentifier(_ value: String) throws {
        try ContractValidation.require(
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && value.utf8.count <= 128
                && value.utf8.allSatisfy { $0 < 128 },
            "Invalid file type identifier"
        )
    }

    static func validateCursor(_ value: String?) throws {
        try ContractValidation.require(
            value.map { !$0.isEmpty && $0.utf8.count <= 128 } ?? true,
            "Invalid file workspace cursor"
        )
    }

    static func validateIDs(_ values: [UUID], requiresNonempty: Bool) throws {
        try ContractValidation.require(
            values.count <= 32 && (!requiresNonempty || !values.isEmpty)
                && Set(values).count == values.count,
            "Invalid file workspace IDs"
        )
    }
}
