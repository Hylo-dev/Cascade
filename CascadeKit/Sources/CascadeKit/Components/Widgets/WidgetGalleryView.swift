//
//  WidgetGalleryView.swift
//  CascadeKit
//

import SwiftUI

/// WidgetGalleryView is the strip under the grid while editing: every widget that is not on the
/// grid, as a small live preview of its own content, with one button per size when it has more
/// than one. Clicking the preview adds the widget at its first size; a size button adds it at
/// that size. A size with no free fit on the grid is shown disabled rather than refused after
/// the click. The previews never take clicks themselves, and the row scrolls only when it does
/// not fit.
struct WidgetGalleryView: View {

    let entries: [WidgetBoardView.GalleryEntry]
    let actions: WidgetBoardView.Actions

    /// previewHeight is the tallest a preview is drawn; larger widgets are scaled down to it.
    private let previewHeight: CGFloat = 44

    var body: some View {
        if entries.isEmpty {
            Text("Every widget is on the notch.", bundle: .module)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ViewThatFits(in: .horizontal) {

                row

                ScrollView(.horizontal, showsIndicators: false) {
                    row
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var row: some View {
        HStack(spacing: 16) {

            ForEach(entries) { entry in
                item(entry)
            }
        }
        .padding(.horizontal, 8)
    }

    private func item(_ entry: WidgetBoardView.GalleryEntry) -> some View {
        HStack(spacing: 6) {

            if let first = entry.options.first {
                Button { actions.add(entry.id, first.span) } label: {
                    preview(entry.view, size: first.size)
                }
                .buttonStyle(.plain)
                .disabled(!first.isAvailable)
                .accessibilityLabel(Text("Add Widget", bundle: .module))
            }

            if entry.options.count > 1 {
                VStack(spacing: 4) {

                    ForEach(entry.options) { option in
                        Button { actions.add(entry.id, option.span) } label: {
                            glyph(for: option.size)
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.isAvailable)
                        .opacity(option.isAvailable ? 1 : 0.35)
                        .accessibilityLabel(Text("Add Widget, Size \(option.index + 1) of \(entry.options.count)", bundle: .module))
                    }
                }
            }
        }
    }

    /// preview draws the widget at its real size and scales the drawing down, so the preview is
    /// exactly what the tile will look like.
    private func preview(
        _ view: AnyView,
        size  : CGSize
    ) -> some View {
        let scale = size.height > 0 ? min(1, previewHeight / size.height) : 1

        return view
            .allowsHitTesting(false)
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }

    /// glyph is a size button: an outline with the size's proportions, so a wide and a square
    /// size read apart without words.
    private func glyph(for size: CGSize) -> some View {
        let width : CGFloat = 18
        let height = size.width > 0 ? min(18, max(6, width * size.height / size.width)) : width

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.2)
            .frame(width: width, height: height)
            .padding(2)
            .contentShape(Rectangle())
    }
}
