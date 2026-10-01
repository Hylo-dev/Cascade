//
//  PluginNodeViewTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct PluginNodeViewTests {

    /// everything is one document that uses every node kind and every modifier, so laying it
    /// out evaluates every branch of the renderer.
    private func everything() throws -> PluginDocument {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        return try PluginDocument(
            root: PluginNode(
                .vStack(alignment: .leading, spacing: 4),
                modifiers: [
                    .padding(.all, length: 8),
                    .background(alignment: .center),
                    .overlay(alignment: .topTrailing),
                ],
                children : [
                    PluginNode(
                        .hStack(alignment: .center, spacing: nil),
                        children: [
                            PluginNode(.text("Title"), modifiers: [.font(PluginFont(style: .headline, weight: .bold)), .lineLimit(1)]),
                            PluginNode(.spacer(minLength: 4)),
                            PluginNode(.symbol(name: "music.note"), modifiers: [.contentTransition(.symbolEffect)]),
                            PluginNode(.asset(id: "art"), modifiers: [.clipShape(.roundedRectangle(cornerRadius: 6))]),
                        ]
                    ),
                    PluginNode(
                        .zStack(alignment: .bottomLeading),
                        children: [
                            PluginNode(.shape(.capsule), modifiers: [.foregroundStyle(.gradient([.white, .black]))]),
                            PluginNode(.shape(.circle), modifiers: [.frame(width: 8, height: 8, maxWidth: nil, maxHeight: nil, alignment: .center)]),
                        ]
                    ),
                    PluginNode(.date(now, style: .time), modifiers: [.font(PluginFont(size: 18, design: .rounded, monospacedDigit: true))]),
                    PluginNode(.timer(start: now, end: now.addingTimeInterval(60), countsDown: true), modifiers: [.contentTransition(.numericText(countsDown: true))]),
                    PluginNode(.timerProgress(start: now, end: now.addingTimeInterval(60))),
                    PluginNode(.progress(value: 0.4, total: 1, style: .linear), modifiers: [.opacity(0.8)]),
                    PluginNode(.progress(value: 0.4, total: 1, style: .circular), modifiers: [.transition(.scale)]),
                    PluginNode(.button(action: "next"), children: [PluginNode(.symbol(name: "forward.fill"))]),
                    PluginNode(
                        .toggle(isOn: true, action: "togglePlayback"),
                        modifiers: [.accessibilityLabel("Play")],
                        children : [PluginNode(.symbol(name: "pause.fill"))]
                    ),
                    PluginNode(.slider(value: 0.5, minimum: 0, maximum: 1, step: 0.1, action: "setVolume")),
                    PluginNode(.slider(value: 0.5, minimum: 0, maximum: 1, step: nil, action: "seek"), modifiers: [.transition(.move(.bottom))]),
                    PluginNode(
                        .component(id: "audio.spectrum", version: 1, parameters: [:]),
                        modifiers: [.foregroundStyle(.hierarchical(.secondary)), .minimumScaleFactor(0.5), .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .points(20), alignment: .leading)]
                    ),
                ],
                layers   : [
                    PluginNode(.shape(.roundedRectangle(cornerRadius: 12)), modifiers: [.foregroundStyle(.color(PluginColor(red: 0.1, green: 0.1, blue: 0.1)))]),
                    PluginNode(.symbol(name: "star.fill")),
                ]
            )
        )
    }

    @Test
    func everyNodeKindAndModifierLaysOut() throws {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try everything()))
        let host = NSHostingView(rootView: PluginDocumentView(store: store))
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 480)

        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.width > 0)
    }

    @Test
    func anEmptyStoreDrawsNothing() {
        let store = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        let host  = NSHostingView(rootView: PluginDocumentView(store: store))

        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize == .zero)
    }
}
