//
//  PluginScreenRecordingState.swift
//  CascadeKit
//

import Foundation

/// PluginScreenRecordingState is the native capture adapter's latest recording state. The
/// session names both the recording and its Stop control, so an accepted control from an old
/// session cannot stop a new writer. Idle withdraws the activity; stopping keeps it visible
/// until the writer confirms that the file is finalized. No frame or file crosses this source.
public struct PluginScreenRecordingState: Equatable, Sendable {

    public static let source = "screen.recording"

    public let session   : UUID?
    public let startedAt : Date?
    public let isStopping: Bool

    public init(
        session   : UUID? = nil,
        startedAt : Date? = nil,
        isStopping: Bool = false
    ) {
        self.session    = session
        self.startedAt  = startedAt
        self.isStopping = isStopping
    }

    public init?(_ event: PluginSourceEvent) {
        guard event.source == Self.source,
              case .bool(let isStopping)? = event.fields["isStopping"]
        else { return nil }

        if case .string(let identifier)? = event.fields["session"],
           let session = UUID(uuidString: identifier),
           case .number(let timestamp)? = event.fields["startedAt"],
           timestamp.isFinite, (0...4_102_444_800).contains(timestamp) {
            self.init(session: session, startedAt: Date(timeIntervalSince1970: timestamp), isStopping: isStopping)
        } else if event.fields["session"] == nil, event.fields["startedAt"] == nil, !isStopping {
            self.init()
        } else {
            return nil
        }
    }

    public func event() throws -> PluginSourceEvent {
        try ContractValidation.require((session == nil) == (startedAt == nil), "A recording needs its session and start")
        try ContractValidation.require(session != nil || !isStopping, "An idle recording cannot be stopping")

        var fields: [String: PluginValue] = ["isStopping": .bool(isStopping)]
        if let session, let startedAt {
            try ContractValidation.require(
                startedAt.timeIntervalSince1970.isFinite && (0...4_102_444_800).contains(startedAt.timeIntervalSince1970),
                "Invalid recording start"
            )
            fields["session"]   = .string(session.uuidString)
            fields["startedAt"] = .number(startedAt.timeIntervalSince1970)
        }
        return try PluginSourceEvent(source: Self.source, fields: fields)
    }
}
