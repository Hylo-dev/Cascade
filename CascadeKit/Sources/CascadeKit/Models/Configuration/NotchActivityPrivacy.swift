//
//  NotchActivityPrivacy.swift
//  CascadeKit
//

/// Explicit content classification. Sensitive factories are skipped until the
/// person opts in; the host supplies an innocuous placeholder instead.
public nonisolated enum NotchActivityPrivacy: Sendable {
    case standard
    case sensitive
}
