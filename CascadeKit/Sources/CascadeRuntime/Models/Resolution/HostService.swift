//
//  HostService.swift
//  CascadeKit
//

public struct HostService: Hashable, Codable, Sendable {

    public let id     : String
    public let version: SemanticVersion

    public init(
        id     : String,
        version: SemanticVersion
    ) {
        self.id      = id
        self.version = version
    }
}
