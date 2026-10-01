//
//  ServiceControlAction.swift
//  CascadeKit
//

import Foundation

/// ServiceControlAction is consumer syntax with no owner, permission, partition
/// or lifetime authority.
public enum ServiceControlAction: Equatable, Sendable {

    case acquire    (OperationRequest)
    case subscribe  (requirementID: String, grantID: UUID)
    case unsubscribe(subscriptionID: UUID)
}
