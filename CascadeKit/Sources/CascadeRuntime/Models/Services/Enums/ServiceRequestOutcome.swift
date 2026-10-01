//
//  ServiceRequestOutcome.swift
//  CascadeKit
//

import CascadeContracts

public enum ServiceRequestOutcome: Equatable, Sendable {

    case pending
    case dispatched
    case completed(ServiceResponse)
    case unknown
    case unsent
}
