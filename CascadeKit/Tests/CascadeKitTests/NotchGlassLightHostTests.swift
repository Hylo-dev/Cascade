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

    @Test
    func anAppKitEmitterReachesTheGlassDirectlyAndWithdrawsWithAnEmptyArray() throws {
        let renderer = RecordingGlassRenderer()
        let host = NotchHostView(frame: CGRect(x: 0, y: 0, width: 600, height: 260), glassRenderer: renderer)
        let geometry = NotchGeometry(leftExtent: 200, rightExtent: 200, height: 150, bottomCornerRadius: 40, topCornerRadius: 16)
        host.apply(geometry: geometry, centerX: 300, topY: 260, isChromeVisible: true)
        let receiver: any NotchGlassLightReceiving = host
        let light = try makeLight()
        let emitter = NSView()
        host.addSubview(emitter)

        receiver.setGlassLights([light], from: emitter)
        #expect(renderer.lights == [light])
        // Normalized to the same outline the renderer lays lights out in.
        #expect(receiver.glassLightBounds == CGPath.notch(geometry: geometry, centerX: 300, topY: 260).boundingBoxOfPath)

        receiver.setGlassLights([], from: emitter)
        #expect(renderer.lights.isEmpty)

        // A view outside the notch cannot light it.
        receiver.setGlassLights([light], from: NSView())
        #expect(renderer.lights.isEmpty)
    }

    @Test
    func replacingTheContentWithdrawsItsEmitterAtOnce() throws {
        let renderer = RecordingGlassRenderer()
        let frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        let host = NotchHostView(frame: frame, glassRenderer: renderer)
        host.setExpandedActivityContent(AnyView(Text("Album")), frame: frame)
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        let hosting = try #require(descendants(host).first { $0 is NSHostingView<AnyView> && !$0.isHidden })
        let emitter = NSView()
        hosting.addSubview(emitter)
        (host as any NotchGlassLightReceiving).setGlassLights([try makeLight()], from: emitter)
        #expect(!renderer.lights.isEmpty)

        host.setExpandedActivityContent(AnyView(Text("Contenuto nascosto").privacySensitive()), frame: frame)

        #expect(renderer.lights.isEmpty)
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
        func apply(
            path        : CGPath,
            body        : NotchGlassBody,
            target      : NotchGlassBody,
            canvasBounds: CGRect,
            progress    : CGFloat,
            isVisible   : Bool
        ) {}
    }
}
