//
//  ServiceInvocationResult.swift
//  CascadeKit
//

import Foundation

/// ServiceInvocationResult is the outcome an invocation reply carries; refusal
/// means this exchange caused no new dispatch. A retained logical request may
/// already have run; refusal is not the SDK's rejected-before-handoff proof.
public enum ServiceInvocationResult: Equatable, Sendable {
    case completed(ServiceResponse)
    case refused(code: AddonFailure.Code, reason: String)
    case outcomeUnknown
}
