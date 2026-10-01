//
//  FileWorkspaceMode.swift
//  CascadeKit
//

import Foundation

/// FileWorkspaceMode selects one host-rendered shelf surface.
public enum FileWorkspaceMode: String, Codable, Equatable, Sendable {

    case deck, list, conversion
}
