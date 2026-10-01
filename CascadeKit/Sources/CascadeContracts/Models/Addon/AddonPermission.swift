//
//  AddonPermission.swift
//  CascadeKit
//

import Foundation

/// AddonPermission is a validated value in the version 1 addon protocol.
public struct AddonPermission: Codable, Equatable, Sendable {

    public let id   : PermissionID
    public let scope: PermissionScope

    public init(
        id   : PermissionID,
        scope: PermissionScope
    ) throws {
        self.id    = id
        self.scope = scope

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id            = try container.decode(PermissionID.self, forKey: .id)
        scope         = try container.decode(PermissionScope.self, forKey: .scope)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            id == .storageOwn && scope == .addon,
            "Unsupported permission scope"
        )
    }

    public enum PermissionID: String, Codable, Sendable {

        case storageOwn = "storage.own"
    }

    public enum PermissionScope: String, Codable, Sendable {

        case addon
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id
        case scope
    }
}
