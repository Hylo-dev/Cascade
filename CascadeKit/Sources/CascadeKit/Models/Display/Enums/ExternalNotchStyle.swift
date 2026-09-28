//
//  ExternalNotchStyle.swift
//  CascadeKit
//

import Foundation

/// ExternalNotchStyle describes the compact chrome used when no hardware notch
/// dictates the shape.
public nonisolated enum ExternalNotchStyle: String, Codable, Equatable, Sendable {
    case notch
    case dynamicIsland
}
