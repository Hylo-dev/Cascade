//
//  ServiceDecision.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import OSLog

public enum ServiceDecision: Equatable, Sendable {
    case startSource(UUID)
    case stopSource(UUID)
    case wakeConsumer(VerifiedAddonIdentity)
}
