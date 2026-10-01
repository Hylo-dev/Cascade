//
//  ServiceControlResult.swift
//  CascadeKit
//

import Foundation

/// ServiceControlResult is the outcome a control reply carries; accepted
/// acknowledges committed intent, not readiness. refused asserts pre-effect refusal,
/// never SDK request-side non-exposure. Lifecycle ordering is external.
public enum ServiceControlResult: Equatable, Sendable {

    case accepted
    case acquired  (Grant)
    case subscribed(UUID)
    case acknowledged
    case refused(code: AddonFailure.Code, reason: String)
    case outcomeUnknown
}
