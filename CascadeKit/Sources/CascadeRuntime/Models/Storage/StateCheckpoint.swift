//
//  StateCheckpoint.swift
//  CascadeKit
//

import Foundation

public struct StateCheckpoint: Equatable, Sendable {
    public let data: Data
    public let schemaVersion: UInt32
    public let revision: UInt64
    public let digest: Data
}
