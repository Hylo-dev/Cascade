//
//  StateMigration.swift
//  CascadeKit
//

import Foundation

/// StateMigration is the bounded source the host may send to a qualified external migration worker.
/// This type does not execute addon code or authorize a process launch.
public struct StateMigration: Sendable {
    public let ticket: StateMigrationTicket
    public let source: StateCheckpoint
    public let targetSchemaVersion: UInt32
}
