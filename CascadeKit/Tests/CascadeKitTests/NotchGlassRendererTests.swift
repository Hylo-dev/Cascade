import AppKit
import CascadeContracts
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct NotchGlassRendererTests {
    private let canvas   = CGRect(x: 0, y: 0, width: 600, height: 260)
    private let expanded = NotchGeometry(leftExtent: 220, rightExtent: 220, height: 144, bottomCornerRadius: 44, topCornerRadius: 18)
    private let halfway  = NotchGeometry(leftExtent: 150, rightExtent: 150, height: 90, bottomCornerRadius: 30, topCornerRadius: 11)
    private let resting  = NotchGeometry(leftExtent: 92, rightExtent: 92, height: 32, bottomCornerRadius: 14, topCornerRadius: 4)

    @Test
    func settledGlassIsLaidOutAtTheBodyWithoutATransform() throws {
        guard #available(macOS 26, *) else { return }
        let (renderer, glass) = try makeRenderer()
        apply(renderer, body: expanded, target: expanded)

        #expect(glass.frame == body(expanded).rect)
        // Nominal radius whose native continuous corner spans the outline's 44.
        #expect(abs(glass.cornerRadius * ContinuousNotchCorner.spanPerRadius - 44) < 0.001)
        #expect(ContinuousNotchCorner.spanPerRadius > 1)
        #expect(try #require(glass.layer).affineTransform().isIdentity)
    }

    @Test
    func lensOpensTheGlassBackgroundFilterAndLeavesUnknownKeysAlone() throws {
        let backdropType = try #require(NSClassFromString("CABackdropLayer") as? CALayer.Type)
        let filterType = try #require(NSClassFromString("CAFilter") as? NSObject.Type)
        let filter = try #require(
            filterType.perform(NSSelectorFromString("filterWithType:"), with: "glassBackground")?
                .takeUnretainedValue() as? NSObject
        )
        filter.setValue("glassBackground", forKey: "name")
        filter.setValue(10.0, forKey: "inputBlurRadius")
        filter.setValue(0.0, forKey: "inputRefractionOpacity")
        let backdrop = backdropType.init()
        backdrop.filters = [filter]
        let root = CALayer()
        let nested = CALayer()
        nested.addSublayer(backdrop)
        root.addSublayer(nested)

        #expect(NotchGlassLens.open(in: CALayer()) == .missing)
        #expect(NotchGlassLens.open(in: root) == .opened)
        #expect(NotchGlassLens.open(in: root) == .alreadyOpen)

        let tuned = try #require(backdrop.filters?.first as? NSObject)
        #expect(tuned.value(forKey: "inputBlurRadius") as? Double == 0)
        #expect(tuned.value(forKey: "inputRefractionOpacity") as? Double == 1)
        #expect(tuned.value(forKey: "inputFaceColorMatrixBlack") as? Double == 0)
        #expect(tuned.value(forKey: "inputFaceColorMatrixWhite") as? Double == 1)
        let fill = try #require(tuned.value(forKey: NotchGlassLens.faceFillKey).map { $0 as AnyObject })
        #expect(CFEqual(fill, NotchGlassLens.faceFill))
        // A layer without the filter is untouched.
        #expect(root.filters == nil)
    }

    @Test
    func openingLaysOutOnceAtTheTargetAndTransformsOntoTheBody() throws {
        guard #available(macOS 26, *) else { return }
        let (renderer, glass) = try makeRenderer()
        apply(renderer, body: halfway, target: expanded)

        #expect(glass.frame == body(expanded).rect)
        let layer = try #require(glass.layer)
        #expect(layer.affineTransform() == body(halfway).transform(from: body(expanded), anchor: layer.anchorPoint))
    }

    @Test
    func collapsingKeepsTheLargerLayoutUntilHidden() throws {
        guard #available(macOS 26, *) else { return }
        let (renderer, glass) = try makeRenderer()
        apply(renderer, body: expanded, target: expanded)
        apply(renderer, body: halfway, target: resting)
        #expect(glass.frame == body(expanded).rect)

        // Hidden at rest: the next session lays out again from its own target.
        renderer.apply(path: path(resting), body: body(resting), target: body(resting), canvasBounds: canvas, progress: 0, isVisible: false)
        #expect(renderer.view.isHidden)
        apply(renderer, body: halfway, target: halfway)
        #expect(glass.frame == body(halfway).rect)
    }

    @Test
    func lightsKeepTheirCenterAndRadiusWithinTheOutline() throws {
        guard #available(macOS 26, *) else { return }
        let (renderer, _) = try makeRenderer()
        let light = try GlassLight(x: 0.25, y: 0.2, radius: 0.1, red: 1, green: 0.1, blue: 0, intensity: 0.8)
        renderer.setLights([light])
        apply(renderer, body: expanded, target: expanded, progress: 1)

        // Below the glass, above the black backing it absorbs them with.
        let lights = try #require(renderer.view.subviews[1].layer?.sublayers?.first)
        let bounds = path(expanded).boundingBoxOfPath
        #expect(lights.frame == bounds)
        #expect(lights.opacity == 1)
        let layer = try #require(lights.sublayers?.first as? CAGradientLayer)
        #expect(layer.type == .radial)
        // Center at (x, y) of the outline with y from the top; radius on width.
        #expect(abs(layer.frame.midX - 0.25 * bounds.width) < 0.001)
        #expect(abs(layer.frame.midY - 0.8 * bounds.height) < 0.001)
        #expect(abs(layer.frame.width - 0.2 * bounds.width) < 0.001)
    }

    @Test
    func aChangingLightReusesItsLayerAndCarriesIntensityAsOpacity() throws {
        guard #available(macOS 26, *) else { return }
        let (renderer, _) = try makeRenderer()
        apply(renderer, body: expanded, target: expanded, progress: 1)
        renderer.setLights([try GlassLight(x: 0.2, y: 0.5, radius: 0.3, red: 1, green: 0.2, blue: 0.1, intensity: 0.4)])
        let lights = try #require(renderer.view.subviews[1].layer?.sublayers?.first)
        let layer = try #require(lights.sublayers?.first as? CAGradientLayer)
        let colors = try #require(layer.colors as? [CGColor])

        renderer.setLights([try GlassLight(x: 0.2, y: 0.5, radius: 0.4, red: 1, green: 0.2, blue: 0.1, intensity: 0.9)])

        #expect(lights.sublayers?.first === layer)
        #expect(layer.opacity == 0.9)
        #expect((layer.colors as? [CGColor]) == colors)
        #expect(abs(layer.frame.width - 0.8 * lights.bounds.width) < 0.001)
    }

    @Test
    func lightsRebuiltForANewCountStillCarryTheirColors() throws {
        guard #available(macOS 26, *) else { return }
        let (renderer, _) = try makeRenderer()
        apply(renderer, body: expanded, target: expanded, progress: 1)
        let halo = try GlassLight(x: 0.2, y: 0.5, radius: 0.1, red: 1, green: 0.2, blue: 0.1, intensity: 0.6)
        let wash = try GlassLight(x: 0.2, y: 0.5, radius: 0.5, red: 1, green: 0.2, blue: 0.1, intensity: 0.4)
        renderer.setLights([halo, wash])

        // Pausing drops the halo: the remaining light shares its hue.
        renderer.setLights([wash])

        let lights = try #require(renderer.view.subviews[1].layer?.sublayers?.first)
        let layer = try #require(lights.sublayers?.first as? CAGradientLayer)
        #expect(lights.sublayers?.count == 1)
        #expect((layer.colors?.count ?? 0) == 4)
    }

    // MARK: - Fixture

    @available(macOS 26, *)
    private func makeRenderer() throws -> (NotchGlassRenderer, NSGlassEffectView) {
        let renderer = NotchGlassRenderer()
        let glass = try #require(renderer.view.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        return (renderer, glass)
    }

    private func apply(
        _ renderer: NotchGlassRenderer,
        body     : NotchGeometry,
        target   : NotchGeometry,
        progress : CGFloat = 0.6
    ) {
        renderer.apply(
            path        : path(body),
            body        : self.body(body),
            target      : self.body(target),
            canvasBounds: canvas,
            progress    : progress,
            isVisible   : true
        )
    }

    private func body(_ geometry: NotchGeometry) -> NotchGlassBody {
        NotchGlassBody(geometry: geometry, centerX: canvas.midX, topY: canvas.maxY)
    }

    private func path(_ geometry: NotchGeometry) -> CGPath {
        CGPath.notch(geometry: geometry, centerX: canvas.midX, topY: canvas.maxY)
    }
}
