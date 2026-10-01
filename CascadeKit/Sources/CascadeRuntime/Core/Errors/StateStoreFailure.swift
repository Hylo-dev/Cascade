//
//  StateStoreFailure.swift
//  CascadeKit
//

public enum StateStoreFailure: Error, Equatable, Sendable {

    case unsafePath
    case unrecognizedEntry
    case oversized
    case corrupt
    case invalidOwner
    case invalidTicket
    case staleRevision
    case quotaExceeded
    case busy
    case closed
    case invalidConfiguration
    case missingState
    case futureSchema(UInt32)
    case io          (Int32)
}
