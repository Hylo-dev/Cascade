//
//  KeyedWriteTicket.swift
//  CascadeKit
//

import CryptoKit
import Foundation

/// KeyedWriteTicket identifies the sole prepared write of one backend epoch.
struct KeyedWriteTicket: Hashable, Sendable {
    let id : UUID
}
