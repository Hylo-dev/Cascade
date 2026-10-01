//
//  NativeFileDragHintFixture.swift
//  CascadeKit
//

import AppKit
import Foundation
import Testing
@testable import CascadeKit

@MainActor
final class NativeFileDragHintFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cascade-NativeFileDragHint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func board() -> NSPasteboard {
        let board = NSPasteboard(name: .init("Cascade.NativeFileDragHint.\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    func file(name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("file".utf8).write(to: url)
        return url
    }

    func item(url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        return item
    }
}
