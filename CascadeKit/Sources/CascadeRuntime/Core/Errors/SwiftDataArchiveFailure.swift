//
//  SwiftDataArchiveFailure.swift
//  CascadeKit
//

import Foundation

/// SwiftDataArchiveFailure distinguishes rejected operations from committed save outcomes.
enum SwiftDataArchiveFailure: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidGeneration
    case unavailable
    case busy
    case unsafePath
    case staleRevision
    case corrupt
    case futureFormat
    case accounting
    case cancelled
}
