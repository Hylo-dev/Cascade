//
//  ServiceSession.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

public struct ServiceSession: Hashable, Sendable {
    fileprivate let id: UUID
    init() { id = UUID() }
}
