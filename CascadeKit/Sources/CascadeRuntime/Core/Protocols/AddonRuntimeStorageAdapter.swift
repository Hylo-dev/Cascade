//
//  AddonRuntimeStorageAdapter.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonRuntimeStorageAdapter refines the same single ingress slot with raw storage frames.
/// Staging owns a compact bounded copy under launch capacity; no response history is retained.
/// Publication and storage share one slot. Reject disposes only staged bytes; cancel/finish
/// require the successful taker's exact handle. Receipt applies only to accepted delivery,
/// never a runtime-only reservation. Stop/exit follow the base transport's synchronous rules.
protocol AddonRuntimeStorageAdapter: AddonRuntimeAdapter {
    func takeStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data?
    func rejectStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    )
    func cancelStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    )
    func finishStorageIngress(
        _ handle   : RuntimeStorageIngressHandle,
        incarnation: RuntimeIncarnation
    )
}
