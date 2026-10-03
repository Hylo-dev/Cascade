//
//  AddonRuntimeOptionsAdapter.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonRuntimeOptionsAdapter is a bounded synchronous projection seam. A connected
/// adapter owns the canonical host origin registry and rechecks it after any actor hop.
/// It must never block for UI/IPC or recursively enter runtime. Returning false means
/// nothing was retained or shown. The production launcher hold remains independent.
protocol AddonRuntimeOptionsAdapter: Sendable {

    func accepts(_ origin: AddonOptionsOrigin) -> Bool
    func present(_ presentation: AddonOptionsPresentation) -> Bool
    func invalidateControls(leaseID: UUID, origin: AddonOptionsOrigin)
    func dismiss(leaseID: UUID, origin: AddonOptionsOrigin)
}
