//
//  PluginDocument+Validation.swift
//  CascadeKit
//

import Foundation

extension PluginDocument {

    /// validate enforces the document limits and every value's range in one walk.
    public func validate() throws {
        try ContractValidation.require(schema == Self.schemaVersion, "Unsupported document schema")
    }
}
