//
//  KeyedStorageCloseStatus.swift
//  CascadeKit
//

/// KeyedStorageCloseStatus distinguishes immediate closure from an active operation draining its refunds.
enum KeyedStorageCloseStatus: Equatable, Sendable {

    case closed
    case draining
}
