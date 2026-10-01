//
//  AddonHealthSnapshot.swift
//  CascadeKit
//

/// AddonHealthSnapshot exposes bounded diagnostic state without exposing mutable
/// policy or the store's host-issued session and retry credentials.
public struct AddonHealthSnapshot: Equatable, Sendable {

    public let isQuarantined        : Bool
    public let moderateIncidentCount: Int
    public let crashRetryCount      : Int
    public let hasPendingRetry      : Bool
}
