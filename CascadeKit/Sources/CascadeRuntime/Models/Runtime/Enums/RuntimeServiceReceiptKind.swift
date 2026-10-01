//
//  RuntimeServiceReceiptKind.swift
//  CascadeKit
//

import Foundation

enum RuntimeServiceReceiptKind: Equatable, Sendable {

    case consumerReply
    case providerInvocation(workID: UUID)
}
