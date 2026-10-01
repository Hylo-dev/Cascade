//
//  StateRegistration.swift
//  CascadeKit
//

/// StateRegistration is trusted host policy for one verified retained-data identity. Never decoded
/// from provider input.
public struct StateRegistration: Hashable, Sendable {

    public let identity            : VerifiedAddonIdentity
    public let maximumSchemaVersion: UInt32

    public init(
        identity            : VerifiedAddonIdentity,
        maximumSchemaVersion: UInt32
    ) {
        self.identity             = identity
        self.maximumSchemaVersion = maximumSchemaVersion
    }
}
