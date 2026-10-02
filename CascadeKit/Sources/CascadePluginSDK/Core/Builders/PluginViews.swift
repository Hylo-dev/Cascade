//
//  PluginViews.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

// PluginViews mirrors SwiftUI's view initialisers as free functions, one for every kind of node
// the contract accepts, so a plugin's content reads like the SwiftUI it is drawn with. They are
// capitalised on purpose: `Text("Charging")` is meant to look like the view it becomes. Each
// returns a plain `PluginNode`, and nothing is checked until `PluginDocument.init`.

// MARK: - Layout

/// VStack lays its children out top to bottom.
public func VStack(
    alignment: PluginHorizontalAlignment = .center,
    spacing  : Double? = nil,
    @PluginNodeBuilder content: () -> [PluginNode]
) -> PluginNode {
    PluginNode(.vStack(alignment: alignment, spacing: spacing), children: content())
}

/// HStack lays its children out leading to trailing.
public func HStack(
    alignment: PluginVerticalAlignment = .center,
    spacing  : Double? = nil,
    @PluginNodeBuilder content: () -> [PluginNode]
) -> PluginNode {
    PluginNode(.hStack(alignment: alignment, spacing: spacing), children: content())
}

/// ZStack lays its children over each other, the first at the back.
public func ZStack(
    alignment: PluginAlignment = .center,
    @PluginNodeBuilder content: () -> [PluginNode]
) -> PluginNode {
    PluginNode(.zStack(alignment: alignment), children: content())
}

/// ViewThatFits shows the first of its children that fits along `axes`, which is how a widget
/// that cannot know its tile offers a face for every size, largest first.
public func ViewThatFits(
    in axes: PluginAxes = .both,
    @PluginNodeBuilder content: () -> [PluginNode]
) -> PluginNode {
    PluginNode(.viewThatFits(axes: axes), children: content())
}

/// Spacer takes the room its stack leaves over.
public func Spacer(minLength: Double? = nil) -> PluginNode {
    PluginNode(.spacer(minLength: minLength))
}

/// Regions is a notice's root: its children are the compact leading, the compact trailing and
/// the minimal region, in that order.
public func Regions(@PluginNodeBuilder content: () -> [PluginNode]) -> PluginNode {
    PluginNode(.regions, children: content())
}

// MARK: - Content

/// Text shows a string as it is given; the plugin localises it first.
public func Text(_ content: String) -> PluginNode {
    PluginNode(.text(content))
}

/// Image(systemName:) shows an SF Symbol.
public func Image(systemName: String) -> PluginNode {
    PluginNode(.symbol(name: systemName))
}

/// Image(asset:) shows the image asset with this id.
public func Image(asset: String) -> PluginNode {
    PluginNode(.asset(id: asset))
}

/// Circle draws a filled circle.
public func Circle() -> PluginNode {
    PluginNode(.shape(.circle))
}

/// Capsule draws a filled capsule.
public func Capsule() -> PluginNode {
    PluginNode(.shape(.capsule))
}

/// RoundedRectangle draws a filled rectangle with rounded corners.
public func RoundedRectangle(cornerRadius: Double) -> PluginNode {
    PluginNode(.shape(.roundedRectangle(cornerRadius: cornerRadius)))
}

/// Component is a tier-2 node the kernel draws natively from typed parameters. A nil parameter
/// is left out, so a measurement the plugin does not have is simply not passed.
public func Component(
    id        : String,
    version   : Int,
    parameters: [String: PluginValue?] = [:]
) -> PluginNode {
    PluginNode(.component(id: id, version: version, parameters: parameters.compactMapValues { $0 }))
}

// MARK: - Kernel-drawn time and progress

/// Clock is the current time. The kernel draws it and keeps it current, so the plugin never
/// runs to turn a minute.
public func Clock() -> PluginNode {
    PluginNode(.clock)
}

/// Today is the current weekday, day and month, kept current by the kernel like `Clock`.
public func Today() -> PluginNode {
    PluginNode(.today)
}

/// Text(_:style:) shows a fixed date in a style the kernel keeps current, as SwiftUI's does.
public func Text(
    _ date: Date,
    style : PluginDateStyle
) -> PluginNode {
    PluginNode(.date(date, style: style))
}

/// Text(timerInterval:countsDown:) is a running timer over the interval, drawn by the kernel.
public func Text(
    timerInterval: ClosedRange<Date>,
    countsDown   : Bool = true
) -> PluginNode {
    PluginNode(
        .timer(
            start     : timerInterval.lowerBound,
            end       : timerInterval.upperBound,
            countsDown: countsDown
        )
    )
}

/// ProgressView(timerInterval:) is a bar that fills over the interval, drawn by the kernel.
public func ProgressView(timerInterval: ClosedRange<Date>) -> PluginNode {
    PluginNode(.timerProgress(start: timerInterval.lowerBound, end: timerInterval.upperBound))
}

/// ProgressView(value:total:style:) is a determinate bar or ring at `value` out of `total`.
public func ProgressView(
    value: Double,
    total: Double = 1,
    style: PluginProgressStyle = .linear
) -> PluginNode {
    PluginNode(.progress(value: value, total: total, style: style))
}

// MARK: - Controls

/// Button sends `action` to the plugin when it is pressed, and shows its label.
public func Button(
    action: String,
    @PluginNodeBuilder label: () -> [PluginNode]
) -> PluginNode {
    PluginNode(.button(action: action), children: label())
}

/// Toggle shows its label in the state `isOn` and sends `action` with the new state when it is
/// flipped; the plugin answers by publishing that state.
public func Toggle(
    isOn  : Bool,
    action: String,
    @PluginNodeBuilder label: () -> [PluginNode]
) -> PluginNode {
    PluginNode(.toggle(isOn: isOn, action: action), children: label())
}

/// Slider shows `value` within `bounds`, moving by `step` when one is given, and sends `action`
/// with the value it is released at.
public func Slider(
    value    : Double,
    in bounds: ClosedRange<Double> = 0...1,
    step     : Double? = nil,
    action   : String
) -> PluginNode {
    PluginNode(
        .slider(
            value  : value,
            minimum: bounds.lowerBound,
            maximum: bounds.upperBound,
            step   : step,
            action : action
        )
    )
}
