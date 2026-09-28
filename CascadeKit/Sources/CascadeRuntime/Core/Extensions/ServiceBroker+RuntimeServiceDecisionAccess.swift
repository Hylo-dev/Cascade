//
//  ServiceBroker+RuntimeServiceDecisionAccess.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

extension ServiceBroker: RuntimeServiceDecisionAccess {
    nonisolated var serviceBrokerTarget: ServiceBroker { self }
}
