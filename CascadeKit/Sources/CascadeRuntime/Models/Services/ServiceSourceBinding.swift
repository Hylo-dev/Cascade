//
//  ServiceSourceBinding.swift
//  CascadeKit
//

import Foundation

struct ServiceSourceBinding: Sendable {

    let sourceID       : UUID
    let key            : ServiceRegistry.SourceKey
    let deadline       : Duration
    let startConsumed  : Bool
    let restartRequired: Bool
}
