//
//  ControlRow.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// controlRow lays a widget's buttons side by side, each as the notch draws a control: a white
/// glyph on a circle of dim white, `diameter` points across, so it reads as something to press
/// on the black notch at every tile size. Each is named for VoiceOver, which cannot read a
/// glyph. The additions show their minutes, "+1" and "+5", since no symbol says a minute; the
/// others are the SF Symbols the system's own media and timer controls use.
func controlRow(
    _ controls: [WidgetControl],
    diameter  : Double,
    spacing   : Double
) -> PluginNode {
    HStack(spacing: spacing) {

        for control in controls {
            Button(action: control.rawValue) {
                glyph(of: control)
                    .font(.system(size: diameter * 0.47, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: diameter, height: diameter)
                    .background {
                        Circle()
                            .foregroundStyle(.white.opacity(0.18))
                    }
            }
            .accessibilityLabel(label(of: control))
        }
    }
}

/// controlRowWidth is how wide `controlRow` lays `count` buttons, so a face can give the rest of
/// a row to its text as a fixed width the text shrinks into rather than spills out of.
func controlRowWidth(
    _ count : Int,
    diameter: Double,
    spacing : Double
) -> Double {
    Double(count) * diameter + Double(max(count - 1, 0)) * spacing
}

private func glyph(of control: WidgetControl) -> PluginNode {
    switch control {
        case .addOneMinute  : Text("+1")
        case .addFiveMinutes: Text("+5")
        case .start         : Image(systemName: "play.fill")
        case .pause         : Image(systemName: "pause.fill")
        case .reset         : Image(systemName: "arrow.counterclockwise")
    }
}

private func label(of control: WidgetControl) -> String {
    switch control {
        case .addOneMinute  : String(localized: "Add one minute", table: "Plugins", bundle: .module)
        case .addFiveMinutes: String(localized: "Add five minutes", table: "Plugins", bundle: .module)
        case .start         : String(localized: "Start", table: "Plugins", bundle: .module)
        case .pause         : String(localized: "Pause", table: "Plugins", bundle: .module)
        case .reset         : String(localized: "Reset", table: "Plugins", bundle: .module)
    }
}
