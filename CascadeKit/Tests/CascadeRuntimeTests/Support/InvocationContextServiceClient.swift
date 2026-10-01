//
//  InvocationContextServiceClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// InvocationContextServiceClient is TEST ONLY: it adapts the real invocation exchange to the
/// existing context container.
/// Subscription/control operations are outside this fixture, which claims no coverage of them.
struct InvocationContextServiceClient: AddonServiceClient {
    private enum UnsupportedFixtureOperation: Error { case subscribe, unsubscribe }
    let exchange: ServiceInvocationExchange

    func invoke(_ invocation: ServiceInvocation, grant: Grant) async throws -> ServiceResponse {
        switch try await exchange.invoke(grantID: grant.id, invocation: invocation) {
        case .completed(let response): return response
        case .refused(let code, let reason): throw AddonFailure(code: code, reason: reason)
        case .outcomeUnknown:
            throw AddonFailure(code: .outcomeUnknown, reason: "The service invocation outcome is unknown.")
        }
    }

    func subscribe(requirementID: String, grant: Grant) async throws -> UUID {
        throw UnsupportedFixtureOperation.subscribe
    }

    func unsubscribe(subscriptionID: UUID) async throws {
        throw UnsupportedFixtureOperation.unsubscribe
    }
}
