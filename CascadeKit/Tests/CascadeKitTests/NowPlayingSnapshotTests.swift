//
//  NowPlayingSnapshotTests.swift
//  CascadeKit
//

import Testing
import Foundation
@testable import CascadeKit

struct NowPlayingSnapshotTests {

    @Test
    func playbackUsesTimestampAndClampsAtTheEndOfTheTrack() {
        let snapshot = makeSnapshot(isPlaying: true, elapsed: 85)

        #expect(snapshot.position(at: Date(timeIntervalSince1970: 110)) == 95)
        #expect(snapshot.position(at: Date(timeIntervalSince1970: 120)) == 100)
    }

    @Test
    func pausedPlaybackDoesNotAdvanceOrRunBackwardWithClockChanges() {
        #expect(makeSnapshot(isPlaying: false, elapsed: 25).position(at: Date(timeIntervalSince1970: 120)) == 25)
        #expect(makeSnapshot(isPlaying: true, elapsed: 25).position(at: Date(timeIntervalSince1970: 90)) == 25)
    }

    @Test
    func invalidTimingCannotPoisonTheProgressView() {
        let snapshot = makeSnapshot(isPlaying: true, elapsed: .nan)

        #expect(snapshot.position(at: Date(timeIntervalSince1970: 110)) == 10)
    }

    private func makeSnapshot(
        isPlaying: Bool,
        elapsed  : TimeInterval
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            sourceBundleIdentifier: "example.player",
            title                 : "Track",
            artist                : "Artist",
            isPlaying             : isPlaying,
            duration              : 100,
            elapsed               : elapsed,
            timestamp             : Date(timeIntervalSince1970: 100),
            capabilities          : [.togglePlayback, .nextTrack]
        )
    }

    @Test
    func actualPlaybackRateControlsExtrapolationAndStillStopsAtDuration() {
        let snapshot = NowPlayingSnapshot(
            sourceBundleIdentifier: "example.player",
            title                 : "Track",
            artist                : "Artist",
            isPlaying             : true,
            duration              : 100,
            elapsed               : 60,
            timestamp             : Date(timeIntervalSince1970: 100),
            capabilities          : [.seek],
            playbackRate          : 2
        )

        #expect(snapshot.position(at: Date(timeIntervalSince1970: 110)) == 80)
        #expect(snapshot.position(at: Date(timeIntervalSince1970: 130)) == 100)
    }
}
