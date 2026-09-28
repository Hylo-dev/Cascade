//
//  KeyedStorageFailure.swift
//  CascadeKit
//

import CryptoKit
import Foundation

/// KeyedStorageFailure distinguishes precommit refusal from a visible but uncertain durable write.
enum KeyedStorageFailure: Error, Equatable, Sendable {
    case invalidConfiguration, invalidKey, oversized, invalidOwner, invalidTicket
    case closed, busy, unsafePath, unrecognizedEntry, corrupt, futureFormat
    case staleRevision, quotaExceeded, cleanupRequired, committedDurabilityUncertain
    case io(Int32)
}
