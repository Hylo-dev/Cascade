//
//  SpotlightWindowSnapshot.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices

/// SpotlightWindowSnapshot carries geometry and focus, never search text or
/// results. Only a focused, positioned, settled native field can accept keys.
nonisolated struct SpotlightWindowSnapshot: Sendable {

    let generation: UInt64
    let processID : pid_t
    let isVisible : Bool
    let isFocused : Bool?
    let isSettled : Bool
    let isReady   : Bool
    let frame     : CGRect?
}
