//
//  WidgetBoardView.swift
//  CascadeKit
//

import SwiftUI

/// WidgetBoardView draws page 0 of the open notch: every widget at its resolved frame and,
/// while editing, the grid's cells, each tile's controls, the Done button and the gallery.
///
/// Every frame arrives already resolved and flipped to SwiftUI's y-down space, so the view
/// does no layout math of its own. Editing is a discrete mode: entering or leaving it, and every
/// accepted edit, rebuilds the board once through the host, while a drag only moves the one
/// tile being dragged and lights the cells it would land on, in white where it fits and in red
/// where it would be refused. A tile that moves or changes size on the grid springs to its new
/// frame. A tap on empty notch area ends editing, and a zero-size keyboard target takes focus
/// while editing so that Escape ends it too.
struct WidgetBoardView: View {

    /// Tile is one placed widget: its view, its frame and whether it can change size.
    struct Tile: Identifiable {

        let id       : WidgetIdentifier
        let view     : AnyView
        let frame    : CGRect
        let canResize: Bool
    }

    /// GalleryEntry is one widget that is not on the grid, with a preview and the sizes it can
    /// be added at.
    struct GalleryEntry: Identifiable {

        let id     : WidgetIdentifier
        let view   : AnyView
        let options: [GalleryOption]
    }

    /// GalleryOption is one size a gallery widget can be added at: its span, its size in points
    /// and whether the grid has a free fit for it.
    struct GalleryOption: Identifiable {

        let index      : Int
        let span       : GridSpan
        let size       : CGSize
        let isAvailable: Bool

        var id: Int { index }
    }

    /// Target is where a dragged or resized tile would land: its placement, the cells it would
    /// cover and whether the grid accepts it there.
    struct Target: Equatable {

        let placement: WidgetPlacement
        let cells    : [CGRect]
        let fits     : Bool
    }

    /// Actions are the edits the board asks the host for. `drop` takes the translation a tile
    /// was dragged by and answers whether the widget moved; `target` says where that drop would
    /// land. `resizeTarget` takes how far a tile's corner was dragged and picks the declared size
    /// nearest to it, keeping the tile's corner, and `commitResize` applies it in place.
    struct Actions {

        let setEditing  : (Bool) -> Void
        let drop        : (WidgetIdentifier, CGSize) -> Bool
        let target      : (WidgetIdentifier, CGSize) -> Target?
        let remove      : (WidgetIdentifier) -> Void
        let resize      : (WidgetIdentifier) -> Void
        let resizeTarget: (WidgetIdentifier, CGSize) -> Target?
        let commitResize: (WidgetIdentifier, GridSpan) -> Bool
        let add         : (WidgetIdentifier, GridSpan) -> Void
    }

    let tiles       : [Tile]
    let cells       : [CGRect]
    let isEditing   : Bool
    let doneFrame   : CGRect
    let galleryFrame: CGRect
    let gallery     : [GalleryEntry]
    let actions     : Actions

    @State
    private var highlight: Target?

    init(
        tiles       : [Tile],
        cells       : [CGRect],
        isEditing   : Bool,
        doneFrame   : CGRect,
        galleryFrame: CGRect,
        gallery     : [GalleryEntry],
        actions     : Actions
    ) {
        self.tiles        = tiles
        self.cells        = cells
        self.isEditing    = isEditing
        self.doneFrame    = doneFrame
        self.galleryFrame = galleryFrame
        self.gallery      = gallery
        self.actions      = actions
    }

    var body: some View {
        ZStack(alignment: .topLeading) {

            if isEditing {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { actions.setEditing(false) }

                Path { path in
                    for cell in cells {
                        path.addRoundedRect(in: cell, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                    }
                }
                .fill(Color.white.opacity(0.10))
                .overlay {
                    Path { path in
                        for cell in cells {
                            path.addRoundedRect(in: cell.insetBy(dx: 0.5, dy: 0.5), cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                        }
                    }
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
                .allowsHitTesting(false)

                if let highlight {
                    let color = highlight.fits ? Color.white : Color(red: 1, green: 0.3, blue: 0.3)
                    Path { path in
                        for cell in highlight.cells {
                            path.addRoundedRect(in: cell.insetBy(dx: 0.5, dy: 0.5), cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                        }
                    }
                    .fill(color.opacity(0.22))
                    .stroke(color.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
                }

                WidgetEditingKeyboardTarget { actions.setEditing(false) }
                    .frame(width: 0, height: 0)
            }

            ForEach(tiles) { tile in
                WidgetTileView(
                    tile     : tile,
                    isEditing: isEditing,
                    actions  : actions,
                    onTarget : { target in
                        if highlight != target {
                            highlight = target
                        }
                    }
                )
                .frame(width: tile.frame.width, height: tile.frame.height)
                .position(x: tile.frame.midX, y: tile.frame.midY)
                .animation(.snappy, value: tile.frame)
            }

            if isEditing {
                Button { actions.setEditing(false) } label: {
                    Text("Done", bundle: .module)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
                .frame(width: doneFrame.width, height: doneFrame.height, alignment: .leading)
                .position(x: doneFrame.midX, y: doneFrame.midY)

                WidgetGalleryView(
                    entries: gallery,
                    actions: actions
                )
                .frame(width: galleryFrame.width, height: galleryFrame.height)
                .position(x: galleryFrame.midX, y: galleryFrame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
