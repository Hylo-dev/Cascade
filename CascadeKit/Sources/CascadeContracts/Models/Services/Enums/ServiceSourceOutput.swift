//
//  ServiceSourceOutput.swift
//  CascadeKit
//

import Foundation

public enum ServiceSourceOutput: Equatable, Sendable {

    case startupCompleted
    case sourceUpdate(ServiceResponse)
}
