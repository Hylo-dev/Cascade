//
//  FailingServices.swift
//  StandaloneClock
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneClockProvider
import Testing

struct FailingServices: AddonServiceClient {

    func invoke(
        _ invocation: ServiceInvocation,
        grant       : Grant
    ) async throws -> ServiceResponse {
        throw UnexpectedCapability.call
    }

    func subscribe(
        requirementID: String,
        grant        : Grant
    ) async throws -> UUID {
        throw UnexpectedCapability.call
    }

    func unsubscribe(subscriptionID: UUID) async throws { throw UnexpectedCapability.call }
}
