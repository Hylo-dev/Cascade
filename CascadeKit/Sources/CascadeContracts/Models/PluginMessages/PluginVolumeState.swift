//
//  PluginVolumeState.swift
//  CascadeKit
//

/// PluginVolumeState is the `volume` catalog source's state, typed: the output level, whether it
/// is muted, and an announcement counter. The kernel's volume source decides, beside its key tap,
/// which changes are worth a notice; each one moves the counter, so a plugin shows a notice when
/// the counter moves and never has to second-guess the tap. Counter zero is a baseline, emitted
/// when the source starts, with no level yet.
public struct PluginVolumeState: Equatable, Sendable {

    public static let source = "volume"

    public let percentage  : Int?
    public let isMuted     : Bool
    public let announcement: UInt64

    public init(
        percentage  : Int?,
        isMuted     : Bool,
        announcement: UInt64
    ) {
        self.percentage   = percentage.map { min(100, max(0, $0)) }
        self.isMuted      = isMuted
        self.announcement = announcement
    }

    /// init(_:) reads a volume event, or fails for another source's event or a malformed one.
    public init?(_ event: PluginSourceEvent) {
        guard event.source == Self.source,
              case .bool(let isMuted)?        = event.fields["isMuted"],
              case .number(let announcement)? = event.fields["announcement"],
              announcement >= 0, announcement < 9_007_199_254_740_992
        else { return nil }

        var percentage: Int?
        if case .number(let value)? = event.fields["percentage"] {
            percentage = Int(value.rounded())
        }

        self.init(percentage: percentage, isMuted: isMuted, announcement: UInt64(announcement))
    }

    /// event is the state as the source emits it; a baseline's missing level is left out.
    public func event() throws -> PluginSourceEvent {
        var fields: [String: PluginValue] = [
            "isMuted"     : .bool(isMuted),
            "announcement": .number(Double(announcement)),
        ]
        if let percentage {
            fields["percentage"] = .number(Double(percentage))
        }

        return try PluginSourceEvent(source: Self.source, fields: fields)
    }
}
