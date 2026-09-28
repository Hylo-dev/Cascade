//
//  FileShelfPromiseDelegate.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

final class FileShelfPromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let file: PreparedFile
    private let copy: @Sendable (PreparedFile, URL) async throws -> Void

    init(
        file: PreparedFile,
        copy: @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        self.file = file
        self.copy = copy
    }

    @MainActor
    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        file.name
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        let file = file
        let copy = copy
        let completion = FilePromiseCompletion(completionHandler)
        Task {
            do {
                try await copy(file, url)
                completion.call(nil)
            } catch {
                completion.call(error)
            }
        }
    }
}
