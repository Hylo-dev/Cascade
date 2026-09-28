//
//  NotchGlassLightHostTests.swift
//  CascadeKitTests
//

import AppKit
import CascadeContracts
import CascadePresentation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct NotchGlassLightHostTests {
    @Test
    func privacyPlaceholderClearsPreviousLightBeforePreferenceDelivery() async throws {
        let renderer = RecordingGlassRenderer()
        let frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        let host = NotchHostView(frame: frame, glassRenderer: renderer)
        let light = try makeLight()
        host.setExpandedActivityContent(
            AnyView(Text("Private album").notchGlassLights([light])),
            frame: frame
        )
        try await expectLights([light], from: host, renderer: renderer)

        host.setExpandedActivityContent(
            AnyView(Text("Contenuto nascosto").privacySensitive()),
            frame: frame
        )

        // Do not yield or lay out the replacement first: no private color may
        // survive while the no-light placeholder's preference is still queued.
        #expect(renderer.lights.isEmpty)
        try await expectLights([], from: host, renderer: renderer)
    }

    @Test
    func identicalReplacementReacquiresLightsWithItsNewGeneration() async throws {
        let renderer = RecordingGlassRenderer()
        let frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        let host = NotchHostView(frame: frame, glassRenderer: renderer)
        let light = try makeLight()
        let content = AnyView(Text("Album").notchGlassLights([light]))
        host.setExpandedActivityContent(content, frame: frame)
        try await expectLights([light], from: host, renderer: renderer)

        host.setExpandedActivityContent(content, frame: frame)

        #expect(renderer.lights.isEmpty)
        try await expectLights([light], from: host, renderer: renderer)
    }

    private func expectLights(
        _ lights: [GlassLight],
        from host: NotchHostView,
        renderer: RecordingGlassRenderer
    ) async throws {
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            if renderer.lights == lights { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(renderer.lights == lights)
    }

    private func makeLight() throws -> GlassLight {
        try GlassLight(
            x: 0.25,
            y: 0.6,
            radius: 0.4,
            red: 1,
            green: 0.2,
            blue: 0.1,
            intensity: 0.7
        )
    }

    private final class RecordingGlassRenderer: NotchGlassRendering {
        let view = NSView(frame: .zero)
        let isSupported = true
        private(set) var lights: [GlassLight] = []

        func setColor(_ color: Color) {}
        func setLights(_ lights: [GlassLight]) { self.lights = lights }
        func apply(path: CGPath, canvasBounds: CGRect, progress: CGFloat, isVisible: Bool) {}
    }
}
