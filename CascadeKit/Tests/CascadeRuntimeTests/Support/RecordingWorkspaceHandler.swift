//
//  RecordingWorkspaceHandler.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

actor RecordingWorkspaceHandler: FileWorkspaceCommandHandling {

    enum Failure: Sendable {

        case workspace(FileWorkspaceError)
        case untrusted(AddonFailure)
    }

    struct Call: Sendable {

        let command: FileWorkspaceCommand
        let owner  : VerifiedAddonIdentity
        let source : ServiceSourceDescriptor
    }

    let snapshot: FileWorkspaceSnapshot
    let gate    : WorkspaceHandlerGate?
    let failure : Failure?

    private(set) var calls: [Call] = []

    init(
        snapshot: FileWorkspaceSnapshot,
        gate    : WorkspaceHandlerGate? = nil,
        failure : Failure? = nil
    ) {
        self.snapshot = snapshot
        self.gate     = gate
        self.failure  = failure
    }

    func handle(
        _ command: FileWorkspaceCommand,
        owner    : VerifiedAddonIdentity,
        source   : ServiceSourceDescriptor
    ) async throws -> FileWorkspaceSnapshot {
        calls.append(Call(
            command: command,
            owner  : owner,
            source : source
        ))
        await gate?.pause()

        switch failure {
            case .workspace(let error): throw error
            case .untrusted(let error): throw error
            case nil: break
        }

        return snapshot
    }
}
