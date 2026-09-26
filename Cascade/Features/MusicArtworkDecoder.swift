//
//  MusicArtworkDecoder.swift
//  Cascade
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// MusicArtworkColor keeps sampled sRGB components independent of SwiftUI.
nonisolated struct MusicArtworkColor: Equatable, Sendable {
    let red  : Double
    let green: Double
    let blue : Double

    /// illuminated raises dark colors together, preserving their hue and neutrality.
    var illuminated: Self {
        let brightness = max(red, green, blue)
        let scale = brightness > 0.02 ? max(1, 0.68 / brightness) : 1
        return Self(
            red  : min(1, red * scale),
            green: min(1, green * scale),
            blue : min(1, blue * scale)
        )
    }

    func distanceSquared(to other: Self) -> Double {
        pow(red - other.red, 2) + pow(green - other.green, 2) + pow(blue - other.blue, 2)
    }
}

/// DecodedMusicArtwork transfers an immutable CGImage and a small palette from
/// the decoder worker. No NSImage or SwiftUI objects cross that actor boundary.
nonisolated struct DecodedMusicArtwork: @unchecked Sendable {
    let image : CGImage
    let pausedImage: CGImage
    let colors: [MusicArtworkColor]
}

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
        // Bake the paused variant once on the decoder worker. Layer filters
        // are unreliable in the notch's AppKit hosting surface and would add
        // compositing work to every playback transition.
        let original = CIImage(cgImage: image)
        let paused = original.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: Double(image.width) * 0.7 / 66])
        let renderer = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        guard let pausedImage = renderer.createCGImage(paused, from: original.extent) else { return nil }
        return DecodedMusicArtwork(image: image, pausedImage: pausedImage, colors: palette(from: bytes))
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
