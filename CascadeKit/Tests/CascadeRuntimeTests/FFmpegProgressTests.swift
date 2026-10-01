//
//  FFmpegProgressTests.swift
//  CascadeKit
//

import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct FFmpegProgressTests {

    @Test
    func arbitraryChunkBoundariesPreserveTheLatestCompleteObservation() {
        let report   = Data("out_time_us=2500000\r\nprogress=continue\r\n".utf8)
        let expected = FFmpegProgressParser.Observation(fraction: 0.25, marker: .continuing)

        for boundary in 0...report.count {
            var parser = FFmpegProgressParser(durationSeconds: 10)
            var latest: FFmpegProgressParser.Observation?

            for chunk in [report.prefix(boundary), report.suffix(report.count - boundary)] {
                latest = parser.consume(Data(chunk)) ?? latest
            }

            latest = parser.finish() ?? latest
            #expect(latest == expected)
        }

        var byteParser = FFmpegProgressParser(durationSeconds: 10)
        var byteLatest: FFmpegProgressParser.Observation?

        for byte in report {
            byteLatest = byteParser.consume(Data([byte])) ?? byteLatest
        }

        #expect(byteLatest == expected)
    }

    @Test
    func oneChunkCoalescesRecordsWithoutLosingTheNewestProgress() {
        var parser      = FFmpegProgressParser(durationSeconds: 10)
        let observation = parser.consume(
            Data(
                "out_time_us=1000000\nprogress=continue\n"
                    .appending("out_time_us=4000000\nprogress=continue\n")
                    .utf8
            )
        )

        #expect(observation == FFmpegProgressParser.Observation(fraction: 0.4, marker: .continuing))
    }

    @Test
    func canonicalMicrosecondsWinAndTheLegacyAliasRemainsMicroseconds() {
        var aliasParser = FFmpegProgressParser(durationSeconds: 10)
        let alias       = aliasParser.consume(Data("out_time_ms=2500000\nprogress=continue\n".utf8))
        #expect(alias?.fraction == 0.25)

        var preferredParser = FFmpegProgressParser(durationSeconds: 10)
        let preferred       = preferredParser.consume(
            Data(
                "out_time_ms=9000000\n"
                    .appending("out_time_us=2000000\n")
                    .appending("progress=continue\n")
                    .utf8
            )
        )
        #expect(preferred?.fraction == 0.2)

        var invalidPreferred = FFmpegProgressParser(durationSeconds: 10)
        let indeterminate    = invalidPreferred.consume(
            Data(
                "out_time_ms=3000000\n"
                    .appending("out_time_us=N/A\n")
                    .appending("progress=continue\n")
                    .utf8
            )
        )
        #expect(indeterminate?.fraction == nil)

        let resetAlias = invalidPreferred.consume(
            Data("out_time_ms=4000000\nprogress=continue\n".utf8)
        )
        #expect(resetAlias?.fraction == 0.4)
    }

    @Test
    func invalidDurationAndTimestampsStayIndeterminate() {
        for duration in [nil, 0, -1, .nan, .infinity] as [Double?] {
            var parser      = FFmpegProgressParser(durationSeconds: duration)
            let observation = parser.consume(Data("out_time_us=1000000\nprogress=continue\n".utf8))
            #expect(observation?.fraction == nil)
        }

        for timestamp in ["N/A", "nan", "inf", "9223372036854775808", "-1"] {
            var parser      = FFmpegProgressParser(durationSeconds: 10)
            let observation = parser.consume(
                Data("out_time_us=\(timestamp)\nprogress=continue\n".utf8)
            )
            #expect(observation?.fraction == nil)
        }
    }

    @Test
    func progressNeverMovesBackwardOrBeyondOne() {
        var parser   = FFmpegProgressParser(durationSeconds: 10)
        let first    = parser.consume(Data("out_time_us=8000000\nprogress=continue\n".utf8))
        let backward = parser.consume(Data("out_time_us=2000000\nprogress=continue\n".utf8))
        let beyond   = parser.consume(Data("out_time_us=12000000\nprogress=continue\n".utf8))

        #expect(first?.fraction == 0.8)
        #expect(backward?.fraction == 0.8)
        #expect(beyond?.fraction == 1)
    }

    @Test
    func overlongLineIsDiscardedWholeAndTheNextRecordRecovers() {
        var parser   = FFmpegProgressParser(durationSeconds: 10)
        let poisoned = Data(
            (String(repeating: "x", count: 4_097)
                + "out_time_us=9000000\nprogress=continue\n").utf8
        )
        let split = poisoned.count / 2

        #expect(parser.consume(poisoned.prefix(split)) == nil)

        let discarded = parser.consume(poisoned.suffix(poisoned.count - split))
        #expect(discarded?.fraction == nil)

        let recovered = parser.consume(Data("out_time_us=3000000\nprogress=continue\n".utf8))
        #expect(recovered?.fraction == 0.3)
    }

    @Test
    func endMarkerReportsObservedProgressWithoutForcingCompletion() {
        var parser      = FFmpegProgressParser(durationSeconds: 10)
        let observation = parser.consume(Data("out_time_us=5000000\nprogress=end\n".utf8))

        #expect(observation == FFmpegProgressParser.Observation(fraction: 0.5, marker: .end))
    }

    @Test
    func finishHandlesOneUnterminatedBoundaryAndThenClearsState() {
        var parser = FFmpegProgressParser(durationSeconds: 10)
        #expect(parser.consume(Data("out_time_us=6000000\nprogress=end".utf8)) == nil)
        #expect(parser.finish() == FFmpegProgressParser.Observation(fraction: 0.6, marker: .end))
        #expect(parser.finish() == nil)
    }
}
