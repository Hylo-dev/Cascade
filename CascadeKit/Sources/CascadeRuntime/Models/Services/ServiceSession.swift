//
//  ServiceSession.swift
//  CascadeKit
//

import Foundation

public struct ServiceSession: Hashable, Sendable {

    fileprivate let id: UUID

    init() { id = UUID() }
}
