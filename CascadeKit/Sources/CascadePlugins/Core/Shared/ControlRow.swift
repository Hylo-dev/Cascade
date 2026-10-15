//
//  ControlRow.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// controlDiameter is how wide and tall every widget button is, the 20 points macOS asks of a
/// control, on every tile that has room for one.
let controlDiameter = 20.0

/// controlRow lays a widget's buttons side by side in fixed slots, each as the notch draws a
/// control: a white glyph on a circle of dim white, so it reads as something to press on the
/// black notch. A face gives every state the same number of slots and keeps a control in the
/// same slot across the presses that change it, so a second press lands where the first did; a
/// slot with nothing to offer holds an empty space of the same size, which is not a button.
///
/// Each button is named for VoiceOver, which cannot read a glyph. The additions show their
/// minutes, "+1" and "+5", since no symbol says a minute; the others are the SF Symbols the
/// system's own media and timer controls use.
func controlRow(
    _ slots: [WidgetControl?],
    spacing: Double
) -> PluginNode {
    HStack(spacing: spacing) {

        for slot in slots {
            if let control = slot {
                Button(action: control.action) {
                    glyph(of: control)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: controlDiameter, height: controlDiameter)
                        .background {
                            Circle()
                                .foregroundStyle(.white.opacity(0.18))
                        }
                }
                .accessibilityLabel(label(of: control))
            } else {
                Spacer(minLength: 0)
                    .frame(width: controlDiameter, height: controlDiameter)
            }
        }
    }
}

/// controlRowWidth is how wide `controlRow` lays `count` slots, so a face can give the rest of a
/// row to its text as a fixed width the text shrinks into rather than spills out of.
func controlRowWidth(
    _ count: Int,
    spacing: Double
) -> Double {
    Double(count) * controlDiameter + Double(max(count - 1, 0)) * spacing
}

private func glyph(of control: WidgetControl) -> PluginNode {
    switch control {
        case .addOneMinute   : Text("+1")
        case .addFiveMinutes : Text("+5")
        case .start, .resume : Image(systemName: "play.fill")
        case .pause          : Image(systemName: "pause.fill")
        case .reset          : Image(systemName: "arrow.counterclockwise")
    }
}

private func label(of control: WidgetControl) -> String {
    switch control {
        case .addOneMinute  : String(localized: "Add one minute", table: "Plugins", bundle: .module)
        case .addFiveMinutes: String(localized: "Add five minutes", table: "Plugins", bundle: .module)
        case .start         : String(localized: "Start", table: "Plugins", bundle: .module)
        case .resume        : String(localized: "Resume", table: "Plugins", bundle: .module)
        case .pause         : String(localized: "Pause", table: "Plugins", bundle: .module)
        case .reset         : String(localized: "Reset", table: "Plugins", bundle: .module)
    }
}
