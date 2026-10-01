//
//  StorageOperation.swift
//  CascadeKit
//

import Foundation

/// StorageOperation names a keyed data operation, without granting storage authority.
public enum StorageOperation: String, Codable, Sendable {

    case read, write, remove
}
