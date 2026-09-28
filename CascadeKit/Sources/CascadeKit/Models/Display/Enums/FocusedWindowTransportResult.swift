//
//  FocusedWindowTransportResult.swift
//  CascadeKit
//

import AppKit

/// FocusedWindowTransportResult keeps raw AX coordinates at the worker seam so
/// coordinate normalization remains explicit and independently testable.
nonisolated enum FocusedWindowTransportResult: Equatable, Sendable {

    case frameInAXCoordinates(CGRect)
    case unavailable
    case permissionDenied
}
