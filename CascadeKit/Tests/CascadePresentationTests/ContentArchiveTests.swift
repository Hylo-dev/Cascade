//
//  ContentArchiveTests.swift
//  Cascade
//

import CascadeAddonSDK
import CascadeContracts
import CascadePresentation
import Foundation
import Testing

@Suite
struct ContentArchiveTests {
    @Test
    func keepsCountdownWithoutProviderObjects() throws {
        let document = try ContentDocument(
            root: .countdown(until: Date(timeIntervalSince1970: 2_000_000_000)),
            privacy: .publicContent,
            accessibilityLabel: "Tempo rimanente"
        )
        #expect(try ContentDocument.decode(document.encode()) == document)
    }

    @Test
    func archivesAllComponentsAndBuilderBranches() throws {
        let action = try ActionDescriptor(id: "open", label: "Open details", payload: Data([1, 2, 3]))
        let showImage = true
        let column = try CascadeColumn {
            try CascadeRow {
                try CascadeText("Focus")
                try CascadeSymbol("moon.fill")
            }
            if showImage {
                try CascadeImage(assetID: "cover", accessibilityLabel: "Album cover")
            }
            for value in [0.0, 0.5, 1.0] {
                try CascadeProgress(value: value)
            }
            try CascadeCountdown(until: Date(timeIntervalSince1970: 2_000_000_000))
            try CascadeClock(format: .hourMinuteSecond)
            try CascadeButton(action)
        }
        let document = try ContentDocument(
            root: column.contentNode,
            privacy: .sensitive,
            accessibilityLabel: "Focus status",
            assetIDs: ["cover"]
        )
        #expect(try ContentDocument.decode(document.encode()) == document)
        #expect(column.contentNode.children?.last?.actionPayload == action.payload)
    }

    @Test
    func archivesVersionedProviderEvents() throws {
        let event = AddonEvent.scheduled(eventID: "refresh")
        #expect(try AddonEvent.decode(JSONEncoder().encode(event)) == event)
        #expect(throws: (any Error).self) { try JSONEncoder().encode(AddonEvent.scheduled(eventID: "")) }
        #expect(throws: (any Error).self) {
            try AddonEvent.decode(Data(#"{"schemaVersion":2,"kind":"stop","reason":"idle"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try AddonEvent.decode(
                Data(#"{"schemaVersion":1,"kind":"stop","reason":"idle","eventID":"x"}"#.utf8)
            )
        }
    }
}
