//
//  NotchHostViewTests.swift
//  CascadeKitTests
//

import AppKit
import Testing
@testable import CascadeKit

@MainActor
struct NotchHostViewTests {
    @Test
    func glassHasNoOpaqueBackingBlockingTheDesktop() throws {
        guard #available(macOS 26, *),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return }
        let host = makeHost()
        let backing = try #require(host.layer?.sublayers?.first as? CAShapeLayer)
        #expect(backing.isHidden)
        #expect(host.containsInteractivePoint(CGPoint(x: 200, y: 100)))
    }

    @Test
    func restingChromeReleasesGlassAndPreservesItsOpaqueSilhouette() throws {
        let host = makeHost()
        host.apply(
            geometry        : NotchGeometry(leftExtent: 90, rightExtent: 90, height: 33, bottomCornerRadius: 14, topCornerRadius: 4),
            centerX         : 200,
            topY            : 200,
            isChromeVisible : true,
            borderOpacity   : 0,
            materialProgress: 0
        )
        let backing = try #require(host.layer?.sublayers?.first as? CAShapeLayer)
        #expect(!backing.isHidden)
        #expect(host.containsInteractivePoint(CGPoint(x: 200, y: 180)))
        #expect(!host.containsInteractivePoint(CGPoint(x: 200, y: 160)))
    }

    @Test
    func glassCoordinatesPreserveTheNotchAndDetachedActivityGap() {
        let outline = CGMutablePath()
        outline.addRect(CGRect(x: 100, y: 120, width: 200, height: 80))
        outline.addRect(CGRect(x: 330, y: 140, width: 20, height: 20))
        let shape = NotchGlassShape(outline: outline)
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 250, height: 80))

        #expect(path.contains(CGPoint(x: 100, y: 10)))
        #expect(path.contains(CGPoint(x: 240, y: 50)))
        #expect(!path.contains(CGPoint(x: 220, y: 50)))
        #expect(!path.contains(CGPoint(x: 240, y: 25)))
        #expect(!path.contains(CGPoint(x: 240, y: 65)))
    }

    @Test
    func nativeContrastUsesTheCompositorAndLeavesControlsInteractive() throws {
        let host = makeHost()
        let effect = try #require(host.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView)
        #expect(effect.blendingMode == .behindWindow)
        #expect(effect.state == .active)
        #expect(!effect.isHidden)
        #expect(effect.hitTest(CGPoint(x: 200, y: 100)) == nil)
        #expect(host.containsInteractivePoint(CGPoint(x: 200, y: 61)))
        #expect(!host.containsInteractivePoint(CGPoint(x: 200, y: 59)))
    }

    @Test
    func hidingChromeDeactivatesTheNativeContrastEffect() throws {
        let host = makeHost()
        let effect = try #require(host.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView)
        host.apply(
            geometry: NotchGeometry(leftExtent: 90, rightExtent: 90, height: 33, bottomCornerRadius: 14, topCornerRadius: 4),
            centerX: 200,
            topY: 200,
            isChromeVisible: true,
            borderOpacity: 0
        )
        #expect(effect.isHidden)
        #expect(effect.state == .inactive)
    }

    @Test
    func nativeMaterialCoversTheBottomRimAndHaloAtFullExpansion() throws {
        let host = makeHost()
        host.apply(
            geometry: NotchGeometry(leftExtent: 140, rightExtent: 140, height: 200, bottomCornerRadius: 22, topCornerRadius: 8),
            centerX: 200,
            topY: 200,
            isChromeVisible: true
        )
        let effect = try #require(host.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView)
        let shape = try #require(host.layer?.sublayers?.first as? CAShapeLayer)
        let outline = try #require(shape.path?.boundingBoxOfPath)
        #expect(effect.frame.contains(outline.insetBy(dx: 0, dy: -NotchBorderRenderer.visualOutset)))
    }

    @Test
    func hitTestingDeliversClicksToControlsInsideTheShape() {
        let host = makeHost()
        let button = NSButton(frame: CGRect(x: 100, y: 100, width: 60, height: 30))
        host.addSubview(button)
        #expect(host.hitTest(CGPoint(x: 120, y: 115)) === button)
    }

    @Test
    func roundedCornerDoesNotConsumeTheUnderlyingMenuClick() {
        let host = makeHost()
        #expect(host.hitTest(CGPoint(x: 60, y: 61)) == nil)
        #expect(host.hitTest(CGPoint(x: 20, y: 115)) == nil)
    }

    @Test
    func haloGutterDoesNotShiftTheInteractiveOutline() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 212))
        let host = makeHost()
        root.addSubview(host)
        host.setFrameOrigin(CGPoint(x: 0, y: 12))

        // AppKit supplies superview coordinates: y=71 is below the path's
        // actual lower edge at 72, despite lying inside its unshifted bounds.
        #expect(host.hitTest(CGPoint(x: 200, y: 71)) == nil)
        #expect(host.hitTest(CGPoint(x: 200, y: 73)) != nil)
    }

    private func makeHost() -> NotchHostView {
        let host = NotchHostView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        host.apply(
            geometry: NotchGeometry(
                leftExtent: 140,
                rightExtent: 140,
                height: 140,
                bottomCornerRadius: 22,
                topCornerRadius: 8
            ),
            centerX: 200,
            topY: 200,
            isChromeVisible: true
        )
        return host
    }
}
