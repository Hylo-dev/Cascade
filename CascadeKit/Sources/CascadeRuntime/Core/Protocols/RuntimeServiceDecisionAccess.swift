//
//  RuntimeServiceDecisionAccess.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeServiceDecisionAccess delays only broker decision returns needed for stale-authority tests.
/// Its target identity prevents a wrapper from substituting a second broker authority.
protocol RuntimeServiceDecisionAccess: Sendable {

    var serviceBrokerTarget: ServiceBroker { get }

    func consumeInvocation(
        _ id: UUID,
        now : RuntimeInstant
    ) async throws -> UUID

    func consumeSourceStart(
        _ id: UUID,
        now : RuntimeInstant
    ) async throws -> ServiceSourceDescriptor

    func prepareInvocationCompletion(
        _ id      : UUID,
        response  : ServiceResponse,
        receivedAt: RuntimeInstant
    ) async throws -> ServiceBroker.CompletionPreparation

    func nextDeadline() async -> Duration?
}
