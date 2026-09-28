//
//  StateMigration.swift
//  CascadeKit
//

import Foundation

/// StateRegistration is trusted host policy for one verified retained-data identity. Never decoded
/// from provider input.
public struct StateRegistration: Hashable, Sendable {
    public let identity: VerifiedAddonIdentity
    public let maximumSchemaVersion: UInt32

    public init(identity: VerifiedAddonIdentity, maximumSchemaVersion: UInt32) {
        self.identity = identity
        self.maximumSchemaVersion = maximumSchemaVersion
    }
}

/// StateOwner is a capability issued by one store instance. It is never decoded from provider input.
public struct StateOwner: Hashable, Sendable {
    let id: UUID
}

public struct StateWriteTicket: Hashable, Sendable {
    let id: UUID
}

public struct StateMigrationTicket: Hashable, Sendable {
    let id: UUID
}

public struct StateCheckpoint: Equatable, Sendable {
    public let data: Data
    public let schemaVersion: UInt32
    public let revision: UInt64
    public let digest: Data
}

/// StateMigration is the bounded source the host may send to a qualified external migration worker.
/// This type does not execute addon code or authorize a process launch.
public struct StateMigration: Sendable {
    public let ticket: StateMigrationTicket
    public let source: StateCheckpoint
    public let targetSchemaVersion: UInt32
}

public enum StateStoreFailure: Error, Equatable, Sendable {
    case unsafePath, unrecognizedEntry, oversized, corrupt, invalidOwner, invalidTicket
    case staleRevision, quotaExceeded, busy, closed, invalidConfiguration, missingState
    case futureSchema(UInt32)
    case io(Int32)
}
