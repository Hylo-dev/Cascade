//
//  ServiceSourceBinding.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import OSLog

struct ServiceSourceBinding: Sendable {
    let sourceID: UUID
    let key: ServiceRegistry.SourceKey
    let deadline: Duration
    let startConsumed: Bool
    let restartRequired: Bool
}
