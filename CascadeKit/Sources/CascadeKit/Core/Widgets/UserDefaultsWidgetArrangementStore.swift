//
//  UserDefaultsWidgetArrangementStore.swift
//  CascadeKit
//

import Foundation

/// UserDefaultsWidgetArrangementStore keeps the edited arrangements in one UserDefaults payload,
/// keyed by the display's UUID, so a display finds its page again after a reboot or a reconnect.
///
/// Every read and write runs on one serial utility queue: the encoding and the defaults write
/// stay off the main thread, and a load issued after a save always sees it. The payload is a
/// JSON dictionary of display UUID to widget id to placement. A payload that does not decode,
/// damaged or from a future version, reads as nothing, so the displays fall back to the default
/// arrangement instead of failing.
///
/// It is `@unchecked Sendable` because its only state is immutable and `UserDefaults`, which
/// the SDK does not mark Sendable, is documented as safe to use from any thread.
nonisolated final class UserDefaultsWidgetArrangementStore: WidgetArrangementStoring, @unchecked Sendable {

    static let defaultsKey = "widgetArrangementsByDisplayUUIDV1"

    private let defaults: UserDefaults
    private let queue    = DispatchQueue(label: "hylo.Cascade.WidgetArrangements", qos: .utility)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() async -> [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: read()) }
        }
    }

    func save(_ arrangements: [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]]) {
        queue.async { [self] in write(arrangements) }
    }

    private func read() -> [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]] {
        guard let payload = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String: WidgetPlacement]].self, from: payload)
        else { return [:] }

        var arrangements: [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]] = [:]
        for (display, placements) in decoded {
            arrangements[DisplayIdentity(rawValue: display)] = Dictionary(
                uniqueKeysWithValues: placements.map { (WidgetIdentifier($0.key), $0.value) }
            )
        }

        return arrangements
    }

    private func write(_ arrangements: [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]]) {
        var encoded: [String: [String: WidgetPlacement]] = [:]
        for (display, placements) in arrangements {
            encoded[display.rawValue] = Dictionary(
                uniqueKeysWithValues: placements.map { ($0.key.rawValue, $0.value) }
            )
        }

        guard let payload = try? JSONEncoder().encode(encoded) else { return }

        defaults.set(payload, forKey: Self.defaultsKey)
    }
}
