//
//  StateStoreFailure.swift
//  CascadeKit
//

import Foundation

public enum StateStoreFailure: Error, Equatable, Sendable {
    case unsafePath, unrecognizedEntry, oversized, corrupt, invalidOwner, invalidTicket
    case staleRevision, quotaExceeded, busy, closed, invalidConfiguration, missingState
    case futureSchema(UInt32)
    case io(Int32)
}
