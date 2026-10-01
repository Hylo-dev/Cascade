//
//  ServiceDecision.swift
//  CascadeKit
//

import Foundation

public enum ServiceDecision: Equatable, Sendable {

    case startSource (UUID)
    case stopSource  (UUID)
    case wakeConsumer(VerifiedAddonIdentity)
}
