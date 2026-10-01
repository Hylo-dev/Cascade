//
//  ServiceSubscriptionBinding.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// ServiceSubscriptionBinding holds value projections only. Callers must ask the broker again after
/// suspension.
struct ServiceSubscriptionBinding: Sendable {

    let grant       : Grant
    let permissionID: UUID
    let interestID  : UUID
    let sourceID    : UUID
    let key         : ServiceRegistry.SourceKey
    let deadline    : Duration
}
