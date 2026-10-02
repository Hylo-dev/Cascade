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
                    PluginNode(.clock, modifiers: [.font(PluginFont(size: 18, weight: .semibold, design: .rounded, monospacedDigit: true))]),
                    PluginNode(.today, modifiers: [.foregroundStyle(.hierarchical(.secondary))]),
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

    @Test
    func aToggleShowsItsOptimisticStateAtOnce() async throws {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        let document  = try PluginDocument(
            root: PluginNode(
                .toggle(isOn: true, action: "togglePlayback"),
                id      : "play",
                children: [PluginNode(.symbol(name: "play.fill")), PluginNode(.symbol(name: "pause.fill"))]
            )
        )
        store.apply(publisher.publish(document))
        let host   = NSHostingView(rootView: PluginDocumentView(store: store))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        try await Task.sleep(for: .milliseconds(100))
        let playing = snapshot(of: host)
        try await Task.sleep(for: .milliseconds(100))

        #expect(snapshot(of: host) == playing)

        store.set(.bool(false), on: try #require(store.model(PluginNodeID(rawValue: "#play:toggle"))))
        try await Task.sleep(for: .milliseconds(400))

        #expect(snapshot(of: host) != playing)
    }

    /// snapshot draws the view offscreen and returns its pixels.
    private func snapshot(of view: NSView) -> Data? {
        view.layoutSubtreeIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }

        view.cacheDisplay(in: view.bounds, to: image)
        return image.tiffRepresentation
    }

    @Test
    func theTodayNodeShowsTodaysWeekdayDayAndMonth() throws {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: PluginNode(.today))))
        let drawn    = NSHostingView(rootView: PluginDocumentView(store: store))
        let expected = NSHostingView(rootView: Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)))

        #expect(drawn.fittingSize == expected.fittingSize)
    }

    @Test
    func everyCatalogComponentIsDrawnAndAnUnknownOneOnlyKeepsItsFrame() throws {
        /// opaquePixels counts the pixels a component draws at more than half opacity, so a bar's
        /// fill tells from its dimmed track.
        func opaquePixels(
            _ id        : String,
            _ parameters: [String: PluginValue] = ["percentage": .number(80)]
        ) throws -> Int {
            let frame: PluginModifier = .frame(width: 26, height: 12, maxWidth: nil, maxHeight: nil, alignment: .center)
            var publisher = PluginRenderFixtures.Publisher()
            let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
            store.apply(publisher.publish(try PluginDocument(root: PluginNode(.component(id: id, version: 1, parameters: parameters), modifiers: [frame]))))
            let image  = try #require(ImageRenderer(content: PluginDocumentView(store: store)).cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)

            return (0..<bitmap.pixelsWide).reduce(0) { count, x in
                count + (0..<bitmap.pixelsHigh).count { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
            }
        }

        #expect(try opaquePixels("power.battery") > 0)
        #expect(try opaquePixels("audio.spectrum") == 0)
        #expect(try opaquePixels("volume.level", ["level": .number(50)]) > 0)
        #expect(try opaquePixels("volume.level", ["level": .number(50)]) < (try opaquePixels("volume.level", ["level": .number(100)])))
        #expect(try opaquePixels("power.battery", ["percentage": .number(1e300)]) > 0)
        #expect(try opaquePixels("volume.level", ["level": .number(-1e300)]) == 0)
    }

    @Test
    func aChargingBatteryShowsItsBolt() throws {
        /// whitePixels counts the near-white pixels of a battery, which only its bolt draws.
        func whitePixels(isCharging: Bool) throws -> Int {
            let frame: PluginModifier = .frame(width: 30, height: 14, maxWidth: nil, maxHeight: nil, alignment: .center)
            var publisher = PluginRenderFixtures.Publisher()
            let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
            let battery   = PluginNode(.component(id: "power.battery", version: 1, parameters: ["percentage": .number(60), "isCharging": .bool(isCharging)]), modifiers: [frame])
            store.apply(publisher.publish(try PluginDocument(root: battery)))
            let renderer = ImageRenderer(content: PluginDocumentView(store: store))
            renderer.scale = 3
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))

            return (0..<bitmap.pixelsWide).reduce(0) { count, x in
                count + (0..<bitmap.pixelsHigh).count { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }

                    return color.alphaComponent > 0.9 && color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9
                }
            }
        }

        #expect(try whitePixels(isCharging: true) > 0)
        #expect(try whitePixels(isCharging: false) == 0)
    }

    @Test
    func aViewThatFitsShowsTheFirstAlternativeThatFits() throws {
        /// image renders a view into a fixed slot, so two renders compare pixel for pixel.
        func image(_ view: some View, width: CGFloat) throws -> Data {
            let renderer = ImageRenderer(content: view.frame(width: width, height: 20))
            let bitmap   = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))

            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
        func document(width: CGFloat) throws -> Data {
            var publisher = PluginRenderFixtures.Publisher()
            let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
            let fits      = PluginNode(.viewThatFits(axes: .horizontal), children: [PluginNode(.text("WWWWWWWWWWWW")), PluginNode(.text("W"))])
            store.apply(publisher.publish(try PluginDocument(root: fits)))

            return try image(PluginDocumentView(store: store), width: width)
        }

        #expect(try document(width: 30) == (try image(Text(verbatim: "W"), width: 30)))
        #expect(try document(width: 400) == (try image(Text(verbatim: "WWWWWWWWWWWW"), width: 400)))
    }

    @Test
    func aBatteryCanShowItsChargeKnockedOutOfItsBody() throws {
        /// opaque counts the pixels a full battery covers; digits cut out of it cover fewer.
        func opaque(showsPercentage: Bool) throws -> Int {
            let frame: PluginModifier = .frame(width: 40, height: 18, maxWidth: nil, maxHeight: nil, alignment: .center)
            var publisher = PluginRenderFixtures.Publisher()
            let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
            let battery   = PluginNode(.component(id: "power.battery", version: 1, parameters: ["percentage": .number(100), "showsPercentage": .bool(showsPercentage)]), modifiers: [frame])
            store.apply(publisher.publish(try PluginDocument(root: battery)))
            let renderer = ImageRenderer(content: PluginDocumentView(store: store))
            renderer.scale = 3
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))

            return (0..<bitmap.pixelsWide).reduce(0) { count, x in
                count + (0..<bitmap.pixelsHigh).count { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
            }
        }

        #expect(try opaque(showsPercentage: true) < (try opaque(showsPercentage: false)))
    }
}
