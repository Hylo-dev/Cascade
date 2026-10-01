//
//  FocusInitializationMode.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation

/// FocusInitializationMode separates a fresh assignment from a resumed one: fresh is a
/// caller declaration that the host has no revision history for this assignment.
/// Resume never interprets missing storage as a new assignment.
public enum FocusInitializationMode: Sendable {

    case freshAssignment
    case resumeExisting
}
