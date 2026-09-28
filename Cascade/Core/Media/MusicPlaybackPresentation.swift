//
//  MusicPlaybackPresentation.swift
//  Cascade
//

import CascadeKit
import Foundation
import Observation

/// MusicPlaybackPresentation holds local feedback that never changes the
/// provider snapshot or drives audio capture. An intent survives delayed reads,
/// then yields to confirmation, failure, a different track, or a bounded
/// confirmation deadline.
@MainActor
@Observable
final class MusicPlaybackPresentation {

    private(set) var confirmed        : NowPlayingSnapshot
    private(set) var pendingCapability: MediaCommandCapabilities?
    private(set) var commandError     : String?

    private var preview: NowPlayingSnapshot?
    private var token  : UUID?

    @ObservationIgnored
    private var confirmationTask   : Task<Void, Never>?
    @ObservationIgnored
    private let confirmationTimeout: Duration

    var displayed: NowPlayingSnapshot { preview ?? confirmed }

    init(
        snapshot           : NowPlayingSnapshot,
        confirmationTimeout: Duration = .seconds(2)
    ) {
        confirmed                = snapshot
        self.confirmationTimeout = confirmationTimeout
    }

    func begin(
        _ command : MediaCommand,
        capability: MediaCommandCapabilities,
        at date   : Date = .now
    ) -> UUID? {
        guard token == nil else { return nil }

        let id            = UUID()
        token             = id
        pendingCapability = capability
        commandError      = nil

        var playing  = confirmed.isPlaying
        var position = confirmed.position(at: date)
        var favorite = confirmed.isFavorite

        switch command {
            case .togglePlayback: playing.toggle()
            case .seek(let seconds): position = min(confirmed.duration ?? position, max(0, seconds))
            case .toggleFavorite: favorite = favorite.map { !$0 }
            case .nextTrack, .previousTrack: return id
        }

        preview = NowPlayingSnapshot(
            sourceBundleIdentifier: confirmed.sourceBundleIdentifier,
            title                 : confirmed.title,
            artist                : confirmed.artist,
            isPlaying             : playing,
            duration              : confirmed.duration,
            elapsed               : position,
            timestamp             : date,
            capabilities          : confirmed.capabilities,
            artworkData           : confirmed.artworkData,
            trackIdentifier       : confirmed.trackIdentifier,
            isFavorite            : favorite,
            playbackRate          : confirmed.playbackRate
        )
        return id
    }

    func receive(_ snapshot: NowPlayingSnapshot) {
        let changedTrack = confirmed.sourceBundleIdentifier != snapshot.sourceBundleIdentifier
            || confirmed.trackIdentifier != snapshot.trackIdentifier
            || confirmed.title != snapshot.title || confirmed.artist != snapshot.artist

        confirmed = snapshot
        if changedTrack || snapshot.capabilities.isEmpty {
            clear()
            commandError = nil
        } else if isConfirmed {
            clear()
        }
    }

    func succeed(_ id: UUID) {
        guard token == id else { return }
        guard preview != nil, !isConfirmed else { clear(); return }

        confirmationTask?.cancel()
        confirmationTask = Task { [weak self, confirmationTimeout] in
            do { try await Task.sleep(for: confirmationTimeout) } catch { return }
            guard let self, self.token == id else { return }

            self.clear()
        }
    }

    func fail(_ id: UUID) {
        guard token == id else { return }

        clear()
        commandError = "Comando non riuscito. Riprova."
    }

    private var isConfirmed: Bool {
        guard let preview, confirmed.timestamp >= preview.timestamp else { return false }

        switch pendingCapability {
            case .togglePlayback: return preview.isPlaying == confirmed.isPlaying
            case .favorite: return preview.isFavorite == confirmed.isFavorite
            case .seek: return abs(preview.position(at: confirmed.timestamp) - confirmed.elapsed) < 2
            default: return false
        }
    }

    private func clear() {
        confirmationTask?.cancel()
        confirmationTask = nil

        preview           = nil
        pendingCapability = nil
        token             = nil
    }
}
