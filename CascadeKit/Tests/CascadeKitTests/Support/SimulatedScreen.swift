//
//  SimulatedScreen.swift
//  CascadeKit
//

@testable import CascadeKit

/// SimulatedScreen is the display a controller test pretends Cascade sits on. The fixture
/// and the driver share it, so a test can move the notch to another screen by replacing
/// `display` and sending the monitor's display-change event.
@MainActor
final class SimulatedScreen {

    var display: ActiveDisplay

    init(display: ActiveDisplay) {
        self.display = display
    }
}
