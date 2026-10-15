//
//  AudioAppIconCache.swift
//  CascadeKit
//

import AppKit
import Observation

/// AudioAppIconCache gives the app columns their icons, and the colour each icon lights the
/// notch's glass with (`AudioGlassTint`), read from the image on the same utility task that
/// loads it. Resolving a bundle identifier to an
/// application and reading its icon touches Launch Services and the disk, so it never runs on the
/// main actor: `load` hands it to a utility task, once per bundle identifier, and publishes the
/// finished image back on the main actor. Until it arrives, and for an app that cannot be found,
/// `icon(for:)` answers nil and the column draws a placeholder.
///
/// Asking twice is free, whether the first answer is in flight or done, so a column can call
/// `load` every time it appears. The cache lives as long as the mixer page does; the images are
/// not kept after it closes, which keeps the notch's footprint where it was.
///
/// The loader is injected, and the default asks `NSWorkspace`. The image crosses from the utility
/// task to the main actor as the loader's result, and nothing keeps a reference to it on the
/// other side, which is the transfer Swift's region analysis allows.
@MainActor
@Observable
final class AudioAppIconCache {

    typealias Loader = @Sendable (String) -> sending NSImage?

    @ObservationIgnored
    private let loader: Loader

    @ObservationIgnored
    private var requested: Set<String> = []

    private var images: [String: NSImage] = [:]

    private var tints: [String: AudioGlassTint] = [:]

    init(
        loader: @escaping Loader = { bundleID in
            AudioAppIconCache.workspaceIcon(for: bundleID)
        }
    ) {
        self.loader = loader
    }

    /// icon is the image for the app, or nil while it loads or when none exists. Reading it
    /// starts nothing: loading is `load`'s business, so a body stays free of side effects.
    func icon(for bundleID: String) -> NSImage? {
        images[bundleID]
    }

    /// tint is the colour the app's capsule lights the glass with: its icon's, or the volume's
    /// own light blue while the icon loads, when it has no colour, or when there is no icon.
    func tint(for bundleID: String) -> AudioGlassTint {
        tints[bundleID] ?? .volume
    }

    /// load resolves the app's icon off the main actor, the first time it is asked for it.
    func load(_ bundleID: String) async {
        guard requested.insert(bundleID).inserted else { return }

        let loader = loader
        let loaded = await Task.detached(priority: .utility) { () -> sending LoadedIcon in
            let image = loader(bundleID)
            let tint  = image
                .flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                .flatMap(AudioGlassTint.dominant(in:))

            return LoadedIcon(image: image, tint: tint)
        }.value

        if let image = loaded.image {
            images[bundleID] = image
        }
        if let tint = loaded.tint {
            tints[bundleID] = tint
        }
    }

    /// LoadedIcon is what the utility task hands back: the image and the colour read from it.
    private struct LoadedIcon {

        let image: NSImage?
        let tint : AudioGlassTint?
    }

    /// workspaceIcon is the real loader: the icon of the application the system associates with
    /// the bundle identifier, or nil when it is not installed.
    nonisolated static func workspaceIcon(for bundleID: String) -> sending NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
