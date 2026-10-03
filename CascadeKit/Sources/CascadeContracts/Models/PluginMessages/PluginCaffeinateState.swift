//
//  PluginCaffeinateState.swift
//  CascadeKit
//

import Foundation

/// PluginCaffeinateState is a full native-session snapshot. Each publication carries a fresh
/// control token so an accepted action queued against an older native state cannot toggle a
/// replacement session. No seconds counter is streamed across the process boundary.
public struct PluginCaffeinateState: Equatable, Sendable {

    public static let source = "caffeinate"

    public let token           : UUID
    public let isActive        : Bool
    public let isBusy          : Bool
    public let keepDisplayAwake: Bool
    public let until           : Date?
    public let error           : String?

    public init(
        token           : UUID = UUID(),
        isActive        : Bool = false,
        isBusy          : Bool = false,
        keepDisplayAwake: Bool = true,
        until           : Date? = nil,
        error           : String? = nil
    ) {
        self.token            = token
        self.isActive         = isActive
        self.isBusy           = isBusy
        self.keepDisplayAwake = keepDisplayAwake
        self.until            = until
        self.error            = error
    }

    public init?(_ event: PluginSourceEvent) {
        guard event.source == Self.source,
              case .string(let token)?          = event.fields["token"],
              let identifier                    = UUID(uuidString: token),
              case .bool(let active)?           = event.fields["isActive"],
              case .bool(let busy)?             = event.fields["isBusy"],
              case .bool(let display)?          = event.fields["keepDisplayAwake"]
        else { return nil }

        var until: Date?
        if let field = event.fields["until"] {
            guard case .number(let seconds) = field,
                  seconds.isFinite, abs(seconds) <= 253_402_300_799
            else { return nil }
            until = Date(timeIntervalSince1970: seconds)
        }
        var error: String?
        if let field = event.fields["error"] {
            guard case .string(let text) = field else { return nil }
            error = text
        }
        self.init(token: identifier, isActive: active, isBusy: busy, keepDisplayAwake: display, until: until, error: error)
    }

    public func event() throws -> PluginSourceEvent {
        var fields: [String: PluginValue] = [
            "token"           : .string(token.uuidString),
            "isActive"        : .bool(isActive),
            "isBusy"          : .bool(isBusy),
            "keepDisplayAwake": .bool(keepDisplayAwake),
        ]
        if let until { fields["until"] = .number(until.timeIntervalSince1970) }
        if let error { fields["error"] = .string(String(error.prefix(512))) }
        return try PluginSourceEvent(source: Self.source, fields: fields)
    }
}
