//
//  RuntimeServiceReceiptKind.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

enum RuntimeServiceReceiptKind: Equatable, Sendable {
    case consumerReply
    case providerInvocation(workID: UUID)
}
