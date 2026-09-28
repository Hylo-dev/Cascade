//
//  OfficialHeadphoneAsset.swift
//  Cascade
//

import Foundation

/// Describes Apple-owned files on this Mac. These URLs are read at runtime;
/// their contents are never copied into Cascade's bundle or a disk cache.
nonisolated struct OfficialHeadphoneAsset: Sendable, Equatable {
    let imageURL: URL
    let movieURL: URL?
}
