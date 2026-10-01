//
//  AddonHealthDecision.swift
//  CascadeKit
//

/// AddonHealthDecision tells the runtime whether the current process may remain,
/// must stop, is quarantined, or has one crash retry for the common deadline queue.
public enum AddonHealthDecision: Equatable, Sendable {

    case keep
    case stop
    case quarantine
    case retryAt(AddonRetryTicket)
}
