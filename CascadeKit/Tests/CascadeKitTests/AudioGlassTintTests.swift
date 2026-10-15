//
//  AudioGlassTintTests.swift
//  CascadeKit
//

import CoreGraphics
import Testing
@testable import CascadeKit

struct AudioGlassTintTests {

    /// icon draws a 64-point square: a white ground with a coloured disc in the middle and clear
    /// corners, the shape of a real app icon.
    private func icon(
        disc   : CGColor,
        ground : CGColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    ) throws -> CGImage {
        let space   = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data            : nil,
            width           : 64,
            height          : 64,
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : space,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(ground)
        context.fill(CGRect(x: 8, y: 8, width: 48, height: 48))
        context.setFillColor(disc)
        context.fillEllipse(in: CGRect(x: 20, y: 20, width: 24, height: 24))

        return try #require(context.makeImage())
    }

    @Test
    func theIconsColourWinsOverItsWhiteGroundAndClearCorners() throws {
        let image = try icon(disc: CGColor(srgbRed: 1, green: 0.2, blue: 0.4, alpha: 1))
        let tint  = try #require(AudioGlassTint.dominant(in: image))

        #expect(abs(tint.red - 1) < 0.001)
        #expect(tint.green < 0.4)
        #expect(tint.blue > tint.green)
    }

    @Test
    func aDarkColourIsLiftedToFullBrightness() throws {
        let image = try icon(disc: CGColor(srgbRed: 0, green: 0, blue: 0.4, alpha: 1))
        let tint  = try #require(AudioGlassTint.dominant(in: image))

        #expect(abs(tint.blue - 1) < 0.001)
        #expect(tint.red < 0.1)
    }

    @Test
    func anIconWithNoColourKeepsTheDefaultLight() throws {
        let grey = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)

        #expect(AudioGlassTint.dominant(in: try icon(disc: grey, ground: grey)) == nil)
    }
}
