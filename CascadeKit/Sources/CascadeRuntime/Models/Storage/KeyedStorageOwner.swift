//
//  KeyedStorageOwner.swift
//  CascadeKit
//

import Foundation

/// KeyedStorageOwner is a canonical host capability, never decoded from provider input.
struct KeyedStorageOwner: Hashable, Sendable {

    let id: UUID
}
