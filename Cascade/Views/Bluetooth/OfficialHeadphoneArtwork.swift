//
//  OfficialHeadphoneArtwork.swift
//  Cascade
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// OfficialHeadphoneArtwork is a small, transient rendering of Apple's
/// installed banner movie. Decoding is performed by a utility task and capped
/// at 48 frames of 96px. The renderer receives plain images; it never keeps a
/// player, decoder or repeating timer.
nonisolated struct OfficialHeadphoneArtwork: Sendable {

    let poster  : CGImage
    let frames  : [CGImage]
    let duration: TimeInterval

    enum LoadError: Error {

        case invalidImage
        case invalidMovie
    }

    static func load(
        asset        : OfficialHeadphoneAsset,
        includeMotion: Bool
    ) async throws -> Self {
        try Task.checkCancellation()

        if let movieURL = asset.movieURL {
            do {
                return try await decodeMovie(at: movieURL, includeMotion: includeMotion)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A missing codec or an OS resource change still has Apple's
                // catalog image as an accurate, static product representation.
            }
        }

        return Self(
            poster  : try decodeImage(at: asset.imageURL),
            frames  : [],
            duration: 0
        )
    }

    private static func decodeMovie(
        at url       : URL,
        includeMotion: Bool
    ) async throws -> Self {
        let asset    = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 12 else { throw LoadError.invalidMovie }
        try Task.checkCancellation()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize                    = CGSize(width: 96, height: 96)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore   = .zero
        generator.requestedTimeToleranceAfter    = CMTime(seconds: 1.0 / 60, preferredTimescale: 600)
        defer { generator.cancelAllCGImageGeneration() }

        if !includeMotion {
            let (poster, _) = try await generator.image(at: .zero)
            try Task.checkCancellation()

            return Self(
                poster  : poster,
                frames  : [],
                duration: 0
            )
        }

        let count  = 48
        let times  = (0..<count).map {
            CMTime(seconds: duration * Double($0) / Double(count), preferredTimescale: 600)
        }
        var frames = [CGImage?](repeating: nil, count: count)
        for await result in generator.images(for: times) {
            try Task.checkCancellation()

            switch result {
                case let .success(requestedTime, image, _):
                    let index = Int((requestedTime.seconds / duration * Double(count)).rounded())
                    guard frames.indices.contains(index), image.width <= 96, image.height <= 96 else {
                        throw LoadError.invalidMovie
                    }

                    frames[index] = image

                case let .failure(_, error):
                    throw error
            }
        }

        let completeFrames = frames.compactMap { $0 }
        guard completeFrames.count == count, let poster = completeFrames.first else {
            throw LoadError.invalidMovie
        }

        // The native six-second loop is sampled as one three-second turn to
        // fit the host's four-second connection notice. No repeats are added.
        return Self(
            poster  : poster,
            frames  : completeFrames,
            duration: min(3, duration)
        )
    }

    private static func decodeImage(at url: URL) throws -> CGImage {
        try Task.checkCancellation()

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize         : 96,
                  kCGImageSourceShouldCacheImmediately        : true,
                  kCGImageSourceCreateThumbnailWithTransform  : true
              ] as CFDictionary)
        else { throw LoadError.invalidImage }

        return image
    }
}
