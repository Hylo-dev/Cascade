//
//  ConnectionGeneration.swift
//  Cascade
//

import Foundation

/// ConnectionGeneration distinguishes handles issued by separate handshakes.
public struct ConnectionGeneration: Codable, Hashable, Sendable {
    public let value: UUID
    public init(value: UUID = UUID()) { self.value = value }
}
