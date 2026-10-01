//
//  ActivityDisplayRoutingTests.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

@MainActor
struct ActivityDisplayRoutingTests {

    private let displayA = DisplayIdentity(rawValue: "display-a")
    private let displayB = DisplayIdentity(rawValue: "display-b")

    @Test
    func fixedDisplayDoesNotFallBackWhenDisconnected() {
        #expect(ActivityDisplayRouting.destinations(
            mode     : .fixedDisplay(displayA),
            connected: [displayB],
            focused  : displayB
        ).isEmpty)
        #expect(ActivityDisplayRouting.destinations(
            mode     : .fixedDisplay(displayA),
            connected: [displayA, displayB],
            focused  : displayB
        ) == [displayA])
    }

    @Test
    func allDisplaysReturnsEveryConnectedDisplay() {
        #expect(ActivityDisplayRouting.destinations(
            mode     : .allDisplays,
            connected: [displayA, displayB],
            focused  : nil
        ) == [displayA, displayB])
    }

    @Test
    func focusedDisplayRequiresAConnectedFocus() {
        #expect(ActivityDisplayRouting.destinations(
            mode     : .focusedDisplay,
            connected: [displayA, displayB],
            focused  : displayB
        ) == [displayB])
        #expect(ActivityDisplayRouting.destinations(
            mode     : .focusedDisplay,
            connected: [displayA],
            focused  : displayB
        ).isEmpty)
        #expect(ActivityDisplayRouting.destinations(
            mode     : .focusedDisplay,
            connected: [],
            focused  : nil
        ).isEmpty)
    }

    @Test
    func preferencesRoundTripWithAnOfflineFixedDisplay() throws {
        let preferences = DisplayPresentationPreferences(
            activityMode: .fixedDisplay(displayA),
            styles      : [displayA: .dynamicIsland]
        )
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(DisplayPresentationPreferences.self, from: encoded)

        #expect(decoded == preferences)
        #expect(decoded.style(for: displayA) == .dynamicIsland)
        #expect(decoded.style(for: displayB) == .notch)
    }

    @Test
    func preferenceStoreUsesOnePayloadAndFallsBackFromCorruptData() throws {
        let suite    = "Cascade.ActivityDisplayRoutingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(
            Data("not-json".utf8),
            forKey: "displayPresentationPreferencesV1"
        )
        let corrupted = DisplayPresentationPreferencesStore(defaults: defaults)
        #expect(corrupted.preferences == DisplayPresentationPreferences())

        defaults.set(
            Data(#"{"activityMode":{"futureMode":{}},"styles":[]}"#.utf8),
            forKey: "displayPresentationPreferencesV1"
        )
        let unknown = DisplayPresentationPreferencesStore(defaults: defaults)
        #expect(unknown.preferences.activityMode == .focusedDisplay)

        let offline = DisplayPresentationPreferences(
            activityMode: .fixedDisplay(displayA),
            styles      : [displayA: .dynamicIsland]
        )
        corrupted.preferences = offline

        let restored = DisplayPresentationPreferencesStore(defaults: defaults)
        #expect(restored.preferences == offline)
        #expect(defaults.object(forKey: "displayPresentationPreferencesV1") is Data)
    }

    @Test
    func inventoryKeepsStableIdentityWhenTheRuntimeIDChanges() {
        var runtimeID  : CGDirectDisplayID = 7
        let identity    = DisplayIdentity(rawValue: "stable-uuid")
        var resolvedIDs: [CGDirectDisplayID] = []
        let inventory   = DisplayInventory(
            screens         : {
                [Self.screen(
                    displayID: runtimeID,
                    name     : "Studio Display"
                )]
            },
            identityResolver: { displayID in
                resolvedIDs.append(displayID)
                return displayID == 7 || displayID == 42 ? identity : nil
            },
            mirrorResolver  : { _ in kCGNullDirectDisplay }
        )

        inventory.start()
        #expect(inventory.displays.map(\.identity) == [identity])
        #expect(inventory.displays.map(\.snapshot.displayID) == [7])

        runtimeID = 42
        inventory.refresh()
        #expect(inventory.displays.map(\.identity) == [identity])
        #expect(inventory.displays.map(\.snapshot.displayID) == [42])
        #expect(resolvedIDs == [7, 42])

        inventory.stop()
    }

    @Test
    func inventoryCoalescesMirrorsUsingTheFirstAppKitRepresentative() {
        let mirroredIdentity = DisplayIdentity(rawValue: "mirrored-uuid")
        let primaryIdentity  = DisplayIdentity(rawValue: "primary-uuid")
        let inventory        = DisplayInventory(
            screens         : {
                [
                    Self.screen(
                        displayID: 11,
                        name     : "AppKit representative",
                        frame    : CGRect(x: 0, y: 0, width: 1280, height: 720)
                    ),
                    Self.screen(
                        displayID: 10,
                        name     : "Larger mirror member",
                        frame    : CGRect(x: 0, y: 0, width: 2560, height: 1440)
                    ),
                ]
            },
            identityResolver: { displayID in
                displayID == 11 ? mirroredIdentity : primaryIdentity
            },
            mirrorResolver  : { displayID in
                displayID == 11 ? 10 : kCGNullDirectDisplay
            }
        )

        inventory.start()
        #expect(inventory.displays.count == 1)
        #expect(inventory.displays[0].snapshot.displayID == 11)
        #expect(inventory.displays[0].identity == mirroredIdentity)
        #expect(inventory.displays[0].name == "AppKit representative")

        inventory.stop()
    }

    @Test
    func inventoryLeavesFailedIdentityLookupsUnresolved() {
        let inventory = DisplayInventory(
            screens         : {
                [Self.screen(
                    displayID: 8,
                    name     : "Session only"
                )]
            },
            identityResolver: { _ in nil },
            mirrorResolver  : { _ in kCGNullDirectDisplay }
        )

        inventory.start()
        #expect(inventory.displays.count == 1)
        #expect(inventory.displays[0].identity == nil)

        inventory.stop()
    }

    @Test
    func inventoryPublishesOnlyMaterialDisplayChangesWithoutMergingPeers() {
        var screens = [
            Self.screen(
                displayID: 7,
                name     : "Identical display"
            ),
            Self.screen(
                displayID: 8,
                name     : "Identical display"
            ),
        ]
        let inventory = DisplayInventory(
            screens         : { screens },
            identityResolver: { displayID in
                displayID == 7 ? displayA : nil
            },
            mirrorResolver  : { _ in kCGNullDirectDisplay }
        )
        var changes        = 0
        inventory.onChange = { changes += 1 }

        inventory.start()
        #expect(inventory.displays.count == 2)
        #expect(inventory.displays.first(where: { $0.snapshot.displayID == 8 })?.identity == nil)
        #expect(changes == 1)

        screens[0] = Self.screen(
            displayID: 7,
            name     : "Renamed"
        )
        inventory.refresh()
        #expect(inventory.displays.first(where: { $0.snapshot.displayID == 7 })?.name == "Renamed")
        #expect(changes == 1)

        screens[0] = Self.screen(
            displayID: 7,
            name     : "Renamed",
            frame    : CGRect(x: 0, y: 0, width: 1600, height: 900)
        )
        inventory.refresh()
        #expect(changes == 2)

        inventory.stop()
    }

    private static func screen(
        displayID: CGDirectDisplayID,
        name     : String,
        frame    : CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
    ) -> DisplayInventoryScreen {
        DisplayInventoryScreen(
            snapshot: ActiveDisplay(
                displayID   : displayID,
                frame       : frame,
                backingScale: 2,
                notch       : .absent
            ),
            name    : name
        )
    }
}
