//
//  KeyedStorageFailure.swift
//  CascadeKit
//

/// KeyedStorageFailure distinguishes precommit refusal from a visible but uncertain durable write.
enum KeyedStorageFailure: Error, Equatable, Sendable {

    case invalidConfiguration
    case invalidKey
    case oversized
    case invalidOwner
    case invalidTicket
    case closed
    case busy
    case unsafePath
    case unrecognizedEntry
    case corrupt
    case futureFormat
    case staleRevision
    case quotaExceeded
    case cleanupRequired
    case committedDurabilityUncertain
    case io(Int32)
}
