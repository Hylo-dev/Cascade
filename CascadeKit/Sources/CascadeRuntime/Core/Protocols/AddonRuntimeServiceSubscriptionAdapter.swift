//
//  AddonRuntimeServiceSubscriptionAdapter.swift
//  CascadeKit
//

/// AddonRuntimeServiceSubscriptionAdapter carries cumulative subscription transport over the same
/// physical ingress/delivery slots. Receipts release staging before SDK event handlers run; handoff
/// never calls user code.
protocol AddonRuntimeServiceSubscriptionAdapter: AddonRuntimeServiceAdapter {}
