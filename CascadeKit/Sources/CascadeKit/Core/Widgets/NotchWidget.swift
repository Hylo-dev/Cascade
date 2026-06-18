//
//  NotchWidget.swift
//  CascadeKit
//

import SwiftUI

/// NotchWidget is the contract every widget conforms to.
///
/// A widget knows nothing about the engine: it is registered, placed in a
/// region, and driven entirely through this protocol and the `WidgetContext` it
/// is handed. Because the overlay is always on screen, the contract is strict
/// about resources (see CODE_STYLE) — `activate`/`suspend` bracket the widget's
/// lifetime so a closed notch holds nothing, and `makeContentView` is called
/// rarely (on activation and on a declared change), never on a timer.
@MainActor
public protocol NotchWidget: AnyObject {

    /// Stable identity used by the registry; never changes at runtime.
    static var identifier: WidgetIdentifier { get }

    /// Where the widget wants to live. The host honors it against `NotchState`.
    var preferredRegion: NotchRegion { get }

    /// Build the SwiftUI content shown while the region is open.
    func makeContentView() -> AnyView

    /// Called when the region becomes visible. Acquire resources and subscribe
    /// here; the context is valid until the matching `suspend()`.
    func activate(in context: WidgetContext)

    /// Called when the region hides. Release images, cancel subscriptions, free
    /// buffers — after this the widget must consume no CPU and minimal RAM.
    func suspend()
}

public extension NotchWidget {

    // Most widgets hold no resources beyond their view, so the lifecycle hooks
    // are optional: the default pair does nothing.
    func activate(in context: WidgetContext) {}

    func suspend() {}
}
