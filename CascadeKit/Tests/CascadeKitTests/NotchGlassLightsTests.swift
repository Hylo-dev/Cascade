//
//  NotchGlassLightsTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CascadeKit
import SwiftUI
import Testing

@Suite
struct NotchGlassLightsTests {

    private func light(_ x: Double) throws -> GlassLight {
        try GlassLight(
            x        : x,
            y        : 0.5,
            radius   : 0.4,
            red      : 1,
            green    : 0.3,
            blue     : 0.1,
            intensity: 0.6
        )
    }

    @Test
    func reductionRetainsEarlierSourcesAndCapsCombinedLights() throws {
        let first  = try light(0.2)
        let second = try light(0.8)
        var value  = NotchGlassLightsPreferenceKey.defaultValue
        #expect(value.isEmpty)

        NotchGlassLightsPreferenceKey.reduce(value: &value) { Array(repeating: first, count: 5) }
        NotchGlassLightsPreferenceKey.reduce(value: &value) { Array(repeating: second, count: 5) }
        #expect(value == Array(repeating: first, count: 5) + Array(repeating: second, count: 3))

        NotchGlassLightsPreferenceKey.reduce(value: &value) {
            Issue.record("A full light budget should not request more contributions")
            return [first]
        }
        #expect(value.count == 8)
    }

    @Test
    func reductionBoundsAnOversizedInitialContribution() throws {
        let first = try light(0.2)
        var value = Array(repeating: first, count: 20)
        NotchGlassLightsPreferenceKey.reduce(value: &value) { [] }

        #expect(value == Array(repeating: first, count: 8))
    }

    @MainActor
    private final class ReceivedLights {

        var value: [GlassLight]?
    }

    @MainActor
    private func receivedLights(from view: some View) async throws -> [GlassLight] {
        let received = ReceivedLights()
        let host     = NSHostingView(
            rootView: view.onPreferenceChange(NotchGlassLightsPreferenceKey.self) { lights in
                Task { @MainActor in received.value = lights }
            }
        )
        host.frame = NSRect(x: 0, y: 0, width: 160, height: 80)
        host.layoutSubtreeIfNeeded()

        for _ in 0..<20 where received.value == nil {
            try await Task.sleep(for: .milliseconds(10))
            host.layoutSubtreeIfNeeded()
        }

        return try #require(received.value)
    }

    @Test
    @MainActor
    func nativeModifierPreservesDescendantsAndBoundsItsOwnContribution() async throws {
        let child  = try light(0.2)
        let parent = try light(0.8)
        let value  = try await receivedLights(
            from: Text("Music")
                .notchGlassLights([child])
                .notchGlassLights(Array(repeating: parent, count: 10))
        )

        #expect(value == [child] + Array(repeating: parent, count: 7))
    }
}
