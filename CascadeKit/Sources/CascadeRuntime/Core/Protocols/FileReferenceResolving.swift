//
//  FileReferenceResolving.swift
//  CascadeKit
//

import Foundation

/// FileReferenceResolving creates and reopens host-side persistent references.
protocol FileReferenceResolving: Sendable {

    func createReference(to url: URL) async throws -> FileReferenceLease
    func resolve(_ bookmark: Data) async throws -> FileReferenceLease
}
