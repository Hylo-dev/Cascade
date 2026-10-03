//
//  CaffeinateSessionSnapshot.swift
//  Cascade
//

import Foundation

/// CaffeinateSessionSnapshot separates a live hold from identifiers retained after a native
/// timeout. Expired identifiers still need releasing, but must never show the widget as on.
nonisolated struct CaffeinateSessionSnapshot: Sendable {

    let isActive        : Bool
    let hasResources    : Bool
    let keepDisplayAwake: Bool
    let until           : Date?
}
