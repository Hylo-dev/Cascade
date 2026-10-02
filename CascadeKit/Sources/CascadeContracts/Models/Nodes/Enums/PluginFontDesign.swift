//
//  PluginFontDesign.swift
//  CascadeKit
//

/// PluginFontDesign mirrors SwiftUI's `Font.Design`; the clock uses `rounded`.
public enum PluginFontDesign: String, Codable, Hashable, Sendable {

    case standard
    case rounded
    case monospaced
    case serif
}
