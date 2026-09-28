import CascadeContracts
import Foundation
import Testing
@testable import CascadeKit

struct NotchGlassLightSourcesTests {
    @Test
    func replacedContentCannotRelightTheGlass() throws {
        let source = NSObject()
        var sources = NotchGlassLightSources()
        let old = sources.replace(source: ObjectIdentifier(source))
        let light = try makeLight(red: 1)
        let acceptedInitial = sources.update([light], for: old)
        #expect(acceptedInitial)
        let current = sources.replace(source: ObjectIdentifier(source))
        #expect(sources.lights.isEmpty)
        let acceptedLate = sources.update([light], for: old)
        #expect(!acceptedLate)
        #expect(sources.lights.isEmpty)
        let acceptedCurrent = sources.update([light], for: current)
        #expect(acceptedCurrent)
        #expect(sources.lights == [light])
        let acceptedDuplicate = sources.update([light], for: current)
        #expect(!acceptedDuplicate)
    }

    @Test
    func removingOneWidgetKeepsTheOtherWidgetLight() throws {
        let first = NSObject(), second = NSObject()
        var sources = NotchGlassLightSources()
        let a = sources.replace(source: ObjectIdentifier(first))
        let b = sources.replace(source: ObjectIdentifier(second))
        let red = try makeLight(red: 1), dim = try makeLight(red: 0.2)
        _ = sources.update([red], for: a)
        _ = sources.update([dim], for: b)
        #expect(sources.lights == [red, dim])
        _ = sources.replace(source: ObjectIdentifier(first))
        #expect(sources.lights == [dim])
    }

    @Test
    func combinedSourcesHaveAFixedRenderingBudget() throws {
        let first = NSObject(), second = NSObject()
        var sources = NotchGlassLightSources()
        let a = sources.replace(source: ObjectIdentifier(first))
        let b = sources.replace(source: ObjectIdentifier(second))
        let red = try makeLight(red: 1), dim = try makeLight(red: 0.2)
        _ = sources.update(Array(repeating: red, count: 6), for: a)
        _ = sources.update(Array(repeating: dim, count: 6), for: b)
        #expect(sources.lights == Array(repeating: red, count: 6) + [dim, dim])
    }

    private func makeLight(red: Double) throws -> GlassLight {
        try GlassLight(x: 0.2, y: 0.6, radius: 0.4, red: red, green: 0.2, blue: 0.3, intensity: 0.5)
    }
}
