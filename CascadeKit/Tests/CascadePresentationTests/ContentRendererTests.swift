//
//  ContentRendererTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import Foundation
import SwiftUI
import Testing

@Suite
struct ContentRendererTests {
    @MainActor
    private struct PreviewAssets: ContentAssetResolving {
        func image(for assetID: String) -> Image? { Image(systemName: "photo") }
    }

    @Test
    @MainActor
    func rendersSharedPreview() throws {
        let content = try CascadeColumn {
            try CascadeText("Focus")
            try CascadeRow {
                try CascadeSymbol("moon.fill")
                try CascadeImage(assetID: "cover", accessibilityLabel: "Cover art")
            }
            try CascadeProgress(value: 0.6)
            try CascadeCountdown(until: Date.now.addingTimeInterval(600))
            try CascadeClock(format: .hourMinuteSecond)
            try CascadeButton(ActionDescriptor(id: "stop", label: "Stop focus"))
        }
        let document = try ContentDocument(
            root: content.contentNode,
            privacy: .publicContent,
            accessibilityLabel: "Focus session",
            assetIDs: ["cover"]
        )
        let preview = try ContentPreview(
            document: document,
            assets: PreviewAssets(),
            previewDispatcher: { _ in Issue.record("Snapshot must never dispatch a provider action") }
        )
        let renderer = ImageRenderer(
            content:
                preview
                .frame(width: 300, height: 280)
                .padding()
                .background(.black)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
        )
        let image = try #require(renderer.nsImage)
        #expect(image.size.width > 0 && image.size.height > 0)
        if ProcessInfo.processInfo.environment["CASCADE_WRITE_PREVIEW"] == "1",
            let data = image.tiffRepresentation
        {
            try data.write(to: URL(fileURLWithPath: "/private/tmp/cascade-content-preview.tiff"))
        }
    }
}
