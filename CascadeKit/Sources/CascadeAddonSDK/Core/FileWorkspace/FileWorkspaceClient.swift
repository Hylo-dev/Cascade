//
//  FileWorkspaceClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// FileWorkspaceClient sends bounded shelf commands through one explicit connection grant.
public struct FileWorkspaceClient: Sendable {

    private static let contractID = "files.workspace"
    private static let featureID  = "workspace"
    private static let operation  = "command"

    private let services: any AddonServiceClient
    private let grant   : Grant
    private let now     : @Sendable () -> Date

    public init(
        services: any AddonServiceClient,
        grant   : Grant,
        now     : @escaping @Sendable () -> Date = Date.init
    ) throws {
        try grant.validate()
        try grant.scope.validate()

        self.services = services
        self.grant    = grant
        self.now      = now
    }

    /// send validates both envelopes and decodes only the bounded public snapshot.
    public func send(_ command: FileWorkspaceCommand) async throws -> FileWorkspaceSnapshot {
        guard grant.serviceID == Self.contractID,
              grant.scope.featureID == Self.featureID,
              grant.scope.operation == Self.operation
        else {
            throw Self.failure(.permissionDenied)
        }

        try command.validate()
        let payload = try JSONEncoder().encode(command)

        let invocation: ServiceInvocation
        do {
            invocation = try ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : Self.contractID,
                operation    : Self.operation,
                payload      : payload,
                deadline     : now().addingTimeInterval(30)
            )
        } catch {
            throw Self.failure(.invalidPayload)
        }

        let response = try await services.invoke(invocation, grant: grant)

        do {
            try response.validate()
            guard response.contractID == Self.contractID,
                  response.operation == Self.operation
            else {
                throw Self.failure(.invalidPayload)
            }

            return try FileWorkspaceSnapshot.decode(response.payload)
        } catch let failure as AddonFailure {
            throw failure
        } catch {
            throw Self.failure(.invalidPayload)
        }
    }

    private static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(
            code  : code,
            reason: "The file workspace service rejected this operation."
        )
    }
}
