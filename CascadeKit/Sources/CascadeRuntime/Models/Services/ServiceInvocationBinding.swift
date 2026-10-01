//
//  ServiceInvocationBinding.swift
//  CascadeKit
//

import CascadeContracts

/// ServiceInvocationBinding is a one-call projection of canonically consumed work.
struct ServiceInvocationBinding: Sendable {

    let owner     : VerifiedAddonIdentity
    let source    : ServiceSourceDescriptor
    let invocation: ServiceInvocation
}
