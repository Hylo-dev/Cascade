//
//  WidgetHost.swift
//  CascadeKit
//

import SwiftUI

/// WidgetHost is the layout workspace: the widget instances (deduplicated), the
/// arrangement of page 0 on each display, and the rendering of the open
/// display's arrangement onto the grid.
///
/// - `widgets` holds each instance once, keyed by id; an arrangement references
///   widgets by id, so one widget shown on several displays is never duplicated.
/// - A display nobody edited shows the shared default arrangement, which
///   auto-places every widget as it registers. The first edit on a display gives
///   it its own copy, keyed by the display's stable identity. An edited
///   arrangement never auto-places a newly registered widget: it waits in the
///   gallery, as a new widget does on a phone's home screen.
/// - An arrangement keeps the place of a widget that is not registered right now,
///   such as a plugin switched off, so it comes back where it was; an edit that
///   covers its cells drops that place, so the two can never overlap.
/// - It owns the pure `NotchLayoutResolver` and turns the open display's
///   arrangement into a positioned SwiftUI `ZStack` for the renderer.
///
/// Lifecycle: when the notch opens on a display the host `activate`s the widgets
/// of that display's arrangement (handing each a context) and `suspend`s every
/// other one, and it suspends them all when the notch closes, so a closed notch,
/// and a widget taken off the grid, hold no widget resources.
@MainActor
final class WidgetHost {

    /// unidentifiedDisplay keys the arrangement of a display CoreGraphics gives no UUID; such
    /// displays share one arrangement.
    nonisolated static let unidentifiedDisplay = DisplayIdentity(rawValue: "unidentified")

    /// Fired when a widget asks for a content refresh or the arrangement changes;
    /// the controller re-renders.
    var onContentChanged: (() -> Void)?

