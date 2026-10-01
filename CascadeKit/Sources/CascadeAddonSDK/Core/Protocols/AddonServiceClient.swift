//
//  AddonServiceClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonServiceClient exposes broker requests with explicit grants and validated wire values.
/// The host and SDK transport behind it authenticates, correlates and bounds each response.
public protocol AddonServiceClient: Sendable {

    func invoke(
        _ invocation: ServiceInvocation,
        grant       : Grant
    ) async throws -> ServiceResponse

    func subscribe(
        requirementID: String,
        grant        : Grant
    ) async throws -> UUID

    func unsubscribe(subscriptionID: UUID) async throws
}
