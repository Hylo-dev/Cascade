//
//  MediaCommandCapabilities.swift
//  CascadeKit
//

/// MediaCommandCapabilities prevents the UI from advertising commands that the
/// current source cannot perform. Providers publish changes with the snapshot.
public nonisolated struct MediaCommandCapabilities: OptionSet, Sendable {

    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let togglePlayback = Self(rawValue: 1 << 0)
    public static let previousTrack  = Self(rawValue: 1 << 1)
    public static let nextTrack      = Self(rawValue: 1 << 2)
    public static let seek           = Self(rawValue: 1 << 3)
    public static let favorite       = Self(rawValue: 1 << 4)
}
