//
//  WidgetTileView.swift
//  CascadeKit
//

import SwiftUI

/// WidgetTileView is one widget on the board. At rest it is the widget's own content; a press
/// held still for half a second starts editing (as does a named accessibility action), and the
/// same press then moves the widget at once, without lifting, as on macOS and iOS. While editing
/// the content stops taking clicks, every tile wiggles, picked up or not, and shows its block and
/// its controls: a minus to remove it and, when it has more than one size, a corner handle.
/// Clicking the handle steps to the next size; dragging it stretches the tile under the pointer
/// and, on release, settles on the declared size nearest to where it was let go, keeping the
/// tile's corner. While a tile moves or stretches, the board lights the cells it would take.
///
/// One gesture follows the whole press, so entering editing in the middle of it does not end it,
/// and where the press began tells moving from resizing. The drag offset and the stretch are this
/// tile's own state, so the pointer invalidates this tile alone. The structure stays the same in
/// both modes, so entering editing does not rebuild the widget's content. The wiggle is the
/// board's only continuous animation and runs only while editing.
struct WidgetTileView: View {

    /// Mode is what one press does: move the tile, or stretch it from its corner handle.
    private enum Mode {

        case move
        case resize
    }

    /// handleSize is the corner a press must begin in to resize, in points.
    private static let handleSize = 20.0

    let tile     : WidgetBoardView.Tile
    let isEditing: Bool
    let actions  : WidgetBoardView.Actions
    let onTarget : (WidgetBoardView.Target?) -> Void

    @State
    private var dragOffset = CGSize.zero

    @State
    private var stretch = CGSize.zero

    @State
    private var press: WidgetPress?

    @State
    private var mode: Mode?

    @State
    private var hold: Task<Void, Never>?

    init(
        tile     : WidgetBoardView.Tile,
        isEditing: Bool,
        actions  : WidgetBoardView.Actions,
        onTarget : @escaping (WidgetBoardView.Target?) -> Void = { _ in }
    ) {
        self.tile      = tile
        self.isEditing = isEditing
        self.actions   = actions
        self.onTarget  = onTarget
    }

    var body: some View {
        // The timeline is paused whenever the board is not editing, so at rest it costs nothing;
        // the gesture sits outside it, untouched by its frames.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isEditing)) { context in
            content
                .rotationEffect(.degrees(isEditing ? wiggleAngle(at: context.date) : 0))
        }
        .offset(dragOffset)
        .simultaneousGesture(pressAndDrag)
        .accessibilityAction(named: Text("Edit Widgets", bundle: .module)) {
            actions.setEditing(true)
        }
        .accessibilityAction(named: Text("Resize Widget", bundle: .module)) {
            if isEditing, tile.canResize {
                actions.resize(tile.id)
            }
        }
        .zIndex(dragOffset == .zero && stretch == .zero ? 0 : 1)
    }

    /// content is the widget with its editing block and controls, stretched from its top-leading
    /// corner while its handle is dragged.
    private var content: some View {
        tile.view
            .allowsHitTesting(!isEditing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isEditing {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.13))
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }
            }
            .overlay(alignment: .topLeading) {
                if isEditing {
                    control(symbol: "minus", label: Text("Remove Widget", bundle: .module)) {
                        actions.remove(tile.id)
                    }
                    .offset(x: -5, y: -5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isEditing, tile.canResize {
                    handle
                        .offset(x: 5, y: 5)
                }
            }
            .frame(width: stretchedSize.width, height: stretchedSize.height)
            .offset(x: (stretchedSize.width - tile.frame.width) / 2, y: (stretchedSize.height - tile.frame.height) / 2)
            .contentShape(Rectangle())
    }

    /// stretchedSize is the tile's size under a corner drag, held between the smallest and the
    /// largest sizes the widget declares, so it never grows past what it can become.
    private var stretchedSize: CGSize {
        CGSize(
            width : min(tile.maximumSize.width, max(tile.minimumSize.width, tile.frame.width + stretch.width)),
            height: min(tile.maximumSize.height, max(tile.minimumSize.height, tile.frame.height + stretch.height))
        )
    }

    /// wiggleAngle is the tile's tilt at `date`, a little over a degree each way three and a half
    /// times a second. Tiles start half a turn apart, so the board shivers instead of rocking in
    /// step.
    private func wiggleAngle(at date: Date) -> Double {
        let phase = tile.id.rawValue.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }.isMultiple(of: 2) ? 0 : Double.pi

        return sin(date.timeIntervalSinceReferenceDate * 2 * .pi * 3.5 + phase) * 1.1
    }

    /// pressAndDrag follows one press from touch-down to release. Begun on the corner handle while
    /// editing, it resizes; anywhere else, held still long enough it starts editing, and while
    /// editing the tile follows it.
    private var pressAndDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if press == nil {
                    press = WidgetPress(isEditing: isEditing)
                    mode  = isOnHandle(value.startLocation) ? .resize : .move
                    if !isEditing {
                        waitForHold()
                    }
                }
                press?.move(to: value.translation)

                switch mode {
                    case .resize?:
                        stretch = value.translation
                        onTarget(actions.resizeTarget(tile.id, value.translation))

                    case .move?, nil:
                        if isEditing, let offset = press?.offset {
                            dragOffset = offset
                            onTarget(actions.target(tile.id, offset))
                        }
                }
            }
            .onEnded { value in
                hold?.cancel()
                hold = nil
                let ended = (press: press, mode: mode)
                press = nil
                mode  = nil
                onTarget(nil)

                if ended.mode == .resize {
                    finishResize(after: value.translation)
                } else {
                    finishMove(by: isEditing ? ended.press?.offset : nil)
                }
            }
    }

    /// isOnHandle is true when a press begins on the corner handle of a resizable, editing tile.
    private func isOnHandle(_ location: CGPoint) -> Bool {
        isEditing
            && tile.canResize
            && location.x >= tile.frame.width - Self.handleSize
            && location.y >= tile.frame.height - Self.handleSize
    }

    /// finishMove drops the tile where it was let go; a refused drop springs back. The board
    /// springs an accepted one into its cell as the tile's frame changes.
    private func finishMove(by offset: CGSize?) {
        if let offset, offset != .zero {
            _ = actions.drop(tile.id, offset)
        }
        withAnimation(.snappy) { dragOffset = .zero }
    }

    /// finishResize treats a click on the handle as a step to the next size and a drag as a
    /// stretch to the nearest declared size that fits in place. Either way the board springs the
    /// tile to its new frame while the stretch eases out.
    private func finishResize(after translation: CGSize) {
        if (translation.width * translation.width + translation.height * translation.height).squareRoot() < 3 {
            actions.resize(tile.id)
        } else if let target = actions.resizeTarget(tile.id, translation), target.fits {
            _ = actions.commitResize(tile.id, target.placement.span)
        }
        withAnimation(.snappy) { stretch = .zero }
    }

    /// waitForHold starts editing when the press is still held, and still, after the hold
    /// duration; from then on the same press moves the tile.
    private func waitForHold() {
        hold?.cancel()
        hold = Task { @MainActor in
            try? await Task.sleep(for: WidgetPress.holdDuration)
            guard !Task.isCancelled, press?.canStartEditing == true else { return }

            actions.setEditing(true)
            actions.feedback()
            press?.beginEditing()
        }
    }

    /// handle is the resize corner: drawn here, driven by the tile's one gesture.
    private var handle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color(white: 0.38)))
            .accessibilityHidden(true)
    }

    /// control is one of the tile's round editing buttons.
    private func control(
        symbol: String,
        label : Text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color(white: 0.38)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
