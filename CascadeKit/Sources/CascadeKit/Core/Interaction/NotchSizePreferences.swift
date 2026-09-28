//
//  NotchSizePreferences.swift
//  CascadeKit
//

import CoreGraphics
import Foundation

/// NotchSizePreferences loads once and persists only on an explicit save.
/// UUIDs preserve a display's settings across runtime display-ID changes.
/// Identity resolution is cached; morphs and hovers never read preferences.
@MainActor
final class NotchSizePreferences: NotchSizeStoring {
    private let defaults: UserDefaults
    private let key = "notchCompactSizesByDisplayUUID"
    private let displayIdentity: (CGDirectDisplayID) -> String?
    private var savedSizes: [String: CGSize] = [:]
    private var cache: [CGDirectDisplayID: Entry] = [:]

    private struct Entry {
        let identity: String?
        var size: CGSize?
    }

    init(
        defaults: UserDefaults = .standard,
        displayIdentity: @escaping (CGDirectDisplayID) -> String? = { displayID in
            DisplayIdentityResolver.resolve(displayID: displayID)?.rawValue
        }
    ) {
        self.defaults = defaults
        self.displayIdentity = displayIdentity
        let saved = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        for (identity, values) in saved {
            guard values.count == 2,
                  values.allSatisfy({ $0.isFinite && $0 > 0 }) else { continue }
            savedSizes[identity] = CGSize(width: values[0], height: values[1])
        }
    }

    func size(for displayID: CGDirectDisplayID) -> CGSize? {
        entry(for: displayID).size
    }

    func setSize(_ size: CGSize, for displayID: CGDirectDisplayID) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let identity = entry(for: displayID).identity
        cache[displayID] = Entry(identity: identity, size: size)
        guard let identity else { return }
        savedSizes[identity] = size
        let saved = savedSizes.mapValues { [Double($0.width), Double($0.height)] }
        defaults.set(saved, forKey: key)
    }

    private func entry(for displayID: CGDirectDisplayID) -> Entry {
        if let entry = cache[displayID] { return entry }
        let identity = displayIdentity(displayID)
        let entry = Entry(identity: identity, size: identity.flatMap { savedSizes[$0] })
        cache[displayID] = entry
        return entry
    }
}
