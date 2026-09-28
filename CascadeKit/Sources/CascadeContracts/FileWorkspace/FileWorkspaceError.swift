//
//  FileWorkspaceError.swift
//  Cascade
//

/// FileWorkspaceError is a stable code suitable for transport without private failure details.
public enum FileWorkspaceError: String, Error, Codable, Equatable, Sendable {
    case unavailable, permissionDenied, unsupported, quotaExceeded, staleRevision, interrupted, ioFailure
}
