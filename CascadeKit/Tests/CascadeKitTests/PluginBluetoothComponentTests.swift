//
//  PluginBluetoothComponentTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

/// PluginBluetoothComponentTests check the Bluetooth notice's tier-2 components and the official
/// artwork behind `bluetooth.device`: the ring draws only a known charge of a connected device,
/// the resolver reads only Apple's catalogs and exact aliases, and the turntable plays one bounded
/// turn, never restarts on enrichment and lets go of every image when it leaves the screen. The
/// artwork checks read the files installed with macOS and are skipped where they are missing.
@MainActor
struct PluginBluetoothComponentTests {

    /// arcPixels counts the pixels the ring draws at more than half opacity: the charge arc, not
    /// its dimmed track.
    private func arcPixels(_ parameters: [String: PluginValue]) throws -> Int {
        let frame: PluginModifier = .frame(width: 18, height: 18, maxWidth: nil, maxHeight: nil, alignment: .center)
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: PluginNode(.component(id: "bluetooth.battery", version: 1, parameters: parameters), modifiers: [frame]))))
        let image  = try #require(ImageRenderer(content: PluginDocumentView(store: store)).cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)

        return (0..<bitmap.pixelsWide).reduce(0) { count, x in
            count + (0..<bitmap.pixelsHigh).count { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
        }
    }

    @Test
    func theRingDrawsAKnownChargeOfAConnectedDeviceOnly() throws {
        let full = try arcPixels(["level": .number(100), "isConnected": .bool(true)])

        #expect(try arcPixels(["level": .number(30), "isConnected": .bool(true)]) > 0)
        #expect(try arcPixels(["level": .number(30), "isConnected": .bool(true)]) < full)
        #expect(try arcPixels(["level": .number(1e300), "isConnected": .bool(true)]) == full)
        #expect(try arcPixels(["level": .number(80), "isConnected": .bool(false)]) == 0)
        #expect(try arcPixels(["isConnected": .bool(true)]) == 0)
        #expect(try arcPixels(["level": .number(0), "isConnected": .bool(true)]) == 0)
    }

    @Test
    func theNotchOffersBothBluetoothComponents() {
        #expect(PluginSurfaceRouter.components.isSuperset(of: ["bluetooth.device", "bluetooth.battery"]))
    }

    @Test
    func theResolverReadsOnlyAppleCatalogsAndExactAliases() throws {
        let root    = FileManager.default.temporaryDirectory.appendingPathComponent("cascade-airpods-\(UUID().uuidString)")
        let catalog = root.appendingPathComponent("Catalog")
        let banners = root.appendingPathComponent("Banners")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        let entries: [String: [String: Any]] = [
            "0x200E": ["DisplayName": "AirPods Pro", "ImageName": "B298.png"],
            "0x2014": ["DisplayName": "AirPods Pro 2", "ImageName": "B698.icns"],
            "0x2024": ["DisplayName": "AirPods Pro 2", "ImageName": "B698.icns"],
            "0x201F": ["DisplayName": "AirPods Max", "ImageName": "B515c.png", "Color": ["0x14": "B515c-blue.png"]],
            "0x2002": ["DisplayName": "AirPods", "ImageName": "../B188.png"],
            "0x1234": ["DisplayName": "Beats Studio", "ImageName": "B298.png"],
        ]
        try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
            .write(to: catalog.appendingPathComponent("AssetPaths.plist"))
        for image in ["B298.png", "B698.icns", "B515c.png", "B515c-blue.png"] {
            try Data([1, 2, 3]).write(to: catalog.appendingPathComponent(image))
        }
        for movie in ["Banner-PID-8212-mov/Banner-PID-8212-Loop.mov", "Banner-PID-8223-mov/Banner-PID-8223-20-Loop.mov"] {
            let url = banners.appendingPathComponent(movie)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: url)
        }
        let resolver = OfficialHeadphoneAssetResolver(catalogDirectory: catalog, bannerDirectory: banners)

        let usbC       = try resolver.resolve(productID: 0x2024, colorID: nil)
        let maxBlue    = try resolver.resolve(productID: 0x201F, colorID: 20)
        let maxUnknown = try resolver.resolve(productID: 0x201F, colorID: 99)
        let pro        = try resolver.resolve(productID: 0x200E, colorID: nil)

        #expect(usbC?.imageURL.lastPathComponent == "B698.icns")
        #expect(usbC?.movieURL?.lastPathComponent == "Banner-PID-8212-Loop.mov", "A sibling's movie is used only for identical artwork")
        #expect(maxBlue?.imageURL.lastPathComponent == "B515c-blue.png")
        #expect(maxBlue?.movieURL?.lastPathComponent == "Banner-PID-8223-20-Loop.mov")
        #expect(maxUnknown?.imageURL.lastPathComponent == "B515c.png")
        #expect(maxUnknown?.movieURL == nil)
        #expect(pro?.imageURL.lastPathComponent == "B298.png" && pro?.movieURL == nil)
        #expect(try resolver.resolve(productID: 0xFFFF, colorID: nil) == nil)
        #expect(try resolver.resolve(productID: 0x1234, colorID: nil) == nil, "Only AirPods entries are read")
        #expect(try resolver.resolve(productID: 0x2002, colorID: nil) == nil, "An image name with a path is refused")
        #expect(try OfficialHeadphoneAssetResolver(catalogDirectory: root.appendingPathComponent("Missing")).resolve(productID: 0x200E, colorID: nil) == nil)
    }

    @Test(.enabled(if: Self.installedProAsset != nil))
    func theInstalledArtworkDecodesAsOneBoundedTurnOrAPoster() async throws {
        let asset = try #require(Self.installedProAsset)

        let turn   = try await Task.detached { try await OfficialHeadphoneArtwork.load(asset: asset, includeMotion: true) }.value
        let poster = try await Task.detached { try await OfficialHeadphoneArtwork.load(asset: asset, includeMotion: false) }.value
        let still  = try await Task.detached {
            try await OfficialHeadphoneArtwork.load(asset: OfficialHeadphoneAsset(imageURL: asset.imageURL, movieURL: nil), includeMotion: true)
        }.value

        #expect(turn.frames.count == 48)
        #expect(turn.duration == 3)
        #expect(turn.poster.width <= 96 && turn.poster.height <= 96)
        #expect(poster.frames.isEmpty, "Reduce Motion keeps no frames")
        #expect(still.frames.isEmpty && still.poster.width <= 96, "A missing movie keeps Apple's still image")
    }

    @Test(.enabled(if: Self.installedProAsset != nil))
    func theTurntablePlaysOnceNeverRestartsAndLetsGoOffScreen() async throws {
        let surface   = AirPodsTurntableSurface()
        surface.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        let window    = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 96, height: 96), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = surface
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        surface.configure(model: .airPodsPro, productID: 0x200E, allowsAnimation: true, isActive: true)
        #expect(try await eventually { surface.layer?.animationKeys()?.count == 1 })
        let turn = surface.layer?.animation(forKey: "airpods.connectionTurn")
        #expect(turn?.duration == 3)
        #expect(turn?.repeatCount == 1)

        surface.configure(model: .airPodsPro, productID: 0x200E, allowsAnimation: true, isActive: true)
        #expect(surface.layer?.animationKeys()?.count == 1, "An enrichment must not restart the turn")

        surface.configure(model: .airPodsPro, productID: 0x200E, allowsAnimation: false, isActive: true)
        #expect(surface.layer?.animationKeys()?.isEmpty != false)
        #expect(surface.layer?.contents != nil)

        window.contentView = nil
        #expect(surface.layer?.contents == nil, "Leaving the window releases every image")

        let hidden = AirPodsTurntableSurface()
        hidden.configure(model: .airPods, productID: 0x2002, allowsAnimation: true, isActive: true)
        hidden.configure(model: .airPodsPro, productID: 0x200E, allowsAnimation: true, isActive: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(hidden.layer?.contents == nil, "A cancelled decode never fills hidden content")
    }

    nonisolated private static var installedProAsset: OfficialHeadphoneAsset? {
        (try? OfficialHeadphoneAssetResolver().resolve(productID: 0x200E, colorID: nil)).flatMap { $0?.movieURL == nil ? nil : $0 }
    }

    /// eventually waits, for at most five seconds, until `condition` holds.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        return condition()
    }
}
