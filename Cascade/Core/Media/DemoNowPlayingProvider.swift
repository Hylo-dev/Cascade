//
//  DemoNowPlayingProvider.swift
//  Cascade
//

import CascadeKit
import Foundation

/// DemoNowPlayingProvider exercises the real activity contract without claiming
/// to read a music app. It is opt-in from the menu, has no timer and finishes
/// its stream when disabled. A production provider can replace this object.
@MainActor
final class DemoNowPlayingProvider: NowPlayingProviding {

    private var continuation: AsyncStream<NowPlayingSnapshot?>.Continuation?
    private var trackIndex   = 0
    private var isPlaying    = true
    private var elapsed     : TimeInterval = 24
    private var timestamp    = Date.now
    private let titles       = [
        String(localized: "A Moment of Calm"),
        String(localized: "Heading Home"),
        String(localized: "Morning Light"),
    ]

    func start() -> AsyncStream<NowPlayingSnapshot?> {
        stop()

        let pair = AsyncStream<NowPlayingSnapshot?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = pair.continuation
        timestamp    = .now

        publish()
        return pair.stream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
    }

    func send(_ command: MediaCommand) async throws {
        guard continuation != nil else { return }

        let now   = Date.now
        elapsed   = snapshot.position(at: now)
        timestamp = now

        switch command {
            case .togglePlayback:
                isPlaying.toggle()

            case .nextTrack:
                trackIndex = (trackIndex + 1) % titles.count
                elapsed    = 0

            case .previousTrack:
                trackIndex = (trackIndex + titles.count - 1) % titles.count
                elapsed    = 0

            case .seek(let seconds):
                guard seconds.isFinite else { return }
                elapsed = min(204, max(0, seconds))

            case .toggleFavorite:
                throw CocoaError(.featureUnsupported)
        }

        publish()
    }

    private var snapshot: NowPlayingSnapshot {
        NowPlayingSnapshot(
            sourceBundleIdentifier: "hylo.Cascade.demo",
            title                 : titles[trackIndex],
            artist                : String(localized: "Music Preview · Cascade"),
            isPlaying             : isPlaying,
            duration              : 204,
            elapsed               : elapsed,
            timestamp             : timestamp,
            capabilities          : [.togglePlayback, .previousTrack, .nextTrack, .seek]
        )
    }

    private func publish() {
        continuation?.yield(snapshot)
    }
}
