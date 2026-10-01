//
//  FFmpegMediaPlanning.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// FFmpegMediaPlanning turns bounded probe facts into one of Cascade's closed output presets.
///
/// These values describe capability and controlled arguments only. They do not grant access to
/// a file, prove that decoding will succeed, or replace process and output supervision.
enum FFmpegMediaPlanning {

    enum Failure: Error, Equatable, Sendable {

        case probeLimitExceeded
        case invalidProbe
        case invalidSelection
        case unsupportedFormat
    }

    struct Media: Equatable, Sendable {

        var hasAudio: Bool { firstAudio != nil }

        /// hasVideo relies on ffprobe reporting `disposition.attached_pic` for artwork streams.
        /// A future probe command must keep that field in its narrowed `show_entries` response.
        var hasVideo: Bool { firstVideo != nil }

        fileprivate let firstAudio    : Track?
        fileprivate let firstVideo    : Track?
        fileprivate let streamIndexes : Set<Int>
        fileprivate let formatDuration: Double?

        /// duration uses container duration only when no unselected stream could have extended it.
        fileprivate func duration(for selected: [Track]) -> Double? {
            let known = selected.compactMap(\.durationSeconds)
            if known.count == selected.count { return known.max() }

            let selectedIndexes = Set(selected.map(\.index))
            guard selectedIndexes == streamIndexes else { return nil }

            return formatDuration
        }
    }

    struct Preset: Equatable, Sendable {

        let format             : FileConversionFormat
        let outputFileExtension: String
        let outputArguments    : [String]
        let durationSeconds    : Double?
    }

    private enum Output: String, CaseIterable {

        case mp4
        case m4a
        case wav
        case flac
    }

    fileprivate struct Track: Equatable, Sendable {

        let index          : Int
        let durationSeconds: Double?
    }

    private struct ProbeDocument: Decodable {

        let streams: [ProbeStream]
        let format : ProbeFormat?

        private enum CodingKeys: String, CodingKey {

            case streams
            case format
        }

        init(from decoder: any Decoder) throws {
            let values       = try decoder.container(keyedBy: CodingKeys.self)
            var streamValues = try values.nestedUnkeyedContainer(forKey: .streams)
            var streams: [ProbeStream] = []
            streams.reserveCapacity(min(streamValues.count ?? 0, 32))

            while !streamValues.isAtEnd {
                guard streams.count < 32 else { throw Failure.probeLimitExceeded }

                streams.append(try streamValues.decode(ProbeStream.self))
            }

            self.streams = streams
            format       = try values.decodeIfPresent(ProbeFormat.self, forKey: .format)
        }
    }

    private struct ProbeStream: Decodable {

        let index      : Int
        let codecType  : String
        let codecName  : String
        let duration   : String?
        let disposition: ProbeDisposition?

        private enum CodingKeys: String, CodingKey {

            case index
            case codecType   = "codec_type"
            case codecName   = "codec_name"
            case duration
            case disposition
        }
    }

    private struct ProbeDisposition: Decodable {

        let attachedPicture: Int?

        private enum CodingKeys: String, CodingKey {

            case attachedPicture = "attached_pic"
        }
    }

    private struct ProbeFormat: Decodable {

        let duration: String?
    }

    /// decodeProbe keeps only stream identity, kind and duration from bounded ffprobe JSON.
    static func decodeProbe(_ data: Data) throws -> Media {
        guard data.count <= 65_536 else { throw Failure.probeLimitExceeded }

        let document: ProbeDocument
        do {
            document = try JSONDecoder().decode(ProbeDocument.self, from: data)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.invalidProbe
        }

        var indexes    = Set<Int>()
        var firstAudio: Track?
        var firstVideo: Track?
        for stream in document.streams {
            guard stream.index >= 0,
                  indexes.insert(stream.index).inserted,
                  !stream.codecType.isEmpty,
                  !stream.codecName.isEmpty,
                  stream.disposition?.attachedPicture.map({ $0 == 0 || $0 == 1 }) ?? true
            else {
                throw Failure.invalidProbe
            }

            let track = Track(index: stream.index, durationSeconds: duration(stream.duration))
            switch stream.codecType {
                case "audio" where firstAudio == nil:
                    firstAudio = track
                case "video" where stream.disposition?.attachedPicture == 0 && firstVideo == nil:
                    firstVideo = track
                default:
                    break
            }
        }

        return Media(
            firstAudio    : firstAudio,
            firstVideo    : firstVideo,
            streamIndexes : indexes,
            formatDuration: duration(document.format?.duration)
        )
    }