    private var widgets           : [WidgetIdentifier: NotchWidget] = [:]
    private var registrationOrder : [WidgetIdentifier] = []
    private var defaultArrangement: [WidgetIdentifier: WidgetPlacement] = [:]
    private var editedArrangements: [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]] = [:]
    private var currentDisplay     = WidgetHost.unidentifiedDisplay
    private var openState         : NotchState?

    private var contexts     : [WidgetIdentifier: WidgetContext] = [:]
    private var activeWidgets: Set<WidgetIdentifier> = []
    private var cachedViews  : [WidgetIdentifier: AnyView] = [:]

    private let resolver: NotchLayoutResolver
    private let store   : (any WidgetArrangementStoring)?

    /// init(metrics:store:) takes the store edited arrangements persist to; without one, as in
    /// tests, edits last for the session only.
    init(
        metrics: NotchLayoutMetrics = .default,
        store  : (any WidgetArrangementStoring)? = nil
    ) {
        self.resolver = NotchLayoutResolver(metrics: metrics)
        self.store    = store
    }

    /// restoreArrangements reads the saved arrangements off the main thread and applies them
    /// here. A display edited before they arrived keeps its newer edit.
    func restoreArrangements() async {
        guard let store else { return }

        let saved = await store.load()
        for (display, saved) in saved where editedArrangements[display] == nil {
            editedArrangements[display] = saved
        }

        if let openState { update(state: openState, display: currentDisplay) }
        onContentChanged?()
    }

    /// arrangement is the page the open display shows: its own once edited, the
    /// shared default until then.
    var arrangement: [WidgetIdentifier: WidgetPlacement] {
        editedArrangements[currentDisplay] ?? defaultArrangement
    }

    /// gallery lists the registered widgets that are not on the open display's
    /// grid, in the order they registered, for the editing gallery to offer.
    var gallery: [NotchWidget] {
        let arrangement = arrangement

        return registrationOrder.compactMap { id in
            arrangement[id] == nil ? widgets[id] : nil
        }
    }

    /// register adds a widget instance and, if it isn't placed yet, auto-places
    /// it into the first free block of the default arrangement's main rows.
    func register(_ widget: NotchWidget) {
        if widgets[widget.id] == nil { registrationOrder.append(widget.id) }
        widgets[widget.id] = widget
        cachedViews.removeValue(forKey: widget.id)

        guard defaultArrangement[widget.id] == nil else { return }

        if let placement = autoPlacement(for: widget.size) {
            defaultArrangement[widget.id] = placement
        }
    }

    /// unregister removes one instance and revokes its context before provider
    /// cleanup runs. An edited arrangement keeps its place for when it returns.
    func unregister(id: WidgetIdentifier) {
        suspend(id)
        widgets.removeValue(forKey: id)
        registrationOrder.removeAll { $0 == id }
        defaultArrangement.removeValue(forKey: id)
        onContentChanged?()
    }

    /// update activates the open display's widgets when the notch is open and
    /// suspends every other one; it suspends them all when the notch closes.
    func update(
        state  : NotchState,
        display: DisplayIdentity = WidgetHost.unidentifiedDisplay
    ) {
        guard !state.isClosed else {
            activeWidgets.forEach(suspend)
            openState = nil
            return
        }

        openState      = state
        currentDisplay = display

        let arrangement = arrangement
        for id in activeWidgets where arrangement[id] == nil {
            suspend(id)
        }

        for id in arrangement.keys {
            guard let widget = widgets[id] else { continue }

            if activeWidgets.contains(id) {
                if contexts[id]?.state != state { cachedViews.removeValue(forKey: id) }
                contexts[id]?.update(state: state)
            } else {
                let context = WidgetContext(state: state) { [weak self] in
                    self?.refresh(id: id)
                }
                contexts[id] = context
                widget.activate(in: context)
                activeWidgets.insert(id)
            }
        }
    }

    // MARK: - Editing

    /// move drops a widget with its top-leading cell on `position`. A drop that
    /// does not fit, off the grid or over another widget, is refused and the
    /// widget keeps its place.
    @discardableResult
    func move(
        _ id       : WidgetIdentifier,
        to position: GridPosition,
        on grid    : NotchGrid
    ) -> Bool {
        guard let current = arrangement[id] else { return false }

        let moved = WidgetPlacement(position: position, span: current.span)
        guard grid.fits(moved, among: placements(besides: id)) else { return false }

        commit(moved, for: id)
        return true
    }

    /// resize switches a widget to another of its sizes. It keeps its origin when
    /// the new size fits there, moves to the first free fit of the main rows when
    /// it does not, and is refused when the size fits nowhere.
    @discardableResult
    func resize(
        _ id   : WidgetIdentifier,
        to span: GridSpan,
        on grid: NotchGrid
    ) -> Bool {
        guard let current = arrangement[id] else { return false }

        let others  = placements(besides: id)
        let inPlace = WidgetPlacement(position: current.position, span: span)
        guard let resized = grid.fits(inPlace, among: others)
                ? inPlace
                : grid.firstFit(for: span, among: others)
        else { return false }

        commit(resized, for: id)
        return true
    }

    /// add puts a gallery widget on the grid at the first free fit of the chosen
    /// size, and is refused when the size fits nowhere.
    @discardableResult
    func add(
        _ id   : WidgetIdentifier,
        size   : GridSpan,
        on grid: NotchGrid
    ) -> Bool {
        guard widgets[id] != nil,
              arrangement[id] == nil,
              let placement = grid.firstFit(for: size, among: placements(besides: id))
        else { return false }

        commit(placement, for: id)
        return true
    }

    /// remove takes a widget off the open display's grid. It is suspended at once,
    /// so a removed plugin widget tells the engine it is no longer visible.
    func remove(_ id: WidgetIdentifier) {
        guard arrangement[id] != nil else { return }

        var edited = arrangement
        edited.removeValue(forKey: id)
        apply(edited)
    }

    /// canAdd tells the gallery whether a size has a free fit, so a button that
    /// would be refused is shown disabled instead.
    func canAdd(
        _ span : GridSpan,
        on grid: NotchGrid
    ) -> Bool {
        grid.firstFit(for: span, among: placements(besides: nil)) != nil
    }

    /// placements are the blocks of the registered widgets on the open display's
    /// grid, except `id`'s own: an absent widget's place never blocks an edit.
    private func placements(besides id: WidgetIdentifier?) -> [WidgetPlacement] {
        arrangement.compactMap { other, placement in
            other != id && widgets[other] != nil ? placement : nil
        }
    }

    /// commit stores one widget's new place and drops the place of any absent
    /// widget it now covers.
    private func commit(
        _ placement: WidgetPlacement,
        for id     : WidgetIdentifier
    ) {
        var edited = arrangement.filter { other, kept in
            widgets[other] != nil || !kept.overlaps(placement)
        }
        edited[id] = placement
        apply(edited)
    }

    /// apply makes `edited` the open display's own arrangement, saves every
    /// edited arrangement, brings the widgets' activation in line with it, and
    /// asks for a re-render.
    private func apply(_ edited: [WidgetIdentifier: WidgetPlacement]) {
        editedArrangements[currentDisplay] = edited
        store?.save(editedArrangements)
        if let openState { update(state: openState, display: currentDisplay) }
        onContentChanged?()
    }

    // MARK: - Rendering

    /// makeContentView builds the open display's content: it resolves every
    /// placement to a frame and drops each widget's view into a `ZStack` at that
    /// frame. Frames come back in the host view's (y-up) coordinates, so we flip
    /// y for SwiftUI.
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
            placements   : arrangement
        )

        let placed = layout.frames.compactMap { id, rect -> PositionedWidget? in
            guard let widget = widgets[id] else { return nil }

            let view = cachedViews[id] ?? widget.makeContentView()
            cachedViews[id] = view
            return PositionedWidget(
                id  : id,
                view: view,
                rect: rect
            )
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

    private func refresh(id: WidgetIdentifier) {
        guard activeWidgets.contains(id), let widget = widgets[id] else { return }

        cachedViews[id] = widget.makeContentView()
        onContentChanged?()
    }

    /// suspend revokes a widget's context before suspending it, so a retained
    /// copy can no longer ask for content.
    private func suspend(_ id: WidgetIdentifier) {
        contexts.removeValue(forKey: id)?.revoke()
        cachedViews.removeValue(forKey: id)

        if activeWidgets.remove(id) != nil { widgets[id]?.suspend() }
    }

    /// PositionedWidget pairs a widget's resolved view with its frame, ready to
    /// position in the `ZStack`.
    private struct PositionedWidget: Identifiable {

        let id  : WidgetIdentifier
        let view: AnyView
        let rect: CGRect
    }

    /// autoPlacement finds the first-fit placement in the main rows (1 and 2),
    /// skipping cells already taken in the default arrangement. Row 0 (the notch
    /// band) is reserved for explicit / drag-and-drop placement, since its
    /// availability depends on the live notch geometry.
    private func autoPlacement(for span: GridSpan) -> WidgetPlacement? {
        NotchGrid(columns: resolver.metrics.columns, bandColumns: 0 ..< 0).firstFit(
            for  : span,
            among: Array(defaultArrangement.values)
        )
    }
}
