//
//  DisplayIdentity.swift
//  CascadeKit
//

/// DisplayIdentity is the stable UUID-backed identity of a physical display.
///
/// CoreGraphics display identifiers only last for the current session. Keeping
/// the UUID as an opaque string lets a fixed routing choice and a software-notch
/// style survive reconnection without exposing CoreGraphics in persisted data.
@frozen
public nonisolated struct DisplayIdentity: RawRepresentable, Hashable, Codable, Sendable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
