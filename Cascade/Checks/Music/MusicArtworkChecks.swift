//
//  MusicArtworkChecks.swift
//  Cascade
//

#if MUSIC_ARTWORK_TESTS
import CoreGraphics
import Foundation
import ImageIO

@main
private enum MusicArtworkChecks {

    static func main() throws {
        let colorful = try decodeFixture { column in
            column < 16 ? [240, 24, 32, 255] : [24, 64, 240, 255]
        }
        require(
            colorful.colors.contains { $0.red > 0.7 && $0.blue < 0.3 },
            "A red cover region must survive palette extraction"
        )
        require(
            colorful.colors.contains { $0.blue > 0.7 && $0.red < 0.3 },
            "A blue cover region must survive instead of averaging into purple"
        )
        require((1...3).contains(colorful.colors.count), "Artwork palette must remain bounded")

        let cover = rgba(colorful.image)
        require(cover[0] > 200 && cover[2] < 60, "The decoded cover keeps its colors")

        let glow = try require2(colorful.glow, "A decoded cover carries its compact glow")
        require(
            glow.width == Int((MusicArtworkDecoder.compactGlowSize * 2).rounded(.up)) && glow.width == glow.height,
            "The glow is a 2x square around the compact cover"
        )

        let halo = rgba(glow)
        func alpha(
            _ column: Int,
            _ row   : Int
        ) -> UInt8 {
            halo[(row * glow.width + column) * 4 + 3]
        }
        require(alpha(0, 0) == 0, "The glow fades to nothing at its corners")
        require(alpha(glow.width / 2, glow.width / 2) > 80, "It is strongest under the cover")
        require(
            alpha(glow.width / 2, 2) > 0 && alpha(glow.width / 2, 2) < alpha(glow.width / 2, glow.width / 2),
            "and falls off toward its edge"
        )
        require(MusicArtworkDecoder.compactGlow(colors: []) == nil, "No colors, no glow")

        let neutral = try decodeFixture { _ in [100, 100, 100, 255] }
        require(
            neutral.colors.allSatisfy { abs($0.red - $0.green) < 0.01 && abs($0.green - $0.blue) < 0.01 },
            "Gray artwork must not acquire an invented tint"
        )

        let transparent = try decodeFixture { column in
            column < 16 ? [0, 255, 0, 0] : [240, 24, 32, 255]
        }
        require(
            transparent.colors.allSatisfy { $0.red > $0.green },
            "Transparent pixels must not color the light"
        )
        require(
            MusicArtworkDecoder.decode(Data([0, 1, 2])) == nil,
            "Invalid artwork must fail safely"
        )
        require(
            MusicArtworkDecoder.decode(Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1)) == nil,
            "Oversized artwork must be rejected before decoding"
        )

        print("Music artwork palette checks passed")
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data            : buffer.baseAddress,
                width           : image.width,
                height          : image.height,
                bitsPerComponent: 8,
                bytesPerRow     : image.width * 4,
                space           : CGColorSpaceCreateDeviceRGB(),
                bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        return bytes
    }

    private static func decodeFixture(_ pixel: (Int) -> [UInt8]) throws -> DecodedMusicArtwork {
        var bytes: [UInt8] = []
        for _ in 0..<32 {
            for column in 0..<32 { bytes += pixel(column) }
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width            : 32,
                  height           : 32,
                  bitsPerComponent : 8,
                  bitsPerPixel     : 32,
                  bytesPerRow      : 128,
                  space            : CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo       : CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider         : provider,
                  decode           : nil,
                  shouldInterpolate: false,
                  intent           : .defaultIntent
              )
        else { throw CocoaError(.coderInvalidValue) }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.coderInvalidValue)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination),
              let decoded = MusicArtworkDecoder.decode(encoded as Data)
        else {
            throw CocoaError(.coderInvalidValue)
        }

        return decoded
    }

    private static func require2<T>(
        _ value  : T?,
        _ message: String
    ) throws -> T {
        guard let value else { fatalError(message) }

        return value
    }

    private static func require(
        _ condition: Bool,
        _ message  : String
    ) {
        guard condition else { fatalError(message) }
    }
}

#endif