    /// formats intersects capabilities so a mixed selection never silently skips an input.
    static func formats(for inputs: [Media]) throws -> [FileConversionFormat] {
        guard (1...32).contains(inputs.count) else { throw Failure.invalidSelection }

        return try Output.allCases.compactMap { output in
            guard inputs.allSatisfy({ supports(output, media: $0) }) else { return nil }

            return try conversionFormat(output)
        }
    }

    /// preset binds a known format to exact probed stream indexes without accepting raw CLI text.
    static func preset(
        formatID : String,
        for input: Media
    ) throws -> Preset {
        guard let output = Output(rawValue: formatID), supports(output, media: input) else {
            throw Failure.unsupportedFormat
        }

        switch output {
            case .mp4:
                guard let video = input.firstVideo else { throw Failure.unsupportedFormat }

                var arguments = ["-map", "0:\(video.index)"]
                var selected  = [video]
                if let audio = input.firstAudio {
                    arguments += ["-map", "0:\(audio.index)"]
                    selected.append(audio)
                } else {
                    arguments.append("-an")
                }
                arguments += ["-c:v", "h264_videotoolbox", "-pix_fmt", "nv12"]
                if input.firstAudio != nil { arguments += ["-c:a", "aac"] }
                arguments += ["-movflags", "+faststart", "-f", "mp4"]

                return try Preset(
                    format             : conversionFormat(output),
                    outputFileExtension: "mp4",
                    outputArguments    : arguments,
                    durationSeconds    : input.duration(for: selected)
                )

            case .m4a:
                return try audioPreset(
                    output: output,
                    codec : "aac",
                    muxer : "ipod",
                    media : input
                )

            case .wav:
                return try audioPreset(
                    output: output,
                    codec : "pcm_s16le",
                    muxer : "wav",
                    media : input
                )

            case .flac:
                return try audioPreset(
                    output: output,
                    codec : "flac",
                    muxer : "flac",
                    media : input
                )
        }
    }

    private static func supports(
        _ output: Output,
        media   : Media
    ) -> Bool {
        switch output {
            case .mp4: media.hasVideo
            case .m4a, .wav, .flac: media.hasAudio
        }
    }

    private static func conversionFormat(_ output: Output) throws -> FileConversionFormat {
        switch output {
            case .mp4:
                try FileConversionFormat(
                    id                  : output.rawValue,
                    label               : "MP4",
                    outputTypeIdentifier: "public.mpeg-4"
                )

            case .m4a:
                try FileConversionFormat(
                    id                  : output.rawValue,
                    label               : "M4A",
                    outputTypeIdentifier: "com.apple.m4a-audio"
                )

            case .wav:
                try FileConversionFormat(
                    id                  : output.rawValue,
                    label               : "WAV",
                    outputTypeIdentifier: "com.microsoft.waveform-audio"
                )

            case .flac:
                try FileConversionFormat(
                    id                  : output.rawValue,
                    label               : "FLAC",
                    outputTypeIdentifier: "org.xiph.flac"
                )
        }
    }

    private static func audioPreset(
        output: Output,
        codec : String,
        muxer : String,
        media : Media
    ) throws -> Preset {
        guard let audio = media.firstAudio else { throw Failure.unsupportedFormat }

        return try Preset(
            format             : conversionFormat(output),
            outputFileExtension: output.rawValue,
            outputArguments    : [
                "-map", "0:\(audio.index)", "-vn", "-c:a", codec, "-f", muxer,
            ],
            durationSeconds    : media.duration(for: [audio])
        )
    }

    private static func duration(_ value: String?) -> Double? {
        guard let value,
              let parsed = Double(value),
              parsed.isFinite,
              parsed > 0
        else {
            return nil
        }

        return parsed
    }
}
