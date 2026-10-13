//
//  AudioOutputSymbol.swift
//  CascadeKit
//

import AppKit
import Synchronization

/// AudioOutputSymbol makes sure a symbol name exists on the system before a view draws it. The
/// newer dotted AirPods names (`airpods.pro`, `airpods.max`) are missing on older macOS, where
/// the same artwork lives under the undotted ones, and SwiftUI draws nothing for a name it does
/// not know. The choice between the two is `resolve`, a pure function over an availability
/// check, so it is tested without the symbol catalogue.
///
/// `installedName(for:)` is the answer the views use. Asking AppKit whether a symbol exists loads
/// its image, which is not work for a frame, so each name is asked once and the answer is kept in
/// a table behind a lock: a body that redraws while the user drags the level reads a dictionary
/// and nothing else.
nonisolated enum AudioOutputSymbol {

    private static let fallbacks: [String: String] = [
        "airpods.pro": "airpodspro",
        "airpods.max": "airpodsmax",
        "macbook"    : "laptopcomputer"
    ]

    private static let installedNames = Mutex<[String: String]>([:])

    /// fallback is the older spelling of a symbol, or nil when the name has none.
    static func fallback(for name: String) -> String? {
        fallbacks[name]
    }

    /// resolve returns the name to draw: the preferred one if the system has it, else its
    /// fallback if that exists. With neither it keeps the preferred name, so the failure stays
    /// visible as a missing symbol instead of silently showing a different product.
    static func resolve(
        _ name     : String,
        isAvailable: (String) -> Bool
    ) -> String {
        if isAvailable(name) { return name }
        if let older = fallback(for: name), isAvailable(older) { return older }
        return name
    }

    /// installedName is `resolve` against the real symbol catalogue, remembered per name.
    static func installedName(for name: String) -> String {
        if let known = installedNames.withLock({ $0[name] }) { return known }

        let resolved = resolve(name) { candidate in
            NSImage(
                systemSymbolName        : candidate,
                accessibilityDescription: nil
            ) != nil
        }
        installedNames.withLock { $0[name] = resolved }
        return resolved
    }
}
