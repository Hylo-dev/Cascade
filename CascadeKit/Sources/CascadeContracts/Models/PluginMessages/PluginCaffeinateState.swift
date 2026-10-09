//
//  PluginCaffeinateState.swift
//  CascadeKit
//

import Foundation

/// PluginCaffeinateState is a full snapshot of the native keep-awake session. Time travels as
/// absolute dates, never as a counter: a session that started at one instant and ends at
/// another is drawn and kept current by the kernel without a single message more, and a late
/// or repeated snapshot can only repeat the truth. `activityStartedAt` marks the live activity's
/// own start, so a renewed activity can present again after its lifetime was capped while an
/// unchanged one does not. `nextTarget` is how the next session will end, and the glyph is
/// the user's pick. The snapshot carries no control token: the widget's controls ask for
/// absolute values.
public struct PluginCaffeinateState: Equatable, Sendable {

    public static let source = "caffeinate"

    public let startedAt        : Date?
    public let endsAt           : Date?
    public let activityStartedAt: Date?
    public let nextTarget       : CaffeinateTarget
    public let keepsDisplayAwake: Bool
    public let glyph            : CaffeinateGlyph
    public let failure          : CaffeinateFailure?

    public init(
        startedAt        : Date?               = nil,
        endsAt           : Date?               = nil,
        activityStartedAt: Date?               = nil,
        nextTarget       : CaffeinateTarget    = .indefinite,
        keepsDisplayAwake: Bool                = true,
        glyph            : CaffeinateGlyph     = .cupHeatWaves,
        failure          : CaffeinateFailure?  = nil
    ) {
        self.startedAt         = startedAt
        self.endsAt            = endsAt
        self.activityStartedAt = activityStartedAt
        self.nextTarget        = nextTarget
        self.keepsDisplayAwake = keepsDisplayAwake
        self.glyph             = glyph
        self.failure           = failure
    }

    /// isActive says a session is running: it has a start. A session without an end is indefinite.
    public var isActive: Bool { startedAt != nil }

    /// init?(_:) reads a caffeinate event, or fails for another source's event or any field that
    /// is present but not valid; a missing optional field is simply nil.
    public init?(_ event: PluginSourceEvent) {
        guard event.source == Self.source,
              case .bool(let keepsDisplayAwake)? = event.fields["keepsDisplayAwake"],
              case .string(let kindName)?        = event.fields["targetKind"],
              case .number(let wireValue)?       = event.fields["targetValue"],
              case .string(let glyphName)?       = event.fields["glyph"],
              wireValue.isFinite,
              abs(wireValue) < 1e9,
              wireValue == wireValue.rounded(),
              let kind       = CaffeinateTargetKind(rawValue: kindName),
              let nextTarget = CaffeinateTarget(kind: kind, value: Int(wireValue)),
              let glyph      = CaffeinateGlyph(rawValue: glyphName)
        else { return nil }

        // A date field is optional, but one that is present must be a number a Date can hold.
        func date(_ key: String) -> Result<Date?, Invalid> {
            guard let field = event.fields[key] else { return .success(nil) }
            guard case .number(let seconds) = field,
                  seconds.isFinite, abs(seconds) <= 253_402_300_799
            else { return .failure(Invalid()) }

            return .success(Date(timeIntervalSince1970: seconds))
        }

        guard case .success(let startedAt)         = date("startedAt"),
              case .success(let endsAt)            = date("endsAt"),
              case .success(let activityStartedAt) = date("activityStartedAt")
        else { return nil }

        var failure: CaffeinateFailure?
        if let field = event.fields["failure"] {
            guard case .string(let kind)        = field,
                  case .number(let rawCode)?    = event.fields["failureCode"],
                  rawCode.isFinite, rawCode == rawCode.rounded(),
                  rawCode >= Double(Int32.min), rawCode <= Double(Int32.max)
            else { return nil }

            let code = Int32(rawCode)
            switch kind {
                case "assertionRefused" : failure = .assertionRefused(code)
                case "extensionRefused" : failure = .extensionRefused(code)
                default                 : return nil
            }
        }

        self.init(
            startedAt        : startedAt,
            endsAt           : endsAt,
            activityStartedAt: activityStartedAt,
            nextTarget       : nextTarget,
            keepsDisplayAwake: keepsDisplayAwake,
            glyph            : glyph,
            failure          : failure
        )
    }

    /// event is the state as the source emits it; an absent date or failure is left out.
    public func event() throws -> PluginSourceEvent {
        var fields: [String: PluginValue] = [
            "targetKind"       : .string(nextTarget.kind.rawValue),
            "targetValue"      : .number(Double(nextTarget.value)),
            "keepsDisplayAwake": .bool(keepsDisplayAwake),
            "glyph"            : .string(glyph.rawValue),
        ]
        if let startedAt         { fields["startedAt"]         = .number(startedAt.timeIntervalSince1970) }
        if let endsAt            { fields["endsAt"]            = .number(endsAt.timeIntervalSince1970) }
        if let activityStartedAt { fields["activityStartedAt"] = .number(activityStartedAt.timeIntervalSince1970) }

        switch failure {
            case .assertionRefused(let code)?:
                fields["failure"]     = .string("assertionRefused")
                fields["failureCode"] = .number(Double(code))

            case .extensionRefused(let code)?:
                fields["failure"]     = .string("extensionRefused")
                fields["failureCode"] = .number(Double(code))

            case nil:
                break
        }

        return try PluginSourceEvent(source: Self.source, fields: fields)
    }

    private struct Invalid: Error {}
}
