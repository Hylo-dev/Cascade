//
//  RuntimeAdapterDelivery.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeAdapterDelivery is the bounded synchronous handoff vocabulary of this cut.
enum RuntimeAdapterDelivery: Equatable, Sendable {
    case start(RuntimeStartDelivery)
    case action(ActionDispatcher.Delivery)
    case source(ServiceSourceDescriptor)
    case service(ServiceWork)
    case serviceInvocation(RuntimeServiceDelivery)
    case serviceReply(RuntimeServiceDelivery)
    case serviceControl(RuntimeServiceSubscriptionDelivery)
    case serviceSourceStart(RuntimeServiceSubscriptionDelivery)
    case serviceEvent(RuntimeServiceSubscriptionDelivery)
    case storageResponse(RuntimeStorageResponseDelivery)
    case assetResponse(RuntimeAssetResponseDelivery)
}
