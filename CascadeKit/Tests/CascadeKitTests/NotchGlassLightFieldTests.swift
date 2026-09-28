import AppKit
import CascadeContracts
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct NotchGlassLightFieldTests {
    @Test
    func renderedLightKeepsItsColorAndFallsOffToTransparency() throws {
        let light = try GlassLight(x: 0.25, y: 0.5, radius: 0.2, red: 1, green: 0.1, blue: 0, intensity: 0.8)
        let renderer = ImageRenderer(content: NotchGlassLightField(lights: [light]).frame(width: 200, height: 100))
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let center = try #require(bitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB))
        let edge = try #require(bitmap.colorAt(x: 80, y: 50))
        let outside = try #require(bitmap.colorAt(x: 150, y: 50))
        #expect(center.redComponent > center.greenComponent * 4)
        #expect(center.alphaComponent > 0.7)
        #expect(edge.alphaComponent < center.alphaComponent * 0.25)
        #expect(outside.alphaComponent == 0)
    }
}
