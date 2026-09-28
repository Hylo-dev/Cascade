//
//  NotchWidget.swift
//  CascadeKit
//

import SwiftUI

/// NotchWidget is the contract every widget conforms to.
///
/// A widget knows nothing about the engine: it is registered, placed on the grid
/// by id, and driven through this protocol and the `WidgetContext` it is handed.
/// Because the overlay is always on screen, the contract is strict about
/// resources (see CODE_STYLE) — `activate`/`suspend` bracket the widget's
/// lifetime so a hidden widget holds nothing, and `makeContentView` is called
/// rarely (on activation and on a declared change), never on a timer.
@MainActor
public protocol NotchWidget: AnyObject {

    /// Unique identity of this widget *instance*. The workspace keys it by this,
    /// and a screen's arrangement references it by this — so one instance can
    /// appear on several screens without being duplicated.
    var id: WidgetIdentifier { get }

    /// The widget *type*. Persistence stores this and a factory recreates the
    /// widget from it on load (many instances may share one kind).
    static var kind: WidgetKind { get }

    /// Footprint on the grid (`1×1`, `1×n`, `2×n`).
    var size: GridSpan { get }

    /// Build the SwiftUI content shown in the widget's cell.
    func makeContentView() -> AnyView

    /// Called when the widget becomes visible. Acquire resources and subscribe
    /// here; the context is valid until the matching `suspend()`.
    func activate(in context: WidgetContext)

    /// Called when the widget hides. Release images, cancel subscriptions, free
    /// buffers — after this the widget must consume no CPU and minimal RAM.
    func suspend()
}

public extension NotchWidget {

    // Most widgets hold no resources beyond their view, so the lifecycle hooks
    // are optional: the default pair does nothing.
    func activate(in context: WidgetContext) {}

    func suspend() {}
}
