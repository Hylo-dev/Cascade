//
//  SwiftDataArchiveStatus.swift
//  CascadeKit
//

/// SwiftDataArchiveStatus describes logical availability, never physical database closure.
struct SwiftDataArchiveStatus: Equatable, Sendable {

    enum State: Equatable, Sendable {

        case unavailable
        case ready
        case overbudget
        case suspended
        case faulted
    }

    let state             : State
    let measuredBytes     : Int
    let ownerOverageBytes : Int
    let globalOverageBytes: Int
    let isBusy            : Bool
}
