//
//  WidgetTileView.swift
//  CascadeKit
//

import SwiftUI

/// WidgetTileView is one widget on the board. At rest it is the widget's own content, with a
/// half-second press to start editing (and the same as a named accessibility action). While
/// editing the content stops taking clicks, the tile shows its block and its controls, a minus
/// to remove it and, when it has more than one size, a control to step to the next one, and it
/// follows the pointer when dragged. On release the host snaps it to the nearest cell or
/// refuses the drop, and a refused tile springs back to where it was.
///
/// The drag offset is this tile's own state, so a drag invalidates this tile alone and the rest
/// of the board never re-renders while the pointer moves. The structure stays the same in both
/// modes, so entering editing does not rebuild the widget's content.
struct WidgetTileView: View {

    let tile     : WidgetBoardView.Tile
    let isEditing: Bool
    let actions  : WidgetBoardView.Actions

    @State
    private var dragOffset = CGSize.zero

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
            .offset(dragOffset)
            .gesture(drag, including: isEditing ? .all : .subviews)
            .simultaneousGesture(longPress, including: isEditing ? .subviews : .all)
            .accessibilityAction(named: Text("Edit Widgets", bundle: .module)) {
                actions.setEditing(true)
            }
            .zIndex(dragOffset == .zero ? 0 : 1)
    }

    private var longPress: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in actions.setEditing(true) }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                if actions.drop(tile.id, value.translation) {
                    dragOffset = .zero
                } else {
                    withAnimation(.snappy) { dragOffset = .zero }
                }
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
