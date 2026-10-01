//
//  NativeFileDragOfferHintTests.swift
//  CascadeKit
//

import AppKit
import Foundation
import Testing
@testable import CascadeKit

@Suite
struct NativeFileDragOfferHintTests {

    @MainActor
    @Test
    func acceptsOneThroughThirtyTwoRegularFileURLsFromOneStableGeneration() throws {
        let fixture = try NativeFileDragHintFixture()

        for count in [1, 32] {
            let board = fixture.board()
            let items = try (0..<count).map { index in
                fixture.item(url: try fixture.file(name: "file-\(count)-\(index).txt"))
            }
            board.writeObjects(items)
            let marker = board.changeCount

            #expect(NativeFileDragOfferHint.validates(board, changeCount: marker))
        }
    }

    @MainActor
    @Test
    func rejectsStaleEmptyAndOversizedGenerations() throws {
        let fixture = try NativeFileDragHintFixture()
        let empty   = fixture.board()
        #expect(!NativeFileDragOfferHint.validates(empty, changeCount: empty.changeCount))

        let board = fixture.board()
        board.writeObjects(try (0..<33).map { index in
            fixture.item(url: try fixture.file(name: "many-\(index).txt"))
        })
        let marker = board.changeCount

        #expect(!NativeFileDragOfferHint.validates(board, changeCount: marker - 1))
        #expect(!NativeFileDragOfferHint.validates(board, changeCount: marker))
    }

    @MainActor
    @Test
    func rejectsDirectoriesPromisesTextAndMixedBatches() throws {
        let fixture = try NativeFileDragHintFixture()

        let directoryBoard = fixture.board()
        directoryBoard.writeObjects([fixture.item(url: fixture.root)])
        #expect(!NativeFileDragOfferHint.validates(directoryBoard, changeCount: directoryBoard.changeCount))

        let promisedBoard = fixture.board()
        let promised      = try fixture.item(url: fixture.file(name: "promised.txt"))
        promised.setString("public.text", forType: .init("com.apple.pasteboard.promised-file-content-type"))
        promisedBoard.writeObjects([promised])
        #expect(!NativeFileDragOfferHint.validates(promisedBoard, changeCount: promisedBoard.changeCount))

        let textBoard = fixture.board()
        let text      = NSPasteboardItem()
        text.setString("not a file", forType: .string)
        textBoard.writeObjects([text])
        #expect(!NativeFileDragOfferHint.validates(textBoard, changeCount: textBoard.changeCount))

        let mixedBoard = fixture.board()
        let mixedText  = NSPasteboardItem()
        mixedText.setString("not a file", forType: .string)
        mixedBoard.writeObjects([
            try fixture.item(url: fixture.file(name: "regular.txt")),
            mixedText,
        ])
        #expect(!NativeFileDragOfferHint.validates(mixedBoard, changeCount: mixedBoard.changeCount))
    }

    @MainActor
    @Test
    func rejectsNonFileURLsAndMissingFiles() throws {
        let fixture = try NativeFileDragHintFixture()

        let remoteBoard = fixture.board()
        let remoteURL   = try #require(URL(string: "https://example.com/file.txt"))
        remoteBoard.writeObjects([fixture.item(url: remoteURL)])
        #expect(!NativeFileDragOfferHint.validates(remoteBoard, changeCount: remoteBoard.changeCount))

        let missingBoard = fixture.board()
        missingBoard.writeObjects([fixture.item(url: fixture.root.appendingPathComponent("missing.txt"))])
        #expect(!NativeFileDragOfferHint.validates(missingBoard, changeCount: missingBoard.changeCount))
    }
}
