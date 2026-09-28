//
//  ServiceWork.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import OSLog

public struct ServiceWork: Equatable, Sendable {
    public let id: UUID
    public let sourceID: UUID
    public let invocation: ServiceInvocation
    let effectiveDeadline: Duration
}
