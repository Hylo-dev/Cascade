//
//  ServiceBroker+RuntimeServiceDecisionAccess.swift
//  CascadeKit
//

extension ServiceBroker: RuntimeServiceDecisionAccess {

    nonisolated var serviceBrokerTarget: ServiceBroker { self }
}
