//
//  FileWorkspaceService.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// FileWorkspaceService dispatches only work consumed from the broker's canonical state.
actor FileWorkspaceService {
    private static let contractID = "files.workspace"
    private static let featureID  = "workspace"
    private static let operation  = "command"

    private let broker : ServiceBroker
    private let handler: any FileWorkspaceCommandHandling
    private let clock  : any RuntimeClock

    init(
        broker : ServiceBroker,
        handler: any FileWorkspaceCommandHandling,
        clock  : any RuntimeClock = SystemRuntimeClock()
    ) {
        self.broker  = broker
        self.handler = handler
        self.clock   = clock
    }

    /// handle consumes dispatch authority once, then rechecks it at result delivery.
    func handle(_ work: ServiceWork) async throws -> ServiceResponse {
        let binding = try await broker.consumeInvocation(
            work,
            serviceID: Self.contractID,
            featureID: Self.featureID,
            operation: Self.operation,
            now      : clock.now()
        )
        let command: FileWorkspaceCommand
        do {
            command = try JSONDecoder().decode(FileWorkspaceCommand.self, from: binding.invocation.payload)
            try command.validate()
        } catch {
            _ = await broker.abandonInvocation(
                work.id,
                knownUnsent: true
            )
            throw Self.failure(.invalidPayload)
        }

        do {
            let snapshot = try await handler.handle(
                command,
                owner : binding.owner,
                source: binding.source
            )
            let response = try ServiceResponse(
                schemaVersion: 1,
                contractID   : Self.contractID,
                operation    : Self.operation,
                payload      : snapshot.encode()
            )
            return try await broker.completeInvocation(
                work.id,
                response: response,
                now     : clock.now()
            )
        } catch {
            _ = await broker.finishConsumedInvocationAsUnknown(work.id)
            if error is CancellationError { throw error }
            if let workspaceError = error as? FileWorkspaceError { throw workspaceError }
            if let failure = error as? AddonFailure { throw Self.failure(failure.code) }
            throw Self.failure(.invalidPayload)
        }
    }

    private static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(code: code, reason: "The file workspace host boundary rejected this operation.")
    }
}
