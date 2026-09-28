//
//  FileAvailability.swift
//  CascadeKit
//

import Foundation

/// FileAvailability describes whether a shelf entry can currently be used.
public enum FileAvailability: String, Codable, Equatable, Sendable {
    case available, unavailable, receiving
}
