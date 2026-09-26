//
//  FFmpegMediaPlanningTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct FFmpegMediaPlanningTests {
    @Test
    func realTracksExcludeCoverArtAndDriveExactPlans() throws {
        let media = try FFmpegMediaPlanning.decodeProbe(
            Data(
                """
                {
                  "format": {"duration": "99.0", "filename": "/private/untrusted.mov"},
                  "streams": [
                    {"index": 4, "codec_type": "video", "codec_name": "mjpeg", "duration": "90", "disposition": {"attached_pic": 1}},
                    {"index": 7, "codec_type": "audio", "codec_name": "aac", "duration": "8.5", "tags": {"title": "-y /tmp/owned"}},
                    {"index": 9, "codec_type": "video", "codec_name": "hevc", "duration": "10.0", "disposition": {"attached_pic": 0}}
                  ]
                }
                """.utf8
            )
        )

        #expect(media.hasAudio)
        #expect(media.hasVideo)
        #expect(try FFmpegMediaPlanning.formats(for: [media]).map(\.id) == ["mp4", "m4a", "wav", "flac"])

        let video = try FFmpegMediaPlanning.preset(formatID: "mp4", for: media)
        #expect(video.outputFileExtension == "mp4")
        #expect(video.durationSeconds == 10)
        #expect(video.outputArguments == [
            "-map", "0:9", "-map", "0:7",
            "-c:v", "h264_videotoolbox", "-pix_fmt", "nv12",
            "-c:a", "aac", "-movflags", "+faststart", "-f", "mp4",
        ])
        #expect(!video.outputArguments.contains { $0.contains("untrusted") || $0.contains("/tmp") })

        let audio = try FFmpegMediaPlanning.preset(formatID: "m4a", for: media)
        #expect(audio.durationSeconds == 8.5)
        #expect(audio.outputArguments == [
            "-map", "0:7", "-vn", "-c:a", "aac", "-f", "ipod",
        ])
    }

    @Test
    func coverArtNeverCreatesVideoCapabilityOrOverridesAudioDuration() throws {
        let audioWithCover = try decode(
            streams: """
            {"index": 0, "codec_type": "video", "codec_name": "mjpeg", "duration": "700", "disposition": {"attached_pic": 1}},
            {"index": 1, "codec_type": "audio", "codec_name": "flac", "duration": "12.25"}
            """,
            formatDuration: "900"
        )
        #expect(!audioWithCover.hasVideo)
        #expect(audioWithCover.hasAudio)
        #expect(
            try FFmpegMediaPlanning.formats(for: [audioWithCover]).map(\.id)
                == ["m4a", "wav", "flac"]
        )
        #expect(
            try FFmpegMediaPlanning.preset(formatID: "flac", for: audioWithCover).durationSeconds
                == 12.25
        )

        let coverOnly = try decode(
            streams: """
            {"index": 0, "codec_type": "video", "codec_name": "png", "disposition": {"attached_pic": 1}}
            """
        )
        #expect(try FFmpegMediaPlanning.formats(for: [coverOnly]).isEmpty)

        let unknownDisposition = try decode(
            streams: """
            {"index": 2, "codec_type": "video", "codec_name": "h264", "duration": "4"}
            """
        )
        #expect(!unknownDisposition.hasVideo)
        #expect(try FFmpegMediaPlanning.formats(for: [unknownDisposition]).isEmpty)
    }

    @Test
    func selectionUsesOnlyFormatsSupportedByEveryInput() throws {
        let audiovisual = try decode(
            streams: """
            {"index": 0, "codec_type": "video", "codec_name": "h264", "duration": "4", "disposition": {"attached_pic": 0}},
            {"index": 1, "codec_type": "audio", "codec_name": "aac", "duration": "4"}
            """
        )
        let audio = try decode(
            streams: """
            {"index": 3, "codec_type": "audio", "codec_name": "pcm_s16le", "duration": "3"}
            """
        )
        let silentVideo = try decode(
            streams: """
            {"index": 5, "codec_type": "video", "codec_name": "vp9", "duration": "2", "disposition": {"attached_pic": 0}}
            """
        )

        #expect(
            try FFmpegMediaPlanning.formats(for: [audiovisual, audio]).map(\.id)
                == ["m4a", "wav", "flac"]
        )
        #expect(
            try FFmpegMediaPlanning.formats(for: [audiovisual, silentVideo]).map(\.id)
                == ["mp4"]
        )
        #expect(try FFmpegMediaPlanning.formats(for: [audio, silentVideo]).isEmpty)

        let silentPlan = try FFmpegMediaPlanning.preset(
            formatID: "mp4",
            for     : silentVideo
        )
        #expect(silentPlan.outputArguments == [
            "-map", "0:5", "-an",
            "-c:v", "h264_videotoolbox", "-pix_fmt", "nv12",
            "-movflags", "+faststart", "-f", "mp4",
        ])
    }

    @Test
    func closedAudioPresetsUseTheSelectedStreamWithoutUnrequestedReductions() throws {
        let media = try decode(
            streams: """
            {"index": 6, "codec_type": "audio", "codec_name": "opus", "duration": "5"}
            """
        )

        let wav = try FFmpegMediaPlanning.preset(formatID: "wav", for: media)
        #expect(wav.format.outputTypeIdentifier == "com.microsoft.waveform-audio")
        #expect(wav.outputFileExtension == "wav")
        #expect(wav.outputArguments == [
            "-map", "0:6", "-vn", "-c:a", "pcm_s16le", "-f", "wav",
        ])

        let flac = try FFmpegMediaPlanning.preset(formatID: "flac", for: media)
        #expect(flac.format.outputTypeIdentifier == "org.xiph.flac")
        #expect(flac.outputFileExtension == "flac")
        #expect(flac.outputArguments == [
            "-map", "0:6", "-vn", "-c:a", "flac", "-f", "flac",
        ])
        #expect(!wav.outputArguments.contains("-ar"))
        #expect(!wav.outputArguments.contains("-ac"))
    }

    @Test
    func unknownAndMP3FormatsAreRejected() throws {
        let media = try decode(
            streams: """
            {"index": 0, "codec_type": "audio", "codec_name": "aac"}
            """
        )

        let offeredIDs = try FFmpegMediaPlanning.formats(for: [media]).map(\.id)
        #expect(!offeredIDs.contains("mp3"))
        #expect(throws: FFmpegMediaPlanning.Failure.unsupportedFormat) {
            _ = try FFmpegMediaPlanning.preset(formatID: "mp3", for: media)
        }
        #expect(throws: FFmpegMediaPlanning.Failure.unsupportedFormat) {
            _ = try FFmpegMediaPlanning.preset(formatID: "../../wav", for: media)
        }
    }

    @Test
    func boundedSelectionAndProbeStructureRejectAmbiguity() throws {
        let media = try decode(
            streams: """
            {"index": 0, "codec_type": "audio", "codec_name": "aac"}
            """
        )
        #expect(throws: FFmpegMediaPlanning.Failure.invalidSelection) {
            _ = try FFmpegMediaPlanning.formats(for: [])
        }
        #expect(throws: FFmpegMediaPlanning.Failure.invalidSelection) {
            _ = try FFmpegMediaPlanning.formats(for: Array(repeating: media, count: 33))
        }

        let oversized = Data(repeating: 32, count: 65_537)
        #expect(throws: FFmpegMediaPlanning.Failure.probeLimitExceeded) {
            _ = try FFmpegMediaPlanning.decodeProbe(oversized)
        }
        for malformed in [
            Data("[]".utf8),
            Data("{\"streams\": [{\"index\": -1, \"codec_type\": \"audio\", \"codec_name\": \"aac\"}]}".utf8),
            Data("{\"streams\": [{\"index\": 0, \"codec_type\": \"audio\", \"codec_name\": \"aac\"}, {\"index\": 0, \"codec_type\": \"video\", \"codec_name\": \"h264\"}]}".utf8),
        ] {
            #expect(throws: FFmpegMediaPlanning.Failure.invalidProbe) {
                _ = try FFmpegMediaPlanning.decodeProbe(malformed)
            }
        }

        let streams = (0..<33).map { index in
            "{\"index\": \(index), \"codec_type\": \"audio\", \"codec_name\": \"aac\"}"
        }.joined(separator: ",")
        #expect(throws: FFmpegMediaPlanning.Failure.probeLimitExceeded) {
            _ = try FFmpegMediaPlanning.decodeProbe(
                Data("{\"streams\":[\(streams)]}".utf8)
            )
        }
    }

    @Test
    func invalidDurationsStayIndeterminateAndSelectedTracksBeatContainerDuration() throws {
        for duration in ["N/A", "nan", "inf", "-1", "1e9999"] {
            let media = try decode(
                streams: """
                {"index": 0, "codec_type": "audio", "codec_name": "aac", "duration": "\(duration)"}
                """
            )
            #expect(
                try FFmpegMediaPlanning.preset(formatID: "m4a", for: media).durationSeconds
                    == nil
            )
        }

        let fallback = try decode(
            streams: """
            {"index": 0, "codec_type": "audio", "codec_name": "aac"}
            """,
            formatDuration: "7.5"
        )
        #expect(
            try FFmpegMediaPlanning.preset(formatID: "m4a", for: fallback).durationSeconds
                == 7.5
        )

        let unrelatedContainer = try decode(
            streams: """
            {"index": 0, "codec_type": "audio", "codec_name": "aac"},
            {"index": 1, "codec_type": "video", "codec_name": "mjpeg", "duration": "80", "disposition": {"attached_pic": 1}}
            """,
            formatDuration: "80"
        )
        #expect(
            try FFmpegMediaPlanning.preset(
                formatID: "m4a",
                for     : unrelatedContainer
            ).durationSeconds == nil
        )
    }

    private func decode(
        streams      : String,
        formatDuration: String? = nil
    ) throws -> FFmpegMediaPlanning.Media {
        let format = formatDuration.map { "\"format\": {\"duration\": \"\($0)\"}," } ?? ""
        return try FFmpegMediaPlanning.decodeProbe(
            Data("{\(format)\"streams\":[\(streams)]}".utf8)
        )
    }
}
