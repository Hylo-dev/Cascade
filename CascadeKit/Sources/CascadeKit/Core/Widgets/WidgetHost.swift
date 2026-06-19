//
//  WidgetHost.swift
//  CascadeKit
//

import SwiftUI

/// WidgetHost is the layout workspace: the widget instances (deduplicated), the
/// pages, and the rendering of the current page onto the grid.
///
/// - `widgets` holds each instance once, keyed by id; a screen references widgets
///   by id, so one widget shown on several screens is never duplicated.
/// - `screens` are the ordered pages (the slider will page through them; for now
///   there is one).
/// - It owns the pure `NotchLayoutResolver` and turns the current screen's
///   arrangement into a positioned SwiftUI `ZStack` for the renderer.
///
/// Lifecycle: when the notch opens the host `activate`s the current screen's
/// widgets (handing each a context) and `suspend`s them when it closes, so a
/// closed notch holds no widget resources.
@MainActor
final class WidgetHost {

    /// Fired when a widget asks for a content refresh; the controller re-renders.
    var onContentChanged: (() -> Void)?

    private var widgets : [WidgetIdentifier: NotchWidget] = [:]
    private var screens : [NotchScreen] = [NotchScreen(id: 0)]
    private var currentScreenIndex = 0

    private var contexts      : [WidgetIdentifier: WidgetContext] = [:]
    private var activeWidgets : Set<WidgetIdentifier> = []

    private let resolver: NotchLayoutResolver

    init(metrics: NotchLayoutMetrics = .default) {
        self.resolver = NotchLayoutResolver(metrics: metrics)
    }

    private var currentScreen: NotchScreen {
        get { screens[currentScreenIndex] }
        set { screens[currentScreenIndex] = newValue }
    }

    /// Add a widget instance and, if it isn't placed yet, auto-place it into the
    /// first free block of the current screen's main rows.
    func register(_ widget: NotchWidget) {

        widgets[widget.id] = widget

        guard currentScreen.arrangement[widget.id] == nil else {
            return
        }

        if let placement = autoPlacement(for: widget.size) {
            currentScreen.arrangement[widget.id] = placement
        }
    }

    /// Activate the current screen's widgets when the notch is open, suspend them
    /// all when it closes. (Per-screen activation; switching screens will re-run
    /// this once paging exists.)
    func update(state: NotchState) {

        guard !state.isClosed else {
            activeWidgets.forEach { widgets[$0]?.suspend() }
            activeWidgets.removeAll()
            contexts.removeAll()
            return
        }

        for id in currentScreen.arrangement.keys {

            guard let widget = widgets[id] else {
                continue
            }

            if activeWidgets.contains(id) {
                contexts[id]?.update(state: state)
            } else {
                let context = WidgetContext(state: state) { [weak self] in
                    self?.onContentChanged?()
                }
                contexts[id] = context
                widget.activate(in: context)
                activeWidgets.insert(id)
            }
        }
    }

    /// Build the current screen's content: resolve every placement to a frame and
    /// drop each widget's view into a `ZStack` at that frame. Frames come back in
    /// the host view's (y-up) coordinates, so we flip y for SwiftUI.
    func makeContentView(
        interior     : CGRect,
        notchWidth   : CGFloat,
        topBandHeight: CGFloat,
        hostHeight   : CGFloat
    ) -> AnyView {

        let layout = resolver.resolve(
            interior     : interior,
            notchWidth   : notchWidth,
            topBandHeight: topBandHeight,
            placements   : currentScreen.arrangement
        )

        let placed = layout.frames.compactMap { id, rect -> PositionedWidget? in
            guard let widget = widgets[id] else { return nil }
            return PositionedWidget(id: id, view: widget.makeContentView(), rect: rect)
        }

        return AnyView(
            ZStack(alignment: .topLeading) {

                ForEach(placed) { item in
                    item.view
                        .frame(width: item.rect.width, height: item.rect.height)
                        .position(x: item.rect.midX, y: hostHeight - item.rect.midY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    /// A widget's resolved view + frame, ready to position in the `ZStack`.
    private struct PositionedWidget: Identifiable {
        let id  : WidgetIdentifier
        let view: AnyView
        let rect: CGRect
    }

    /// First-fit placement in the main rows (1 and 2), skipping cells already
    /// taken on the current screen. Row 0 (the notch band) is reserved for
    /// explicit / drag-and-drop placement, since its availability depends on the
    /// live notch geometry.
    private func autoPlacement(for span: GridSpan) -> WidgetPlacement? {

        let columns = resolver.metrics.columns

        var occupied: Set<GridPosition> = []
        for placement in currentScreen.arrangement.values {
            for column in placement.position.column ..< placement.position.column + placement.span.columns {
                for row in placement.position.row ..< placement.position.row + placement.span.rows {
                    occupied.insert(GridPosition(column: column, row: row))
                }
            }
        }

        // A two-row widget can only originate at row 1 (covering rows 1–2); a
        // one-row widget may sit in either main row.
        let originRows = span.rows == 2 ? [1] : [1, 2]

        for row in originRows {
            for column in 0 ... max(0, columns - span.columns) {

                var fits = true
                for c in column ..< column + span.columns {
                    for r in row ..< row + span.rows where occupied.contains(GridPosition(column: c, row: r)) {
                        fits = false
                    }
                }

                if fits {
                    return WidgetPlacement(
                        position: GridPosition(column: column, row: row),
                        span    : span
                    )
                }
            }
        }

        return nil
    }
}
