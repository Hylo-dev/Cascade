//
//  AddonRuntimeAssetAdapter.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonRuntimeAssetAdapter refines the same single ingress slot with raw asset frames.
/// Staging owns a compact bounded copy under launch capacity; no response history is retained.
/// Publication, storage and asset frames share one slot. Reject disposes only staged bytes;
/// cancel/finish require the successful taker's exact handle. Receipt applies only to accepted
/// delivery, never a runtime-only reservation. Stop/exit follow the base transport's rules.
protocol AddonRuntimeAssetAdapter: AddonRuntimeAdapter {
    func takeAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> Data?
    func rejectAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    )
    func cancelAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    )
    func finishAssetIngress(
        _ handle   : RuntimeAssetIngressHandle,
        incarnation: RuntimeIncarnation
    )
}
