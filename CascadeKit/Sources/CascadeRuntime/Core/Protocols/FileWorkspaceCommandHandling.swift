//
//  FileWorkspaceCommandHandling.swift
//  CascadeKit
//

import CascadeContracts

/// FileWorkspaceCommandHandling is the host-owned persistence and conversion boundary.
protocol FileWorkspaceCommandHandling: Sendable {

    func handle(
        _ command: FileWorkspaceCommand,
        owner    : VerifiedAddonIdentity,
        source   : ServiceSourceDescriptor
    ) async throws -> FileWorkspaceSnapshot
}
