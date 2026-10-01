//
//  PluginPlainSurface.swift
//  CascadeKit
//

import Foundation

/// PluginPlainSurface declares a surface that takes no options in v1, the activity and the
/// notice: `{}` in the manifest. Any field inside it is rejected, so a typo cannot pass for an
/// option the host does not have.
public struct PluginPlainSurface: Codable, Equatable, Sendable {

    public init() {}

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(fields.allKeys.isEmpty, "Unknown wire field")
    }

    public func encode(to encoder: any Encoder) throws {
        _ = encoder.container(keyedBy: WireKey.self)
    }
}
