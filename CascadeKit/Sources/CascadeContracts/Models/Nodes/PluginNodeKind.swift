//
//  PluginNodeKind.swift
//  CascadeKit
//

import Foundation

/// PluginNodeKind is the tier-1 vocabulary of v1 plus the tier-2 component node. Every case
/// exists because Clock, a notice or Music needs it; a node with no consumer is left out.
/// Time is drawn by the kernel: `clock` is the current time and `today` the current weekday,
/// day and month, while `date`, `timer`, `timerProgress` and `countdown` show the dates they are
/// given, so none of them costs the plugin anything while it ticks, which is how the clock stops waking
/// anything once a second. A `regions` node is the root of a notice's document, holding its
/// compact leading, compact trailing and minimal regions in that order. A `viewThatFits` shows the
/// first of its children that fits the space it is given, which is how a widget that comes in
/// several sizes, and cannot know which one it was given, offers a face for each. A slider's
/// `style` is `standard` unless the document says otherwise, on the wire as in code: a slider
/// written before styles existed has no `style` and decodes as `standard`.
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
    case countdown(end: Date, style: PluginCountdownStyle)
    case progress(value: Double, total: Double, style: PluginProgressStyle)
    case button(action: String)
    case toggle(isOn: Bool, action: String)
    case slider(value: Double, minimum: Double, maximum: Double, step: Double?, style: PluginSliderStyle = .standard, action: String)
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
            case .countdown    : "countdown"
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

extension PluginNodeKind {

    /// init(from:) reads the synthesized wire form, with one difference: a slider with no
    /// `style` is a standard slider. Swift's synthesis fails on a missing key, even when the case
    /// has a default value, so the document is decoded as `Wire`, a mirror of the vocabulary in
    /// which the style is optional, and mapped back. `encode(to:)` stays synthesized, so the wire
    /// form is the one the mirror reads, plus the style. Keep the two enums in step: a case
    /// added to one and not to the other fails to compile in `kind`.
    public init(from decoder: any Decoder) throws {
        self = try Wire(from: decoder).kind
    }

    private enum Wire: Decodable {

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
        case countdown(end: Date, style: PluginCountdownStyle)
        case progress(value: Double, total: Double, style: PluginProgressStyle)
        case button(action: String)
        case toggle(isOn: Bool, action: String)
        case slider(value: Double, minimum: Double, maximum: Double, step: Double?, style: PluginSliderStyle?, action: String)
        case component(id: String, version: Int, parameters: [String: PluginValue])
        case regions

        var kind: PluginNodeKind {
            switch self {
                case .vStack(let alignment, let spacing)                        : .vStack(alignment: alignment, spacing: spacing)
                case .hStack(let alignment, let spacing)                        : .hStack(alignment: alignment, spacing: spacing)
                case .zStack(let alignment)                                     : .zStack(alignment: alignment)
                case .viewThatFits(let axes)                                    : .viewThatFits(axes: axes)
                case .spacer(let minLength)                                     : .spacer(minLength: minLength)
                case .text(let text)                                            : .text(text)
                case .symbol(let name)                                          : .symbol(name: name)
                case .asset(let id)                                             : .asset(id: id)
                case .shape(let shape)                                          : .shape(shape)
                case .date(let date, let style)                                 : .date(date, style: style)
                case .clock                                                     : .clock
                case .today                                                     : .today
                case .timer(let start, let end, let countsDown)                 : .timer(start: start, end: end, countsDown: countsDown)
                case .timerProgress(let start, let end)                         : .timerProgress(start: start, end: end)
                case .countdown(let end, let style)                             : .countdown(end: end, style: style)
                case .progress(let value, let total, let style)                 : .progress(value: value, total: total, style: style)
                case .button(let action)                                        : .button(action: action)
                case .toggle(let isOn, let action)                              : .toggle(isOn: isOn, action: action)
                case .slider(let value, let minimum, let maximum, let step, let style, let action):
                    .slider(value: value, minimum: minimum, maximum: maximum, step: step, style: style ?? .standard, action: action)
                case .component(let id, let version, let parameters)            : .component(id: id, version: version, parameters: parameters)
                case .regions                                                   : .regions
            }
        }
    }
}
