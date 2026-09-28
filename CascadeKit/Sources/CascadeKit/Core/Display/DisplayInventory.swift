//
//  DisplayInventory.swift
//  CascadeKit
//

import AppKit
import ColorSync

/// DisplayInventory observes AppKit's screen-parameter notification and emits
/// only changes that affect surface topology, geometry, scale or notch metrics.
///
/// CoreGraphics supplies explicit mirror relationships because AppKit may list
/// more than one physical member. The first member in AppKit's screen order is
/// the deterministic representative for that logical surface; geometry and
/// names never participate in grouping, so independent identical displays stay
/// independent.
@MainActor
final class DisplayInventory: NSObject, DisplayInventoryProviding {
    private(set) var displays: [DisplayInventoryEntry] = []
    var onChange: (() -> Void)?

    private let notificationCenter: NotificationCenter
    private let screens            : @MainActor () -> [DisplayInventoryScreen]
    private let identityResolver   : (CGDirectDisplayID) -> DisplayIdentity?
    private let mirrorResolver     : (CGDirectDisplayID) -> CGDirectDisplayID
    private var isStarted          = false

    init(
        notificationCenter: NotificationCenter = .default,
        screens           : @escaping @MainActor () -> [DisplayInventoryScreen] = {
            NSScreen.screens.map { screen in
                DisplayInventoryScreen(
                    snapshot: screen.activeDisplaySnapshot(),
                    name    : screen.localizedName
                )
            }
        },
        identityResolver: @escaping (CGDirectDisplayID) -> DisplayIdentity? = {
            DisplayIdentityResolver.resolve(displayID: $0)
        },
        mirrorResolver: @escaping (CGDirectDisplayID) -> CGDirectDisplayID = {
            CGDisplayMirrorsDisplay($0)
        }
    ) {
        self.notificationCenter = notificationCenter
        self.screens            = screens
        self.identityResolver   = identityResolver
        self.mirrorResolver     = mirrorResolver
        super.init()
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        refresh()
        notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name    : NSApplication.didChangeScreenParametersNotification,
            object  : nil
        )
    }

    func stop() {
        guard isStarted else {
            return
        }

        notificationCenter.removeObserver(self)
        isStarted = false
    }

    /// refresh rebuilds metadata but calls observers only when presentation
    /// surfaces need reconciliation. A localized-name change alone updates the
    /// exposed inventory without waking the display coordinator.
    func refresh() {
        var representatives: [CGDirectDisplayID: DisplayInventoryScreen] = [:]
        for screen in screens() {
            let logicalDisplayID = canonicalMirrorID(for: screen.snapshot.displayID)
            if representatives[logicalDisplayID] == nil {
                representatives[logicalDisplayID] = screen
            }
        }

        let refreshed = representatives.values.map { screen in
            DisplayInventoryEntry(
                snapshot: screen.snapshot,
                identity: identityResolver(screen.snapshot.displayID),
                name    : screen.name
            )
        }.sorted {
            $0.snapshot.displayID < $1.snapshot.displayID
        }
        let topologyChanged = !Self.hasSamePresentationTopology(displays, refreshed)

        displays = refreshed
        if topologyChanged {
            onChange?()
        }
    }

    @objc
    private func screenParametersDidChange() {
        refresh()
    }

    /// canonicalMirrorID follows CoreGraphics mirror links to the logical root.
    /// A defensive cycle fallback uses the smallest visited numeric ID, keeping
    /// corrupt or transient topology deterministic without merging unrelated
    /// displays by presentation metadata.
    private func canonicalMirrorID(for displayID: CGDirectDisplayID) -> CGDirectDisplayID {
        var current = displayID
        var visited: Set<CGDirectDisplayID> = []

        while visited.insert(current).inserted {
            let mirroredDisplayID = mirrorResolver(current)
            guard mirroredDisplayID != kCGNullDirectDisplay,
                  mirroredDisplayID != current else {
                return current
            }
            current = mirroredDisplayID
        }

        return visited.min() ?? displayID
    }

    private static func hasSamePresentationTopology(
        _ lhs: [DisplayInventoryEntry],
        _ rhs: [DisplayInventoryEntry]
    ) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        return zip(lhs, rhs).allSatisfy { previous, current in
            previous.snapshot == current.snapshot && previous.identity == current.identity
        }
    }
}
