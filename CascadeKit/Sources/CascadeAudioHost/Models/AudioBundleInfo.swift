//
//  AudioBundleInfo.swift
//  CascadeKit
//

/// AudioBundleInfo is what AudioHost reads from an app bundle on disk: the bundle identifier
/// that names the app and the name the user sees for it. It is a plain value so the lookup that
/// produces it can be replaced in tests, which have no real bundles to read.
public struct AudioBundleInfo: Equatable, Sendable {

    public let bundleID    : String
    public let displayName : String

    public init(
        bundleID    : String,
        displayName : String
    ) {
        self.bundleID    = bundleID
        self.displayName = displayName
    }
}
