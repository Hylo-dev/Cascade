//
//  FileWorkspaceClientTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

@Suite struct FileWorkspaceClientTests {
    @Test func sendsBoundedCommandWithExplicitWorkspaceGrant() async throws {
        let instant = Date(timeIntervalSince1970: 1_000)
        let snapshot = try FileWorkspaceSnapshot(
            revision  : 7,
            entries   : [],
            totalCount: 0,
            nextCursor: nil,
            jobs      : []
        )
        let services = try RecordingWorkspaceServiceClient(
            response: ServiceResponse(
                schemaVersion: 1,
                contractID   : "files.workspace",
                operation    : "command",
                payload      : snapshot.encode()
            )
        )
        let grant = try workspaceGrant()
        let client = try FileWorkspaceClient(
            services: services,
            grant   : grant,
            now     : { instant }
        )

        #expect(try await client.send(.list(cursor: "next")) == snapshot)
        let request = try #require(await services.lastRequest)
        #expect(request.grant == grant)
        #expect(request.invocation.contractID == "files.workspace")
        #expect(request.invocation.operation == "command")
        #expect(request.invocation.deadline == instant.addingTimeInterval(30))
        #expect(try JSONDecoder().decode(FileWorkspaceCommand.self, from: request.invocation.payload)
            == .list(cursor: "next"))
    }

    @Test(arguments: ["other.service", "otherOperation"])
    func rejectsMismatchedResponseEnvelope(_ changedValue: String) async throws {
        let snapshot = try FileWorkspaceSnapshot(
            revision  : 0,
            entries   : [],
            totalCount: 0,
            nextCursor: nil,
            jobs      : []
        )
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : changedValue == "other.service" ? changedValue : "files.workspace",
            operation    : changedValue == "otherOperation" ? changedValue : "command",
            payload      : snapshot.encode()
        )
        let client = try FileWorkspaceClient(
            services: RecordingWorkspaceServiceClient(response: response),
            grant   : workspaceGrant(),
            now     : { Date(timeIntervalSince1970: 1_000) }
        )

        await #expect(throws: AddonFailure.self) {
            _ = try await client.send(.list(cursor: nil))
        }
    }

    @Test func rejectsMalformedSnapshotResponse() async throws {
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : "files.workspace",
            operation    : "command",
            payload      : Data("{}".utf8)
        )
        let client = try FileWorkspaceClient(
            services: RecordingWorkspaceServiceClient(response: response),
            grant   : workspaceGrant(),
            now     : { Date(timeIntervalSince1970: 1_000) }
        )

        await #expect(throws: (any Error).self) {
            _ = try await client.send(.list(cursor: nil))
        }
    }

    @Test func rejectsWrongGrantBeforeInvokingTransport() async throws {
        let services = try RecordingWorkspaceServiceClient(
            response: ServiceResponse(
                schemaVersion: 1,
                contractID   : "files.workspace",
                operation    : "command",
                payload      : FileWorkspaceSnapshot(
                    revision  : 0,
                    entries   : [],
                    totalCount: 0,
                    nextCursor: nil,
                    jobs      : []
                ).encode()
            )
        )
        let wrongGrant = try workspaceGrant(featureID: "other")
        let client = try FileWorkspaceClient(
            services: services,
            grant   : wrongGrant,
            now     : { Date(timeIntervalSince1970: 1_000) }
        )

        await #expect(throws: AddonFailure.self) {
            _ = try await client.send(.list(cursor: nil))
        }
        #expect(await services.lastRequest == nil)
    }
}

private actor RecordingWorkspaceServiceClient: AddonServiceClient {
    struct Request: Sendable {
        let invocation: ServiceInvocation
        let grant     : Grant
    }

    let response: ServiceResponse
    private(set) var lastRequest: Request?

    init(response: ServiceResponse) {
        self.response = response
    }

    func invoke(_ invocation: ServiceInvocation, grant: Grant) async throws -> ServiceResponse {
        lastRequest = Request(
            invocation: invocation,
            grant     : grant
        )
        return response
    }

    func subscribe(requirementID: String, grant: Grant) async throws -> UUID {
        throw AddonFailure(code: .dependencyUnavailable, reason: "Subscriptions are outside this test.")
    }

    func unsubscribe(subscriptionID: UUID) async throws {
        throw AddonFailure(code: .dependencyUnavailable, reason: "Subscriptions are outside this test.")
    }
}

private func workspaceGrant(featureID: String = "workspace") throws -> Grant {
    try Grant(
        id        : UUID(),
        owner     : #require(AddonID(rawValue: "com.example.workspace")),
        serviceID : "files.workspace",
        scope     : ServiceScope(
            featureID: featureID,
            operation: "command"
        ),
        expiresAt : Date(timeIntervalSince1970: 2_000),
        generation: ConnectionGeneration(),
        cost      : AddonResourceRequest(
            profile              : .eventDriven,
            requestedMemoryMiB   : 0,
            maximumConcurrentWork: 1,
            background           : .none
        )
    )
}
