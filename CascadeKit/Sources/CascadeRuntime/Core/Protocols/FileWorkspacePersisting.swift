//
//  FileWorkspacePersisting.swift
//  CascadeKit
//

import Foundation

/// FileWorkspacePersisting owns only the versioned manifest operation.
/// Managed payload copies remain the store's responsibility and never cross this boundary.
protocol FileWorkspacePersisting: Sendable {

    func load() async throws -> Data?
    func save(_ data: Data) async throws
}
