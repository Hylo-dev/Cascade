//
//  StorageFrameProfile.swift
//  CascadeKit
//

import Foundation

/// StorageFrameProfile identifies implemented syntax, not handshake or access authority.
/// A transport must select it from its canonical negotiated protocol, never provider input.
public enum StorageFrameProfile: Equatable, Sendable {
    case v1_1
}
