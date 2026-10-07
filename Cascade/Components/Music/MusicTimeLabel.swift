//
//  MusicTimeLabel.swift
//  Cascade
//

import AppKit
import CascadeKit
import SwiftUI

/// MusicTimeLabel is Music's progress label: `RollingDigitsLabel` in Music's own font and
/// color, rolling only the digits that change. The rationale (and the measurement against
/// SwiftUI's `numericText`) lives with the label, in CascadeKit. `animates` is Music's own
/// reason to hold the roll, while the user scrubs.
struct MusicTimeLabel: View {

    let text      : String
    let countsDown: Bool
    let animates  : Bool

    private static let font  = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let color = NSColor.white.withAlphaComponent(0.55)

    var body: some View {
        RollingDigitsLabel(
            text      : text,
            font      : Self.font,
            color     : Self.color,
            countsDown: countsDown,
            animates  : animates
        )
    }
}
