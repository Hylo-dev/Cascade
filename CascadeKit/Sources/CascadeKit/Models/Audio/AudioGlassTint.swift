//
//  AudioGlassTint.swift
//  CascadeKit
//

import CoreGraphics

/// AudioGlassTint is the colour a volume capsule lights the notch's glass with: the global volume
/// its own light blue, an app's capsule the colour of its icon, so Music glows pink and Brave
/// orange. It is a plain sRGB triple, compared before anything is sent to the glass.
nonisolated struct AudioGlassTint: Equatable, Sendable {

    /// volume is the icon's light blue, the global volume's light.
    static let volume = AudioGlassTint(red: 0, green: 198.0 / 255.0, blue: 234.0 / 255.0)

    /// sampleSide is the edge of the square the icon is shrunk to before it is read: 16 by 16 is
    /// 256 pixels, enough to find a dominant hue and nothing to allocate for.
    private static let sampleSide = 16

    let red  : Double
    let green: Double
    let blue : Double

    /// dominant reads the icon's characteristic colour. A plain average would come out grey: the
    /// icon's transparent corners and its white or black ground outweigh the colour that names
    /// it. So each pixel weighs by its opacity and its saturation, and the result is lifted to
    /// a bright, saturated light, since the glass smokes whatever is under it. Nil for an image
    /// with nothing coloured in it, which then keeps the default light.
    ///
    /// It draws into a 1 KiB bitmap and reads it once; it touches no view and runs on the icon
    /// cache's utility task, never on the main actor.
    static func dominant(in image: CGImage) -> AudioGlassTint? {
        let side   = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let space   = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data            : buffer.baseAddress,
                    width           : side,
                    height          : side,
                    bitsPerComponent: 8,
                    bytesPerRow     : side * 4,
                    space           : space,
                    bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var red    = 0.0
        var green  = 0.0
        var blue   = 0.0
        var weight = 0.0

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.1 else { continue }

            // Premultiplied: divide the alpha back out to read the colour itself.
            let r = Double(pixels[index])     / 255 / alpha
            let g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha

            let high       = Swift.max(r, g, b)
            let low        = Swift.min(r, g, b)
            let saturation = high > 0 ? (high - low) / high : 0
            let share      = alpha * saturation * saturation

            red    += r * share
            green  += g * share
            blue   += b * share
            weight += share
        }
        guard weight > 0.5 else { return nil }

        return AudioGlassTint(
            red  : red / weight,
            green: green / weight,
            blue : blue / weight
        )
        .lifted()
    }

    /// lifted brings the colour to full brightness and keeps it saturated, so a dark or muted
    /// icon still gives a light that shows through the smoked glass.
    func lifted() -> AudioGlassTint {
        let high = Swift.max(red, green, blue)
        guard high > 0 else { return self }

        let scale = 1 / high
        return AudioGlassTint(
            red  : Swift.min(1, red * scale),
            green: Swift.min(1, green * scale),
            blue : Swift.min(1, blue * scale)
        )
    }
}
