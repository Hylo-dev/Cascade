//
//  WorkspaceAuthorityFixture.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

struct WorkspaceAuthorityFixture {

    struct Admission {

        let permissionID: UUID
        let session     : ServiceSession
        let acquisition : ServiceAcquisition
    }

    let builtin : VerifiedAddonIdentity
    let external: VerifiedAddonIdentity
    let provider: VerifiedAddonIdentity

    let now = RuntimeInstant(wall: Date(timeIntervalSince1970: 1_000), monotonic: .seconds(10))

    let snapshot: FileWorkspaceSnapshot

    init() throws {
        builtin = VerifiedAddonIdentity(
            publisher: "cascade",
            addonID  : try #require(AddonID(rawValue: "com.example.builtin"))
        )
        external = VerifiedAddonIdentity(
            publisher: "outside",
            addonID  : try #require(AddonID(rawValue: "com.example.external"))
        )
        provider = VerifiedAddonIdentity(
            publisher: "cascade",
            addonID  : try #require(AddonID(rawValue: "com.example.files"))
        )
        snapshot = try FileWorkspaceSnapshot(
            revision  : 4,
            entries   : [],
            totalCount: 0,
            nextCursor: nil,
            jobs      : []
        )
    }

    func admit(
        consumer: VerifiedAddonIdentity,
        broker  : ServiceBroker
    ) async throws -> Admission {
        let permission = HostServicePermission(
            consumer             : consumer,
            binding              : ServiceBinding(
                requirementID   : "files",
                consumer        : consumer.addonID,
                provider        : provider.addonID,
                providerIdentity: provider,
                contractVersion : SemanticVersion(1, 0, 0),
                digest          : "sha256-workspace",
                featureID       : "workspace"
            ),
            serviceID            : "files.workspace",
            partition            : "account",
            operation            : "command",
            crossPublisherConsent: true
        )

        let permissionID = try await broker.authorize(permission)
        let session      = try await broker.registerSession(identity: consumer)
        let acquisition  = try await broker.acquire(
            session      : session,
            requirementID: "files",
            scope        : ServiceScope(featureID: "workspace", operation: "command"),
            now          : now,
            lifetime     : .seconds(30)
        )

        return Admission(
            permissionID: permissionID,
            session     : session,
            acquisition : acquisition
        )
    }

    func work(
        broker : ServiceBroker,
        session: ServiceSession,
        grant  : Grant,
        command: FileWorkspaceCommand
    ) async throws -> ServiceWork {
        try await work(
            broker : broker,
            session: session,
            grant  : grant,
            payload: JSONEncoder().encode(command)
        )
    }

    func work(
        broker : ServiceBroker,
        session: ServiceSession,
        grant  : Grant,
        payload: Data
    ) async throws -> ServiceWork {
        try await broker.beginInvocation(
            session   : session,
            grantID   : grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "files.workspace",
                operation    : "command",
                payload      : payload,
                deadline     : now.wall.addingTimeInterval(20)
            ),
            now       : now
        )
    }

    func oversizedSnapshot() throws -> FileWorkspaceSnapshot {
        let entries = try (0..<32).map { index in
            try FileWorkspaceEntry(
                id              : UUID(),
                name            : String(repeating: "x", count: 4_096),
                typeIdentifier  : "public.data",
                availability    : .available,
                ownership       : .managed,
                thumbnailAssetID: nil
            )
        }

        return try FileWorkspaceSnapshot(
            revision  : 5,
            entries   : entries,
            totalCount: entries.count,
            nextCursor: nil,
            jobs      : []
        )
    }
}
