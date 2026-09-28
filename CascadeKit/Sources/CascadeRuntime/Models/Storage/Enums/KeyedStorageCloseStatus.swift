//
//  KeyedStorageCloseStatus.swift
//  CascadeKit
//

import CryptoKit
import Foundation

/// KeyedStorageCloseStatus distinguishes immediate closure from an active operation draining its refunds.
enum KeyedStorageCloseStatus: Equatable, Sendable {
    case closed, draining
}
