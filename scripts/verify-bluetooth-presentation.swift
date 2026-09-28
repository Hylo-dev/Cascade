//
//  verify-bluetooth-presentation.swift
//  Cascade
//

import AppKit
import CascadeKit
import SwiftUI

@main
@MainActor
enum BluetoothPresentationVerification {
    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let resolver = OfficialHeadphoneAssetResolver()
        let identifiers: [UInt16] = [0x2002, 0x200F, 0x200E, 0x2013, 0x2014, 0x2024, 0x2019, 0x201B, 0x2027, 0x200A, 0x201F, 0x202D]
        for identifier in identifiers {
            let asset = try resolver.resolve(productID: identifier, colorID: nil)
            precondition(asset != nil, "Official catalog must recognize verified AirPods PID \(identifier)")
            precondition(asset?.movieURL != nil, "A matching official banner must resolve for PID \(identifier)")
        }
        let unknown = try resolver.resolve(productID: 0xFFFF, colorID: nil)
        precondition(unknown == nil)
        let proAsset = try resolver.resolve(productID: 0x200E, colorID: nil)
        guard let proAsset else { throw CocoaError(.fileNoSuchFile) }
        let started = Date()
        let artwork = try await Task.detached {
            try await OfficialHeadphoneArtwork.load(asset: proAsset, includeMotion: true)
        }.value
        let decodeDuration = Date().timeIntervalSince(started)
        precondition(artwork.frames.count == 48, "Official video must decode as a real turntable")
        precondition(artwork.duration == 3)
        precondition(artwork.poster.width <= 96 && artwork.poster.height <= 96)
        let staticArtwork = try await Task.detached {
            try await OfficialHeadphoneArtwork.load(asset: proAsset, includeMotion: false)
        }.value
        precondition(staticArtwork.frames.isEmpty, "Reduced motion must not retain animation frames")
        precondition(artwork.frames[0].dataProvider?.data != artwork.frames[12].dataProvider?.data)
        guard let alphaContext = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        alphaContext.draw(artwork.poster, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        precondition(alphaContext.data?.load(as: UInt32.self) == 0, "Official movie corner must remain transparent")
        let usbC = try resolver.resolve(productID: 0x2024, colorID: nil)
        precondition(usbC?.movieURL?.lastPathComponent == "Banner-PID-8212-Loop.mov")
        let maxBlue = try resolver.resolve(productID: 0x201F, colorID: 20)
        precondition(maxBlue?.movieURL?.lastPathComponent == "Banner-PID-8223-20-Loop.mov")
        let imageOnly = OfficialHeadphoneAsset(imageURL: proAsset.imageURL, movieURL: nil)
        let staticFallback = try await Task.detached {
            try await OfficialHeadphoneArtwork.load(asset: imageOnly, includeMotion: true)
        }.value
        precondition(staticFallback.frames.isEmpty, "Missing system movie must retain the official static image")
        precondition(staticFallback.poster.width <= 96 && staticFallback.poster.height <= 96)
        let absentResolver = OfficialHeadphoneAssetResolver(catalogDirectory: URL(fileURLWithPath: "/private/tmp/cascade-no-such-official-catalog"))
        let absentCatalog = try absentResolver.resolve(productID: 0x200E, colorID: nil)
        precondition(absentCatalog == nil, "Missing system catalogs must fall back without failure")
        print("Official AirPods assets: 12 product identifiers, native aliases/colors/alpha; 48 frames decoded in \(String(format: "%.3f", decodeDuration)) seconds.")

        let unavailable = BluetoothBatteryRing(level: nil, diameter: 22, isConnected: true)
        precondition(unavailable.accessibilityLabel == String(localized: "Battery unavailable", table: "BluetoothNotice"))
        let disconnected = BluetoothBatteryRing(level: 83, diameter: 22, isConnected: false)
        precondition(disconnected.accessibilityLabel == String(localized: "Disconnected, battery unavailable", table: "BluetoothNotice"))
        let zero = BluetoothBatteryRing(level: 0, diameter: 22, isConnected: true)
        precondition(zero.accessibilityLabel == String(localized: "Battery, \(0) percent", table: "BluetoothNotice"))
        let invalid = BluetoothBatteryRing(level: 130, diameter: 22, isConnected: true)
        precondition(invalid.accessibilityLabel == String(localized: "Battery unavailable", table: "BluetoothNotice"))

        let event = BluetoothConnectionEvent(
            deviceID: "test-airpods",
            name: "AirPods Pro",
            symbolName: "airpodspro",
            isConnected: true,
            battery: BluetoothBatterySnapshot(left: 83, right: 91, caseLevel: 62),
            model: .airPodsPro,
            productID: 0x200E,
            eventID: 1,
            revision: 2
        )
        let notice = BluetoothConnectionActivity(event: event)
        precondition(notice.contentRevision == 2)
        precondition(notice.accessibilityLabel.contains(String(localized: "Left, \(83) percent", table: "BluetoothNotice")))
        precondition(notice.accessibilityLabel.contains(String(localized: "Case, \(62) percent", table: "BluetoothNotice")))

        // The real mounted surface reads Apple's installed banner assets.
        let animated = AirPodsTurntableSurface()
        animated.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        let animationWindow = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 96, height: 96), styleMask: [.borderless], backing: .buffered, defer: false)
        animationWindow.contentView = animated
        animationWindow.orderFront(nil)
        precondition(animated.layer != nil, "Unmounted NSView has not created its backing layer")
        animated.configure(model: .airPodsPro, productID: 0x200E, allowsAnimation: true, isActive: true)
        try await Task.sleep(for: .milliseconds(200))
        precondition(animated.layer?.animationKeys()?.count == 1)
        let initialAnimation = animated.layer?.animation(forKey: "airpods.connectionTurn")
        precondition(initialAnimation?.duration == 3)
        precondition(initialAnimation?.repeatCount == 1)
        animated.configure(model: .airPodsPro, productID: 0x200E, allowsAnimation: false, isActive: true)
        precondition(animated.layer?.animationKeys()?.isEmpty != false)
        precondition(animated.layer?.contents != nil)
        animationWindow.orderOut(nil)
        animationWindow.contentView = nil
        precondition(animated.layer?.contents == nil)
        precondition(animated.layer?.animationKeys()?.isEmpty != false)

        let finishes = AirPodsTurntableSurface()
        finishes.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        animationWindow.contentView = finishes
        animationWindow.orderFront(nil)
        finishes.configure(model: .airPods, productID: 0x2002, allowsAnimation: true, isActive: true)
        try await Task.sleep(for: .milliseconds(200))
        precondition(finishes.layer?.animationKeys()?.count == 1)
        try await Task.sleep(for: .milliseconds(3100))
        precondition(finishes.layer?.animationKeys()?.isEmpty != false, "One connection turn must finish")
        precondition(finishes.layer?.contents != nil, "Completion must keep the small static poster")
        finishes.configure(model: .airPods, productID: 0x2002, allowsAnimation: true, isActive: true)
        precondition(finishes.layer?.animationKeys()?.isEmpty != false, "Battery enrichment must not restart motion")
        animationWindow.orderOut(nil)
        animationWindow.contentView = nil

        let stopped = AirPodsTurntableSurface()
        stopped.configure(model: .airPods, productID: 0x2002, allowsAnimation: true, isActive: true)
        stopped.configure(model: .airPodsPro, productID: 0x200E, allowsAnimation: true, isActive: true)
        stopped.configure(model: .airPodsPro, productID: 0x200E, allowsAnimation: true, isActive: false)
        try await Task.sleep(for: .milliseconds(100))
        precondition(stopped.layer?.contents == nil, "A canceled decode must not repopulate hidden content")
        precondition(stopped.layer?.animationKeys()?.isEmpty != false)

        let posters = try await Task.detached { () throws -> [CGImage] in
            var images: [CGImage] = []
            for identifier in identifiers {
                guard let asset = try resolver.resolve(productID: identifier, colorID: nil) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                images.append(try await OfficialHeadphoneArtwork.load(asset: asset, includeMotion: false).poster)
            }
            return images
        }.value
        let names = ["AirPods 1", "AirPods 2", "AirPods Pro", "AirPods 3", "AirPods Pro 2", "AirPods Pro 2 USB-C", "AirPods 4", "AirPods 4 ANC", "AirPods Pro 3", "AirPods Max", "AirPods Max USB-C", "AirPods Max · 202D"]
        let gallery = LazyVGrid(columns: Array(repeating: GridItem(.fixed(158)), count: 3), spacing: 20) {
            ForEach(identifiers.indices, id: \.self) { index in
                VStack(spacing: 8) {
                    Image(decorative: posters[index], scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                    Text(names[index])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(24)
        .background(.black)
        let galleryRenderer = ImageRenderer(content: gallery)
        galleryRenderer.scale = 2
        if let galleryImage = galleryRenderer.cgImage,
           let galleryData = NSBitmapImageRep(cgImage: galleryImage).representation(using: .png, properties: [:]) {
            try galleryData.write(to: output.deletingLastPathComponent().appendingPathComponent("official-airpods-library.png"))
        } else {
            throw CocoaError(.coderInvalidValue)
        }

        let samples: [(String, BluetoothConnectionEvent)] = [
            ("AirPods Pro · 83%", event),
            ("AirPods · 17%", BluetoothConnectionEvent(deviceID: "airpods", name: "AirPods", symbolName: "airpods", isConnected: true, battery: BluetoothBatterySnapshot(level: 17), model: .airPods, productID: 0x2002)),
            ("Battery unavailable", BluetoothConnectionEvent(deviceID: "unknown", name: "AirPods Pro", symbolName: "airpodspro", isConnected: true, model: .airPodsPro, productID: 0x200E)),
            ("Disconnection · stale value ignored", BluetoothConnectionEvent(deviceID: "disconnected", name: "AirPods Pro", symbolName: "airpodspro", isConnected: false, battery: BluetoothBatterySnapshot(level: 83), model: .airPodsPro, productID: 0x200E)),
            ("Generic accessory · 7%", BluetoothConnectionEvent(deviceID: "generic", name: "Magic Mouse", symbolName: "computermouse.fill", isConnected: true, battery: BluetoothBatterySnapshot(level: 7)))
        ]
        let sideWidth = notice.compactPreferredSideWidth ?? 40
        let context = NotchActivityViewContext(presentation: .compactLeading, availableSize: CGSize(width: sideWidth, height: 22))
        let content = VStack(alignment: .leading, spacing: 15) {
            ForEach(samples.indices, id: \.self) { index in
                let sample = samples[index]
                let item = BluetoothConnectionActivity(event: sample.1)
                VStack(alignment: .leading, spacing: 7) {
                    Text(sample.0)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(spacing: 0) {
                        item.makeCompactLeadingView(in: context)
                            .frame(width: sideWidth, height: 22)
                        Color.black
                            .frame(width: 158, height: 22)
                        item.makeCompactTrailingView(in: context)
                            .frame(width: sideWidth, height: 22)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.black, in: Capsule())
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.13))

        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: 330, height: 420))
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.coderInvalidValue)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.coderInvalidValue)
        }
        try png.write(to: output)
        window.contentView = nil
        print("Bluetooth presentation: charge semantics, revisions, official Apple video frames, reduced motion, bounded animation, teardown and canceled decode passed.")
        print("Factory preview: \(output.path)")
    }
}
