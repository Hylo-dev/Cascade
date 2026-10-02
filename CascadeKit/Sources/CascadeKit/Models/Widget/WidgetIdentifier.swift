//
//  WidgetIdentifier.swift
//  CascadeKit
//

/// WidgetIdentifier is the stable identity of a widget type.
///
/// It is a thin typed wrapper over a string so the host can register, look up
/// and de-duplicate widgets without raw strings leaking through the API.
public nonisolated struct WidgetIdentifier: Codable, Hashable, Sendable {

    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
