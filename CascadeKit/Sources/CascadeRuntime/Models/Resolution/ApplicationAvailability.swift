//
//  ApplicationAvailability.swift
//  CascadeKit
//

public struct ApplicationAvailability: Hashable, Codable, Sendable {

    public let installed: Bool
    public let running  : Bool

    public init(
        installed: Bool,
        running  : Bool
    ) {
        self.installed = installed
        self.running   = running
    }
}
