import AppKit
import CascadeContracts
import SwiftUI

/// PluginTimerLabel schedules one visible tick per second, keeping elapsed time out of
/// PluginHost. Numeric transitions use the same layer animation as the music's time labels.
struct PluginTimerLabel: View {

    let start     : Date
    let end       : Date
    let countsDown: Bool
    let model     : PluginNodeModel

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        if Date.now >= end {
            label(at: end)
        } else {
            TimelineView(PluginTimerSchedule(start: start, end: end)) { context in
                label(at: context.date)
            }
        }
    }

    private func label(at date: Date) -> some View {
        let seconds = Int(max(0, min(end.timeIntervalSince(start), countsDown
            ? end.timeIntervalSince(date)
            : date.timeIntervalSince(start))))
        let text = String(format: "%02d:%02d", seconds / 60, seconds % 60)

        return RollingTimeLabel(
            text      : text,
            countsDown: countsDown,
            animates  : !reduceMotion,
            fontSize  : fontSize,
            color     : color
        )
        .id(fontSize)
        .id(color)
        .accessibilityLabel(text)
    }

    private var fontSize: CGFloat {
        for modifier in model.modifiers.reversed() {
            if case .font(let font) = modifier, let size = font.size { return CGFloat(size) }
        }
        return 11
    }

    private var color: NSColor {
        for modifier in model.modifiers.reversed() {
            if case .foregroundStyle(.color(let color)) = modifier {
                return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.opacity)
            }
        }
        return .white
    }
}
