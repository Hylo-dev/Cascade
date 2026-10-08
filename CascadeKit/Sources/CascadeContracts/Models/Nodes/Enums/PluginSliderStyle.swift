//
//  PluginSliderStyle.swift
//  CascadeKit
//

/// PluginSliderStyle is how a `slider` node is drawn. `standard` is the system slider. `ruler`
/// is a row of ticks, one per `step`, that scrolls under a fixed indicator while it is dragged,
/// as the iOS timer's does: the kernel draws it in one `Canvas`, takes the drag itself, snaps to
/// `step` on release and sends one action then, so the plugin never wakes during a drag. A label
/// is written every `labelEvery` ticks, in the form `labels` names. A ruler needs a `step`: it
/// is what a tick stands for.
public enum PluginSliderStyle: Codable, Hashable, Sendable {

    case standard
    case ruler(labelEvery: Int, labels: PluginRulerLabels)

    /// maximumLabelCadence and maximumRulerTicks bound what a document can ask the kernel to
    /// lay out: a label every 96 ticks is a day of quarter hours, and 2,048 ticks is more than
    /// any ruler Cascade ships needs, so a hostile step cannot make the drawing loop wide.
    public static let maximumLabelCadence = 96
    public static let maximumRulerTicks   = 2_048
}

/// PluginRulerLabels is what a ruler's labels say. With `duration` the slider's value is a
/// number of minutes and a label reads `1h` or `1h 30m`. With `clockTime` the value is seconds
/// since 1970 and a label is that instant's local time.
public enum PluginRulerLabels: String, Codable, Hashable, Sendable {

    case duration
    case clockTime
}
