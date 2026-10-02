//
//  WidgetTileView.swift
//  CascadeKit
//

import SwiftUI

/// WidgetTileView is one widget on the board. At rest it is the widget's own content; a press
/// held still for half a second starts editing (as does a named accessibility action), and the
/// same press then moves the widget at once, without lifting, as on macOS and iOS. While editing
/// the content stops taking clicks, the tile shows its block and its controls, a minus to remove
/// it and, when it has more than one size, a control to step to the next one, it wiggles until
/// it is picked up, and it follows the pointer when dragged. On release the host snaps it to the
/// nearest cell or refuses the drop, and a refused tile springs back to where it was.
///
/// One gesture follows the whole press, so entering editing in the middle of it does not end it.
/// The drag offset is this tile's own state, so a drag invalidates this tile alone and the rest
/// of the board never re-renders while the pointer moves. The structure stays the same in both
/// modes, so entering editing does not rebuild the widget's content. The wiggle is the board's
/// only continuous animation and runs only while editing.
struct WidgetTileView: View {

    let tile     : WidgetBoardView.Tile
    let isEditing: Bool
    let actions  : WidgetBoardView.Actions

    @State
    private var dragOffset = CGSize.zero

    @State
    private var press: WidgetPress?

    @State
    private var hold: Task<Void, Never>?

    init(
        tile     : WidgetBoardView.Tile,
        isEditing: Bool,
        actions  : WidgetBoardView.Actions
    ) {
        self.tile      = tile
        self.isEditing = isEditing
        self.actions   = actions
    }

    var body: some View {
        // The timeline is paused whenever the tile is not wiggling, so at rest, and on the tile
        // being dragged, it costs nothing; the gesture sits outside it, untouched by its frames.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !wiggles)) { context in
            content
                .rotationEffect(.degrees(wiggles ? wiggleAngle(at: context.date) : 0))
        }
        .offset(dragOffset)
        .simultaneousGesture(pressAndDrag)
        .accessibilityAction(named: Text("Edit Widgets", bundle: .module)) {
            actions.setEditing(true)
        }
        .zIndex(dragOffset == .zero ? 0 : 1)
    }

    /// content is the widget with its editing block and controls.
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
                    control(symbol: "arrow.up.left.and.arrow.down.right", label: Text("Resize Widget", bundle: .module)) {
                        actions.resize(tile.id)
                    }
                    .offset(x: 5, y: 5)
                }
            }
            .contentShape(Rectangle())
    }

    /// wiggles is true while the tile waits to be picked up: editing, and not held or dragged.
    private var wiggles: Bool {
        isEditing && press == nil && dragOffset == .zero
    }

    /// wiggleAngle is the tile's tilt at `date`, a little over a degree each way three and a half
    /// times a second. Tiles start half a turn apart, so the board shivers instead of rocking in
    /// step.
    private func wiggleAngle(at date: Date) -> Double {
        let phase = tile.id.rawValue.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }.isMultiple(of: 2) ? 0 : Double.pi

        return sin(date.timeIntervalSinceReferenceDate * 2 * .pi * 3.5 + phase) * 1.1
    }

    /// pressAndDrag follows one press from touch-down to release: held still long enough it
    /// starts editing, and while editing the tile follows it.
    private var pressAndDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if press == nil {
                    press = WidgetPress(isEditing: isEditing)
                    if !isEditing {
                        waitForHold()
                    }
                }
                press?.move(to: value.translation)
                if isEditing, let offset = press?.offset {
                    dragOffset = offset
                }
            }
            .onEnded { _ in
                hold?.cancel()
                hold = nil
                let offset = isEditing ? press?.offset : nil
                press = nil

                guard let offset, offset != .zero else {
                    withAnimation(.snappy) { dragOffset = .zero }
                    return
                }
                if actions.drop(tile.id, offset) {
                    dragOffset = .zero
                } else {
                    withAnimation(.snappy) { dragOffset = .zero }
                }
            }
    }

    /// waitForHold starts editing when the press is still held, and still, after the hold
    /// duration; from then on the same press moves the tile.
    private func waitForHold() {
        hold?.cancel()
        hold = Task { @MainActor in
            try? await Task.sleep(for: WidgetPress.holdDuration)
            guard !Task.isCancelled, press?.canStartEditing == true else { return }

            actions.setEditing(true)
            press?.beginEditing()
        }
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
