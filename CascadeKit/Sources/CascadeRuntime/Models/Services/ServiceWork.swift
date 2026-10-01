//
//  ServiceWork.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

public struct ServiceWork: Equatable, Sendable {

    public let id        : UUID
    public let sourceID  : UUID
    public let invocation: ServiceInvocation
    let effectiveDeadline: Duration
}
