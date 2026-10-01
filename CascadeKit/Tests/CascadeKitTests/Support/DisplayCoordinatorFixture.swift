//
//  DisplayCoordinatorFixture.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class DisplayCoordinatorFixture {
    let inventory   : RecordingDisplayInventory
    let focus       = RecordingFocusedWindowMonitor()
    let monitor     = RecordingCoordinatorEventMonitor()
    let activityHost: LiveActivityHost
    let widgetHost   = WidgetHost()
    private(set) var surfaces: [CGDirectDisplayID: RecordingDisplaySurface] = [:]
    private(set) var surfaceCreationCount = 0
    let missingIdentity: CGDirectDisplayID?
    lazy var coordinator = NotchDisplayCoordinator(
        inventory   : inventory,
        focusMonitor: focus,
        monitor     : monitor,
        activityHost: activityHost,
        widgetHost  : widgetHost,
        preferences : DisplayPresentationPreferences(activityMode: .allDisplays),
        mainDisplay : { 10 },
        pointer     : { CGPoint(x: 50, y: 50) },
        makeSurface : { [unowned self] display in
            self.surfaceCreationCount += 1
            let surface = RecordingDisplaySurface(display: display)
            surface.acceptsCalibration = display.hasHardwareNotch
            self.surfaces[display.displayID] = surface
            return surface
        }
    )

    init(
        displayIDs     : [CGDirectDisplayID],
        missingIdentity: CGDirectDisplayID? = nil,
        now            : @escaping () -> Date = Date.init
    ) {
        self.activityHost = LiveActivityHost(now: now)
        self.missingIdentity = missingIdentity
        self.inventory = RecordingDisplayInventory(entries: displayIDs.map { displayID in
            DisplayInventoryEntry(
                snapshot: ActiveDisplay(
                    displayID   : displayID,
                    frame       : CGRect(x: CGFloat(displayID - 10) * 100, y: 0, width: 100, height: 100),
                    backingScale: 2,
                    notch       : HardwareNotch(isPresent: displayID == 10, size: CGSize(width: 40, height: 12))
                ),
                identity: displayID == missingIdentity ? nil : DisplayIdentity(rawValue: "display-\(displayID)"),
                name    : "Display \(displayID)"
            )
        })
    }

    func entry(displayID: CGDirectDisplayID) -> DisplayInventoryEntry {
        DisplayInventoryEntry(
            snapshot: ActiveDisplay(
                displayID   : displayID,
                frame       : CGRect(x: CGFloat(displayID - 10) * 100, y: 0, width: 100, height: 100),
                backingScale: 2,
                notch       : HardwareNotch(isPresent: displayID == 10, size: CGSize(width: 40, height: 12))
            ),
            identity: displayID == missingIdentity ? nil : DisplayIdentity(rawValue: "display-\(displayID)"),
            name    : "Display \(displayID)"
        )
    }
}
