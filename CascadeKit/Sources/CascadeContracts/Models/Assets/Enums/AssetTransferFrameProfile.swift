//
//  AssetTransferFrameProfile.swift
//  CascadeKit
//

import Foundation

/// AssetTransferFrameProfile identifies implemented syntax, not handshake or access authority.
/// It makes no claim that a transport has negotiated or implemented asset transfer.
public enum AssetTransferFrameProfile: Equatable, Sendable {

    case v1
}
