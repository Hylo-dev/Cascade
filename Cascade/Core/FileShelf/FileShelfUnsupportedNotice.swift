//
//  FileShelfUnsupportedNotice.swift
//  Cascade
//

import AppKit
import CascadeKit
import SwiftUI

@MainActor
final class FileShelfUnsupportedNotice: NotchTransientNotice {

    let id                        = "cascade.file-shelf.unsupported"
    let sourceID                  = "cascade.file-shelf"
    let contentRevision          : UInt64
    let displayDuration          : TimeInterval = 4
    let privacy                  : NotchActivityPrivacy = .standard
    let compactPreferredSideWidth: CGFloat? = 148
    let accessibilityLabel        = "Solo file locali. Cartelle e file promessi non sono supportati."

    init(revision: UInt64) { contentRevision = revision }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            Label("Solo file locali", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height)
                .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            Text("Cartelle e file promessi non supportati")
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height)
                .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height)
                .accessibilityLabel(accessibilityLabel)
        )
    }
}
