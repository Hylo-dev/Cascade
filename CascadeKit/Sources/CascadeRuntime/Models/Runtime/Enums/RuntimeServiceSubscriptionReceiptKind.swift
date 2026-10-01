//
//  RuntimeServiceSubscriptionReceiptKind.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

enum RuntimeServiceSubscriptionReceiptKind: Equatable, Sendable {

    case control    (requestID: UUID, kind: ServiceControlKind, phase: ServiceControlPhase)
    case sourceStart(sourceID: UUID, startNonce: UUID)
    case event      (subscriptionID: UUID, bindingRevision: UInt64, cacheRevision: UInt64)
}
