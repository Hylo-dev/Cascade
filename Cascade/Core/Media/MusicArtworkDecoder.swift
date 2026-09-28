//
//  MusicArtworkDecoder.swift
//  Cascade
//

import CoreGraphics
import Foundation
import ImageIO

/// MusicArtworkDecoder decodes one bounded thumbnail and samples its real colors.
/// Quantized color groups preserve distinct hues instead of mixing an entire
/// cover into one average. Transparent pixels cannot tint the resulting light.
nonisolated enum MusicArtworkDecoder {
    private struct ColorGroup {
        var red   = 0.0
        var green = 0.0
        var blue  = 0.0
        var weight = 0.0

        var color: MusicArtworkColor {
            MusicArtworkColor(
                red  : red / weight,
                green: green / weight,
                blue : blue / weight
            )
        }
    }

    static func decode(_ data: Data) -> DecodedMusicArtwork? {
        guard data.count <= 8 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize         : 256,
                kCGImageSourceCreateThumbnailWithTransform  : true,
                kCGImageSourceShouldCacheImmediately        : true
              ] as CFDictionary) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 24 * 24 * 4)
        let sampled = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data            : buffer.baseAddress,
                width           : 24,
                height          : 24,
                bitsPerComponent: 8,
                bytesPerRow     : 96,
                space           : CGColorSpaceCreateDeviceRGB(),
                bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 24))
            return true
        }
        guard sampled else { return nil }
        let colors = palette(from: bytes)
        return DecodedMusicArtwork(image: image, colors: colors, glow: compactGlow(colors: colors))
    }

    /// The compact artwork's side and the glow's reach around it, in points.
    static let compactArtworkSize: CGFloat = 22
    static let compactGlowSize = compactArtworkSize * 1.28

    /// compactGlow diffuses the compact artwork's rounded-square silhouette in
    /// the cover's colors with concentric contours whose cumulative alpha falls
    /// smoothly to zero at the outer edge. It was a SwiftUI Canvas, and Canvas
    /// renders on the GPU: each time the compact cover appeared, on every
    /// resume, it held ~56 MB of transient graphics memory for about two
    /// seconds. Drawn once per cover into a 2× bitmap it costs a few kilobytes.
    static func compactGlow(colors: [MusicArtworkColor], scale: CGFloat = 2) -> CGImage? {
        guard let first = colors.first else { return nil }
        let pixels = Int((compactGlowSize * scale).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data            : nil,
                width           : pixels,
                height          : pixels,
                bitsPerComponent: 8,
                bytesPerRow     : 0,
                space           : space,
                bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let stops = (colors.count == 1 ? [first, first] : colors).map {
            CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
        }
        guard let gradient = CGGradient(colorsSpace: space, colors: stops as CFArray, locations: nil) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let size = compactGlowSize
        let spread = (size - compactArtworkSize) / 2
        var accumulatedAlpha: CGFloat = 0
        for index in stride(from: 31, through: 0, by: -1) {
            let progress = CGFloat(index) / 32
            let outset = spread * CGFloat(index + 1) / 32
            let alpha = 0.45 * pow(1 - progress, 2)
            let radius = compactArtworkSize * 0.2 + outset
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
                .insetBy(dx: spread - outset, dy: spread - outset)
            context.saveGState()
            context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
            // Compensate for source-over compositing so each contour reaches
            // its intended opacity instead of adding a rim.
            context.setAlpha((alpha - accumulatedAlpha) / (1 - accumulatedAlpha))
            // Top leading to bottom trailing, as the former Canvas shaded it.
            context.drawLinearGradient(
                gradient,
                start  : CGPoint(x: 0, y: size),
                end    : CGPoint(x: size, y: 0),
                options: []
            )
            context.restoreGState()
            accumulatedAlpha = alpha
        }
        return context.makeImage()
    }

    private static func palette(from bytes: [UInt8]) -> [MusicArtworkColor] {
        var groups = [ColorGroup](repeating: ColorGroup(), count: 512)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[index + 3]) / 255
            guard alpha > 0.05 else { continue }
            let red   = min(1, Double(bytes[index]) / 255 / alpha)
            let green = min(1, Double(bytes[index + 1]) / 255 / alpha)
            let blue  = min(1, Double(bytes[index + 2]) / 255 / alpha)
            let brightness = max(red, green, blue)
            let chroma = brightness - min(red, green, blue)
            let weight = alpha * (0.08 + chroma * chroma) * max(0.05, brightness)
            let bucket = min(7, Int(red * 8)) * 64 + min(7, Int(green * 8)) * 8 + min(7, Int(blue * 8))
            groups[bucket].red += red * weight
            groups[bucket].green += green * weight
            groups[bucket].blue += blue * weight
            groups[bucket].weight += weight
        }
        let ranked = groups.enumerated().filter { $0.element.weight > 0 }.sorted {
            $0.element.weight == $1.element.weight
                ? $0.offset < $1.offset
                : $0.element.weight > $1.element.weight
        }
        guard let strongest = ranked.first?.element.weight else {
            return [MusicArtworkColor(red: 0.65, green: 0.65, blue: 0.65)]
        }
        var colors: [MusicArtworkColor] = []
        for candidate in ranked where candidate.element.weight >= strongest * 0.08 {
            let color = candidate.element.color.illuminated
            guard colors.allSatisfy({ $0.distanceSquared(to: color) > 0.04 }) else { continue }
            colors.append(color)
            if colors.count == 3 { break }
        }
        return colors
    }
}
