//
//  AssetTransferOperation.swift
//  CascadeKit
//

import Foundation

/// AssetTransferOperation names syntax without granting publication authority.
/// `share` and `release` act on an existing canonical alias instead of a byte transfer.
public enum AssetTransferOperation: String, Codable, Sendable {

    case begin, chunk, finish, abort, share, release
}
