//
//  ScriptableMusicArtwork.swift
//  Cascade
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ScriptableMusicArtwork limits both encoded input and decoded pixel storage.
/// It runs on the reader actor, so network IO and decompression never occupy
/// the main actor. Only the current artwork of each supported player is cached.
nonisolated enum ScriptableMusicArtwork {

    static let maximumInputBytes = 4 * 1_024 * 1_024

    static func thumbnail(_ data: Data) -> Data? {
        guard !data.isEmpty,
              data.count <= maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0,
              width <= 4_096,
              height <= 4_096
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform  : true,
            kCGImageSourceThumbnailMaxPixelSize         : 512,
            kCGImageSourceShouldCacheImmediately        : true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination),
              encoded.length <= 1_024 * 1_024
        else { return nil }

        return encoded as Data
    }

    /// spotifyArtwork accepts only Spotify's image CDNs, with an in-memory
    /// transfer cap and request deadline. Arbitrary file and network URLs in
    /// a player's metadata cannot become filesystem reads or unbounded loads.
    static func spotifyArtwork(_ value: String) async throws -> Data? {
        guard let url = URL(string: value), permits(url) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.cachePolicy     = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest  = 4
        configuration.timeoutIntervalForResource = 4
        configuration.urlCache                   = nil
        configuration.httpCookieStorage          = nil

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let finalURL = response.url,
              permits(finalURL),
              response.expectedContentLength <= maximumInputBytes,
              response.mimeType?.hasPrefix("image/") == true
        else { return nil }

        var data = Data()
        data.reserveCapacity(min(maximumInputBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumInputBytes else { return nil }

            data.append(byte)
        }

        return thumbnail(data)
    }

    static func permits(_ url: URL) -> Bool {
        guard url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased()
        else { return false }

        return host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com") || host.hasSuffix(".spotifycdn.net")
    }
}
