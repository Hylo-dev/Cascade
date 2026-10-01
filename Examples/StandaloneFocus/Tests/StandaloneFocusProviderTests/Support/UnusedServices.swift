//
//  UnusedServices.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneFocusProvider
import Testing

struct UnusedServices: AddonServiceClient {

    func invoke(
        _ invocation: ServiceInvocation,
        grant       : Grant
    ) async throws -> ServiceResponse {
        throw FocusError.invalidConfiguration
    }

    func subscribe(
        requirementID: String,
        grant        : Grant
    ) async throws -> UUID { throw FocusError.invalidConfiguration }

    func unsubscribe(subscriptionID: UUID) async throws { throw FocusError.invalidConfiguration }
}
