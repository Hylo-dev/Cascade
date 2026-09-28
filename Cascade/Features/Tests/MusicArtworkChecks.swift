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
        let colorful = try decodeFixture { x in
            x < 16 ? [240, 24, 32, 255] : [24, 64, 240, 255]
        }
        require(colorful.colors.contains { $0.red > 0.7 && $0.blue < 0.3 }, "A red cover region must survive palette extraction")
        require(colorful.colors.contains { $0.blue > 0.7 && $0.red < 0.3 }, "A blue cover region must survive instead of averaging into purple")
        require((1...3).contains(colorful.colors.count), "Artwork palette must remain bounded")

        let cover = rgba(colorful.image)
        require(cover[0] > 200 && cover[2] < 60, "The decoded cover keeps its colors")

        let neutral = try decodeFixture { _ in [100, 100, 100, 255] }
        require(neutral.colors.allSatisfy { abs($0.red - $0.green) < 0.01 && abs($0.green - $0.blue) < 0.01 }, "Gray artwork must not acquire an invented tint")
        let transparent = try decodeFixture { x in
            x < 16 ? [0, 255, 0, 0] : [240, 24, 32, 255]
        }
        require(transparent.colors.allSatisfy { $0.red > $0.green }, "Transparent pixels must not color the light")
        require(MusicArtworkDecoder.decode(Data([0, 1, 2])) == nil, "Invalid artwork must fail safely")
        require(MusicArtworkDecoder.decode(Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1)) == nil, "Oversized artwork must be rejected before decoding")
        print("Music artwork palette checks passed")
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    private static func decodeFixture(_ pixel: (Int) -> [UInt8]) throws -> DecodedMusicArtwork {
        var bytes: [UInt8] = []
        for _ in 0..<32 {
            for x in 0..<32 { bytes += pixel(x) }
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
              ) else { throw CocoaError(.coderInvalidValue) }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.coderInvalidValue)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), let decoded = MusicArtworkDecoder.decode(encoded as Data) else {
            throw CocoaError(.coderInvalidValue)
        }
        return decoded
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
}
#endif
