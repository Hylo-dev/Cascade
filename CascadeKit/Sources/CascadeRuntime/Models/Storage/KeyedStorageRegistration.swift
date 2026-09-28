//
//  KeyedStorageRegistration.swift
//  CascadeKit
//

import CryptoKit
import Foundation

/// KeyedStorageRegistration describes trusted retained-data identity, including disabled addons.
struct KeyedStorageRegistration: Sendable {
    let identity : VerifiedAddonIdentity
}
