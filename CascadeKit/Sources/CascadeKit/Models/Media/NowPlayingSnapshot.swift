//
//  NowPlayingSnapshot.swift
//  CascadeKit
//

import Foundation

/// NowPlayingSnapshot is a provider-neutral, lightweight playback update.
/// The timestamp lets a visible progress view extrapolate without polling the
/// player. Missing duration denotes a stream; invalid timing is normalized at
/// this boundary so it never reaches layout or progress calculations.
public nonisolated struct NowPlayingSnapshot: Equatable, Sendable {

    public let sourceBundleIdentifier: String
    public let title                 : String
    public let artist                : String
    public let isPlaying             : Bool
    public let duration              : TimeInterval?
    public let elapsed               : TimeInterval
    public let timestamp             : Date
    public let capabilities          : MediaCommandCapabilities
    public let artworkData           : Data?
    public let trackIdentifier       : String?
    public let isFavorite            : Bool?
    public let playbackRate          : Double

    public init(
        sourceBundleIdentifier: String,
        title                 : String,
        artist                : String,
        isPlaying             : Bool,
        duration              : TimeInterval?,
        elapsed               : TimeInterval,
        timestamp             : Date,
        capabilities          : MediaCommandCapabilities,
        artworkData           : Data? = nil,
        trackIdentifier       : String? = nil,
        isFavorite            : Bool? = nil,
        playbackRate          : Double = 1
    ) {
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.title                  = title
        self.artist                 = artist
        self.isPlaying              = isPlaying
        self.duration               = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.elapsed                = elapsed.isFinite ? max(0, elapsed) : 0
        self.timestamp              = timestamp.timeIntervalSince1970.isFinite ? timestamp : .now
        self.capabilities           = capabilities
        self.artworkData            = artworkData.flatMap { $0.count <= 8 * 1_024 * 1_024 ? $0 : nil }
        self.trackIdentifier        = trackIdentifier
        self.isFavorite             = isFavorite
        self.playbackRate           = playbackRate.isFinite && playbackRate >= 0 ? playbackRate : 1
    }

    public func position(at date: Date) -> TimeInterval {
        let delta    = date.timeIntervalSince(timestamp)
        let advance  = isPlaying && delta.isFinite ? max(0, delta) * playbackRate : 0
        let position = elapsed + advance

        return duration.map { min(position, $0) } ?? position
    }
}
