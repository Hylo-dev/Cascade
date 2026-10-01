//
//  AddonRuntimeServiceAdapter.swift
//  CascadeKit
//

import Foundation

protocol AddonRuntimeServiceAdapter: AddonRuntimeAdapter {

    func takeServiceIngress(
        _ handle   : RuntimeServiceIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data?

    func rejectServiceIngress(
        _ handle   : RuntimeServiceIngressHandle,
        incarnation: RuntimeIncarnation
    )

    func cancelServiceIngress(
        _ handle   : RuntimeServiceIngressHandle,
        incarnation: RuntimeIncarnation
    )

    func finishServiceIngress(
        _ handle   : RuntimeServiceIngressHandle,
        incarnation: RuntimeIncarnation
    )

    /// Synchronous disposal and terminal physical settlement, including revoked transport.
    func settleServiceExchange(_ settlement: RuntimeServiceSettlement)
}
