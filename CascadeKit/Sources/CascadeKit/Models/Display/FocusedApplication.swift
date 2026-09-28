//
//  FocusedApplication.swift
//  CascadeKit
//

import AppKit

/// FocusedApplication is the small, Sendable identity needed for an AX lookup.
nonisolated struct FocusedApplication: Equatable, Sendable {

    let processID       : pid_t
    let bundleIdentifier: String?
}
