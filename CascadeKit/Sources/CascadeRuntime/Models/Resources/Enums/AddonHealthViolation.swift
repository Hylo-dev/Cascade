//
//  AddonHealthViolation.swift
//  CascadeKit
//

/// AddonHealthViolation classifies already-established host observations. This
/// state machine does not read process metrics or terminate a native process.
public enum AddonHealthViolation: Sendable {

    case moderate
    case severe
}
