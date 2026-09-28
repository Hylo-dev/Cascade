//
//  AddonStorageClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonStorageClient limits storage to the authenticated addon's namespace.
/// Implementations enforce quotas, key validation and permissions at the broker boundary.
public protocol AddonStorageClient: Sendable {
    func read(key: String) async throws -> Data?
    func write(_ data: Data, key: String) async throws
    func remove(key: String) async throws
}
