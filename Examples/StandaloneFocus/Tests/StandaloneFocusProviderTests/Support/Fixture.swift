//
//  Fixture.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneFocusProvider
import Testing

struct Fixture: Sendable {

    let owner  : AddonID
    let id     : PublicationID
    let storage = Storage()
    let clock   = Clock()

    init() throws {
        owner = try #require(AddonID(rawValue: "org.cascade.examples.focus"))
        id    = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
    }

    func provider(
        _ mode  : FocusInitializationMode = .freshAssignment,
        duration: Double = 1500
    ) throws -> StandaloneFocusProvider {
        try StandaloneFocusProvider(
            expectedOwner: owner,
            publicationID: id,
            mode         : mode,
            duration     : duration,
            clock        : { clock.now() }
        )
    }

    func context() throws -> AddonContext {
        try AddonContext(
            services  : UnusedServices(),
            storage   : storage,
            generation: ConnectionGeneration(),
            grants    : []
        )
    }

    func action(
        _ name     : String,
        revision   : UInt64,
        requestID  : UUID = UUID(),
        input      : Data = Data(),
        deadline   : Date? = nil,
        publication: PublicationID? = nil
    ) throws -> ActionRequest {
        try ActionRequest(
            schemaVersion   : 1,
            requestID       : requestID,
            publicationID   : publication ?? id,
            actionID        : name,
            input           : input,
            deadline        : deadline ?? clock.now().addingTimeInterval(60),
            observedRevision: revision
        )
    }

    func refresh(_ provider: StandaloneFocusProvider) async throws -> Publication {
        let output = try await provider.handle(.refresh(id), context: context())

        return try #require(output.publications.first)
    }

    func send(
        _ request : ActionRequest,
        _ provider: StandaloneFocusProvider
    ) async throws -> ProviderOutput {
        let output = try await provider.handle(.action(request), context: context())
        try output.validateContext(
            authenticatedAddonID: owner,
            expectedCompletion  : .action(requestID: request.requestID),
            previousRevisions   : [:]
        )
        #expect(output.checkpoint == nil)

        return output
    }
}
