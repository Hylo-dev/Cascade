//
//  FileOwnership.swift
//  CascadeKit
//

import Foundation

/// FileOwnership distinguishes an external reference from a managed copy.
public enum FileOwnership: String, Codable, Equatable, Sendable {
    case externalReference, managed
}
