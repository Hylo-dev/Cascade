//
//  FFmpegProgressParser.swift
//  CascadeKit
//

import Foundation

/// FFmpegProgressParser reduces FFmpeg's bounded key-value reports to the latest telemetry.
///
/// The parser deliberately has no success state. `progress=end` only marks the last report;
/// a later process supervisor must still observe exit, validate output and publish it safely.
struct FFmpegProgressParser: Sendable {

    struct Observation: Equatable, Sendable {

        enum Marker: Equatable, Sendable {

            case continuing
            case end
        }

        let fraction: Double?
        let marker  : Marker
    }

    private enum ReportTime: Sendable {

        case absent
        case invalid
        case microseconds(Int64)
    }

    private static let maximumLineBytes = 4_096

    private let durationSeconds: Double?

    private var line             = Data()
    private var isDiscardingLine = false
    private var canonicalTime   : ReportTime = .absent
    private var aliasTime       : ReportTime = .absent
    private var latestFraction  : Double?

    init(durationSeconds: Double?) {
        if let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 {
            self.durationSeconds = durationSeconds
        } else {
            self.durationSeconds = nil
        }

        line.reserveCapacity(Self.maximumLineBytes)
    }

    /// consume accepts an arbitrary pipe chunk and coalesces all complete reports to the newest.
    mutating func consume(_ bytes: Data) -> Observation? {
        var latest: Observation?
        for byte in bytes {
            if byte == 0x0A {
                if isDiscardingLine {
                    isDiscardingLine = false
                    line.removeAll(keepingCapacity: true)
                    resetReport()
                } else {
                    latest = consumeLine() ?? latest
                }
                continue
            }

            guard !isDiscardingLine else { continue }
            guard line.count < Self.maximumLineBytes else {
                line.removeAll(keepingCapacity: true)
                isDiscardingLine = true
                continue
            }

            line.append(byte)
        }

        return latest
    }

    /// finish consumes one final unterminated line and discards any incomplete report afterward.
    mutating func finish() -> Observation? {
        defer {
            line.removeAll(keepingCapacity: true)
            isDiscardingLine = false
            resetReport()
        }
        guard !isDiscardingLine, !line.isEmpty else { return nil }

        return consumeLine()
    }

    private mutating func consumeLine() -> Observation? {
        if line.last == 0x0D { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }

        guard let value = String(data: line, encoding: .utf8),
              !value.utf8.contains(0),
              let separator = value.firstIndex(of: "=")
        else {
            return nil
        }

        let key      = value[..<separator]
        let rawValue = value[value.index(after: separator)...]

        switch key {
            case "out_time_us":
                canonicalTime = Self.reportTime(rawValue)
                return nil

            case "out_time_ms":
                // FFmpeg 9.0.2 emits this legacy alias in microseconds despite its name.
                aliasTime = Self.reportTime(rawValue)
                return nil

            case "progress":
                let marker: Observation.Marker
                switch rawValue {
                    case "continue": marker = .continuing
                    case "end": marker = .end
                    default: return nil
                }

                let observation = Observation(fraction: fraction(), marker: marker)
                resetReport()
                return observation

            default:
                return nil
        }
    }

    private mutating func fraction() -> Double? {
        let chosen = switch canonicalTime {
            case .absent: aliasTime
            default: canonicalTime
        }
        guard case .microseconds(let microseconds) = chosen,
              let durationSeconds
        else {
            return latestFraction
        }

        let raw = Double(microseconds) / 1_000_000 / durationSeconds
        guard raw.isFinite else { return latestFraction }

        let bounded    = min(1, max(0, raw))
        let monotonic  = max(latestFraction ?? 0, bounded)
        latestFraction = monotonic
        return monotonic
    }

    private mutating func resetReport() {
        canonicalTime = .absent
        aliasTime     = .absent
    }

    private static func reportTime(_ value: Substring) -> ReportTime {
        guard let parsed = Int64(value), parsed >= 0 else { return .invalid }

        return .microseconds(parsed)
    }
}
