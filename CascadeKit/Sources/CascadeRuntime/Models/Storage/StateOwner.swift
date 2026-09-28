//
//  StateOwner.swift
//  CascadeKit
//

import Foundation

/// StateOwner is a capability issued by one store instance. It is never decoded from provider input.
public struct StateOwner: Hashable, Sendable {
    let id: UUID
}
