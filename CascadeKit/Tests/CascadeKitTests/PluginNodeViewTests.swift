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
                    PluginNode(.clock, modifiers: [.font(PluginFont(size: 18, weight: .semibold, design: .rounded, monospacedDigit: true)), .timeZone("Asia/Tokyo")]),
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
                        .slider(value: 90, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 4, labels: .duration), action: "setDuration"),
                        id       : "duration",
                        modifiers: [.foregroundStyle(.color(PluginColor(red: 1, green: 0.77, blue: 0.33))), .frame(width: 260, height: 50, maxWidth: nil, maxHeight: nil, alignment: .center)]
                    ),
                    PluginNode(.sliderValue(id: "duration"), modifiers: [.font(PluginFont(size: 26, weight: .semibold, design: .rounded, monospacedDigit: true)), .lineLimit(1)]),
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

    @Test
    func aRulerIsDrawnAndRedrawsWhenItsValueMoves() async throws {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        let document  = try PluginDocument(
            root: PluginNode(
                .slider(value: 90, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 4, labels: .duration), action: "setDuration"),
                id       : "ruler",
                modifiers: [
                    .foregroundStyle(.color(PluginColor(red: 1, green: 0.77, blue: 0.33))),
                    .frame(width: 260, height: 50, maxWidth: nil, maxHeight: nil, alignment: .center),
                ]
            )
        )
        store.apply(publisher.publish(document))
        let host   = NSHostingView(rootView: PluginDocumentView(store: store))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 260, height: 50), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        try await Task.sleep(for: .milliseconds(100))
        let first = snapshot(of: host)
        try await Task.sleep(for: .milliseconds(100))

        #expect(first != nil)
        #expect(snapshot(of: host) == first)

        store.drag(135.5, on: try #require(store.model(PluginNodeID(rawValue: "#ruler:slider"))))
        try await Task.sleep(for: .milliseconds(200))

        #expect(snapshot(of: host) != first)
    }

    @Test
    func aSliderValueRedrawsWhenItsRulerIsDragged() async throws {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        let document  = try PluginDocument(
            root: PluginNode(
                .vStack(alignment: .leading, spacing: nil),
                children: [
                    PluginNode(
                        .sliderValue(id: "ruler"),
                        modifiers: [.font(PluginFont(size: 26, weight: .semibold, design: .rounded, monospacedDigit: true))]
                    ),
                    PluginNode(
                        .slider(value: 90, minimum: 15, maximum: 1_440, step: 15, style: .ruler(labelEvery: 4, labels: .duration), action: "setDuration"),
                        id: "ruler"
                    ),
                ]
            )
        )
        store.apply(publisher.publish(document))
        let host   = NSHostingView(rootView: PluginDocumentView(store: store))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 60), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        try await Task.sleep(for: .milliseconds(100))
        let first = snapshot(of: host)

        #expect(first != nil)

        store.drag(300, on: try #require(store.model(PluginNodeID(rawValue: "#ruler:slider"))))
        try await Task.sleep(for: .milliseconds(200))

        #expect(snapshot(of: host) != first)
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
    func aTimeZoneDrawsTheClockAndTheDateInThatZone() throws {
        let rome   = try #require(TimeZone(identifier: "Europe/Rome"))
        let tokyo  = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let locale = Locale(identifier: "en_GB")
        /// image renders a view in Rome, so a node that names Tokyo matches Tokyo's time only
        /// when the modifier reaches what the node draws.
        func image(_ view: some View) throws -> Data {
            let renderer = ImageRenderer(
                content: view
                    .frame(width: 120, height: 20)
                    .environment(\.timeZone, rome)
                    .environment(\.locale, locale)
            )
            let bitmap   = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))

            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
        func drawn(_ node: PluginNode) throws -> Data {
            var publisher = PluginRenderFixtures.Publisher()
            let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
            store.apply(publisher.publish(try PluginDocument(root: node)))

            return try image(PluginDocumentView(store: store))
        }
        func clock(_ date: Date, in zone: TimeZone) throws -> Data {
            try image(Text(verbatim: PluginTimeFormat.clock(date, in: zone, locale: locale)))
        }

        let before = Date.now
        let shown  = try drawn(PluginNode(.clock, modifiers: [.timeZone("Asia/Tokyo")]))
        let after  = Date.now
        let fixed  = Date(timeIntervalSince1970: 1_790_983_800)

        #expect(try [clock(before, in: tokyo), clock(after, in: tokyo)].contains(shown))
        #expect(try shown != clock(after, in: rome))
        #expect(
            try drawn(PluginNode(.date(fixed, style: .time), modifiers: [.timeZone("Asia/Tokyo")]))
                == image(Text(fixed, style: .time).environment(\.timeZone, tokyo))
        )
    }

    @Test
    func aNodeReadsTheZoneAndTheLocaleOnlyInsideAClockOrToday() throws {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: PluginNode(.text("Title")))))
        let content   = PluginNodeContent(model: try #require(store.root), store: store)

        let environment = Mirror(reflecting: content).children.filter { String(describing: type(of: $0.value)).hasPrefix("Environment<") }

        #expect(environment.isEmpty, "A node that draws no time depends on no environment value")
    }

    @Test
    func aLabelledNodeReadsAsOneElementOnlyWhenItHoldsNoControl() throws {
        /// readsAsOneElement asks the renderer about the root of a document drawn by a store.
        func readsAsOneElement(_ root: PluginNode) throws -> Bool {
            var publisher = PluginRenderFixtures.Publisher()
            let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
            store.apply(publisher.publish(try PluginDocument(root: root)))

            return PluginModifiedView.readsAsOneElement(try #require(store.root), in: store)
        }
        let label : [PluginModifier] = [.accessibilityLabel("Calendar")]
        let row    = PluginNode(.hStack(alignment: .center, spacing: nil), children: [PluginNode(.symbol(name: "sun.max")), PluginNode(.text("Sunny"))])
        let volume = PluginNode(.slider(value: 0.5, minimum: 0, maximum: 1, step: nil, action: "setVolume"))
        let button = PluginNode(.button(action: "next"), children: [PluginNode(.symbol(name: "forward.fill"))])

        #expect(try readsAsOneElement(PluginNode(.vStack(alignment: .leading, spacing: nil), modifiers: label, children: [PluginNode(.text("Mon")), row])))
        #expect(try !readsAsOneElement(PluginNode(.vStack(alignment: .leading, spacing: nil), modifiers: label, children: [PluginNode(.text("Sound")), PluginNode(.hStack(alignment: .center, spacing: nil), children: [volume])])))
        #expect(try !readsAsOneElement(PluginNode(.zStack(alignment: .center), modifiers: label + [.overlay(alignment: .topTrailing)], children: [row], layers: [button])))
        #expect(try !readsAsOneElement(PluginNode(.toggle(isOn: true, action: "togglePlayback"), modifiers: label, children: [PluginNode(.symbol(name: "pause.fill"))])))
        #expect(try !readsAsOneElement(PluginNode(.text("Mon"), modifiers: label)))
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

    @Test
    func volumeBarIsOfferedByTheKernel() {
        #expect(PluginComponentView.identifiers.isSuperset(of: ["audio.volumeBar", "audio.mixer", "audio.outputPicker"]))
    }

    private func volumeModel(level: Double) -> AudioMixerModel {
        let model = AudioMixerModel(controller: RecordingSystemAudioController())
        model.receive(
            SystemAudioState(
                level          : level,
                isMuted        : false,
                supportsVolume : true,
                outputs        : [],
                selectedUIDs   : [],
                defaultDeviceID: 7
            )
        )
        return model
    }

    /// volumeBar hosts the component the kernel draws for audio.volumeBar, with the model's
    /// services in its environment, or none.
    private func volumeBar(model: AudioMixerModel?) -> some View {
        PluginComponentView(id: "audio.volumeBar", version: 1, parameters: [:])
            .environment(\.pluginComponentServices, model.map { PluginComponentServices(audio: $0) })
            .frame(width: 60, height: 120)
    }

    /// opaquePixels counts what a view draws at more than half opacity.
    private func opaquePixels(of view: some View) throws -> Int {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))

        return (0..<bitmap.pixelsWide).reduce(0) { count, x in
            count + (0..<bitmap.pixelsHigh).count { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
        }
    }

    @Test
    func volumeBarWithoutServicesDrawsTheUnavailableState() throws {
        let host = NSHostingView(rootView: volumeBar(model: nil))

        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize == CGSize(width: 60, height: 120))
        #expect(try opaquePixels(of: volumeBar(model: nil)) > 0)
        #expect(AudioGlobalVolumeControl.accessibilityValue(of: nil) == "\u{2014}")
    }

    @Test
    func volumeBarExposesAnAdjustableElement() {
        let model = volumeModel(level: 0.5)

        #expect(AudioGlobalVolumeControl.accessibilityLabel == "Global volume")
        #expect(AudioGlobalVolumeControl.accessibilityValue(of: model.system) == "50%")
        #expect(AudioGlobalVolumeControl.accessibilityValue(of: volumeModel(level: 0.999).system) == "100%")
    }

    @Test
    func volumeBarFillsFromTheBottomWithTheLevel() throws {
        /// whitePixels counts the near-white pixels of a bar, which only its fill draws.
        /// whitePixels counts the fill's pixels. The fill is a pearl white (about 0.82 to 0.96) in a
        /// groove that stays under 0.2 and shades the fill's top when it is full, so the line
        /// between them is drawn at 0.6, not at paper white.
        func whitePixels(level: Double) throws -> Int {
            let renderer = ImageRenderer(content: volumeBar(model: volumeModel(level: level)))
            let bitmap   = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))

            return (0..<bitmap.pixelsWide).reduce(0) { count, x in
                count + (0..<bitmap.pixelsHigh).count { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }

                    return color.alphaComponent > 0.9 && color.redComponent > 0.6
                }
            }
        }

        #expect(try whitePixels(level: 0.25) < (try whitePixels(level: 0.75)))
        #expect(try whitePixels(level: 0.75) < (try whitePixels(level: 1)))
    }
}
