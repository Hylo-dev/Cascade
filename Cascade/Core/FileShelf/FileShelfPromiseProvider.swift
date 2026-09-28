//
//  FileShelfPromiseProvider.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

/// Creates one native promise provider whose weak delegate is retained by userInfo.
enum FileShelfPromiseProvider {
    @MainActor
    static func make(
        file: PreparedFile,
        copy: @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) -> NSFilePromiseProvider {
        let delegate = FileShelfPromiseDelegate(file: file, copy: copy)
        let provider = NSFilePromiseProvider(
            fileType: file.typeIdentifier,
            delegate: delegate
        )
        provider.userInfo = delegate
        return provider
    }
}
