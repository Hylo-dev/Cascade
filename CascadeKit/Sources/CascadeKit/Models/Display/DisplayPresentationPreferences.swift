//
//  DisplayPresentationPreferences.swift
//  CascadeKit
//

/// DisplayPresentationPreferences is the complete persisted display policy.
///
/// Missing style entries deliberately resolve to `notch`, so newly connected
/// displays gain a conservative shape without rewriting the saved payload.
public nonisolated struct DisplayPresentationPreferences: Codable, Equatable, Sendable {

    public let activityMode: LiveActivityDisplayMode
    public let styles      : [DisplayIdentity: ExternalNotchStyle]

    public init(
        activityMode: LiveActivityDisplayMode = .focusedDisplay,
        styles      : [DisplayIdentity: ExternalNotchStyle] = [:]
    ) {
        self.activityMode = activityMode
        self.styles       = styles
    }

    /// style returns the saved software-notch shape or the product default for
    /// a display that has never had an explicit choice.
    public func style(for identity: DisplayIdentity) -> ExternalNotchStyle {
        styles[identity] ?? .notch
    }
}
