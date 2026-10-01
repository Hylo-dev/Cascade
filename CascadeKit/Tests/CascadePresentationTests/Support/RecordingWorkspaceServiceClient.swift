//
//  RecordingWorkspaceServiceClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

actor RecordingWorkspaceServiceClient: AddonServiceClient {
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
