//
//  PluginNodeKind.swift
//  CascadeKit
//

import Foundation

/// PluginNodeKind is the tier-1 vocabulary of v1 plus the tier-2 component node. Every case
/// exists because Clock, a notice or Music needs it; a node with no consumer is left out.
/// Time is drawn by the kernel: `clock` is the current time and `today` the current weekday,
/// day and month, while `date`, `timer` and `timerProgress` show the dates they are given, so
/// none of them costs the plugin anything while it ticks, which is how the clock stops waking
/// anything once a second. A `regions` node is the root of a notice's document, holding its
/// compact leading, compact trailing and minimal regions in that order. A `viewThatFits` shows the
/// first of its children that fits the space it is given, which is how a widget that comes in
/// several sizes, and cannot know which one it was given, offers a face for each.
public enum PluginNodeKind: Codable, Hashable, Sendable {

    case vStack(alignment: PluginHorizontalAlignment, spacing: Double?)
    case hStack(alignment: PluginVerticalAlignment, spacing: Double?)
    case zStack(alignment: PluginAlignment)
    case viewThatFits(axes: PluginAxes)
    case spacer(minLength: Double?)
    case text(String)
    case symbol(name: String)
    case asset(id: String)
    case shape(PluginShape)
    case date(Date, style: PluginDateStyle)
    case clock
    case today
    case timer(start: Date, end: Date, countsDown: Bool)
    case timerProgress(start: Date, end: Date)
    case progress(value: Double, total: Double, style: PluginProgressStyle)
    case button(action: String)
    case toggle(isOn: Bool, action: String)
    case slider(value: Double, minimum: Double, maximum: Double, step: Double?, action: String)
    case component(id: String, version: Int, parameters: [String: PluginValue])
    case regions

    /// name is the case's name. Structural identity includes it, so a node whose kind changes
    /// in the same slot becomes a new node, as a SwiftUI view of another type would.
    public var name: String {
        switch self {
            case .vStack       : "vStack"
            case .hStack       : "hStack"
            case .zStack       : "zStack"
            case .viewThatFits : "viewThatFits"
            case .spacer       : "spacer"
            case .text         : "text"
            case .symbol       : "symbol"
            case .asset        : "asset"
            case .shape        : "shape"
            case .date         : "date"
            case .clock        : "clock"
            case .today        : "today"
            case .timer        : "timer"
            case .timerProgress: "timerProgress"
            case .progress     : "progress"
            case .button       : "button"
            case .toggle       : "toggle"
            case .slider       : "slider"
            case .component    : "component"
            case .regions      : "regions"
        }
    }

    /// takesChildren separates containers and labelled controls from leaves.
    public var takesChildren: Bool {
        switch self {
            case .vStack, .hStack, .zStack, .viewThatFits, .button, .toggle, .regions:
                true

            default:
                false
        }
    }
}
