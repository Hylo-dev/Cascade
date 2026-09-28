//
//  ServiceRequestOutcome.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import OSLog

public enum ServiceRequestOutcome: Equatable, Sendable {
    case pending, dispatched, completed(ServiceResponse), unknown, unsent
}
