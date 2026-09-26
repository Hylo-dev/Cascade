//
//  ChargingGlowTests.swift
//  CascadeKitTests
//

import AppKit
import QuartzCore
import Testing
@testable import CascadeKit

@MainActor
struct ChargingGlowTests {
    @Test(arguments: [NotchBorderAppearance.charging, .chargingLowPower])
    func chargingWashFadesToTransparentWithoutBecomingAnOpaqueStrip(appearance: NotchBorderAppearance) throws {
        let renderer = makeRenderer(appearance)
        let layer = renderer.chargingGlow
        let canvas = CALayer()
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
        canvas.addSublayer(layer)
        let context = try #require(CGContext(
            data: nil,
            width: 400,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        canvas.render(in: context)
        // The context owns this buffer for the entire read. Both sample pixels
        // are bounded by its fixed 400×100 RGBA allocation.
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        // CALayer renders into top-first bitmap rows; the canvas uses AppKit's
        // bottom-left coordinates. Sample y=48 and y=59 below the y=60 rim.
        let outerAlpha = pixels[((100 - 48 - 1) * 400 + 200) * 4 + 3]
        let innerAlpha = pixels[((100 - 59 - 1) * 400 + 200) * 4 + 3]
        #expect(outerAlpha < 8)
        #expect(innerAlpha > 30)
        #expect(innerAlpha < 70)
    }

    @Test
    func ordinaryNoticesAndAccessibilityPreferencesRemoveTheChargingWash() {
        let renderer = makeRenderer(.charging)
        #expect(!renderer.chargingGlow.isHidden)
        renderer.setAppearance(.neutral, animated: false, reducesTransparency: false, increasesContrast: false)
        #expect(renderer.chargingGlow.isHidden)
        renderer.setAppearance(.chargingLowPower, animated: false, reducesTransparency: true, increasesContrast: false)
        #expect(renderer.chargingGlow.isHidden)
        renderer.setAppearance(.charging, animated: false, reducesTransparency: false, increasesContrast: false)
        #expect(!renderer.chargingGlow.isHidden)
        renderer.apply(
            path: CGPath(rect: CGRect(x: 40, y: 60, width: 320, height: 40), transform: nil),
            canvasBounds: CGRect(x: 0, y: 0, width: 400, height: 100),
            isVisible: false,
            opacity: 1,
            scale: 2
        )
        #expect(renderer.chargingGlow.isHidden)
    }

    private func makeRenderer(_ appearance: NotchBorderAppearance) -> NotchBorderRenderer {
        let renderer = NotchBorderRenderer()
        renderer.setAppearance(appearance, animated: false, reducesTransparency: false, increasesContrast: false)
        renderer.apply(
            path: CGPath(rect: CGRect(x: 40, y: 60, width: 320, height: 40), transform: nil),
            canvasBounds: CGRect(x: 0, y: 0, width: 400, height: 100),
            isVisible: true,
            opacity: 1,
            scale: 2
        )
        return renderer
    }
}
