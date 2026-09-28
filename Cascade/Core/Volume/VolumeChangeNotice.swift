//
//  VolumeChangeNotice.swift
//  Cascade
//

import CascadeKit
import SwiftUI

/// VolumeChangeNotice renders a brief output-volume change in the two compact
/// wings. It has no expanded content or interaction; the host owns its deadline.
@MainActor
final class VolumeChangeNotice: NotchTransientNotice {

    let id                        = "cascade.volume.current"
    let sourceID                  = "cascade.volume"
    let privacy                  : NotchActivityPrivacy = .standard
    let compactPreferredSideWidth: CGFloat? = 116
    let displayDuration          : TimeInterval = 1.8

    private(set) var contentRevision: UInt64
    private var event               : VolumeChangeEvent

    var accessibilityLabel: String {
        event.isMuted ? "Audio disattivato" : "Volume, \(event.percentage) percento"
    }

    init(event: VolumeChangeEvent) {
        self.event      = event
        contentRevision = event.revision
    }

    /// update preserves one source identity while its displayed value changes.
    /// Hardware callbacks already filtered by the reducer do not rebuild views.
    func update(_ event: VolumeChangeEvent) {
        self.event      = event
        contentRevision = event.revision
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            HStack(spacing: 6) {

                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)

                Text(event.isMuted ? "Silenzioso" : "Volume")
                    .font(.callout)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(
                maxWidth : context.availableSize.width,
                maxHeight: context.availableSize.height,
                alignment: .leading
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        let percentage = event.percentage

        return AnyView(
            HStack(spacing: 6) {

                GeometryReader { geometry in

                    ZStack(alignment: .leading) {

                        Capsule()
                            .fill(.white.opacity(0.23))

                        Capsule()
                            .fill(.white)
                            .frame(width: geometry.size.width * CGFloat(percentage) / 100)
                    }
                }
                .frame(height: 4)

                Text("\(percentage)%")
                    .font(.callout)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            .foregroundStyle(.white)
            .frame(
                maxWidth : context.availableSize.width,
                maxHeight: context.availableSize.height
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .frame(
                    maxWidth : context.availableSize.width,
                    maxHeight: context.availableSize.height
                )
                .accessibilityLabel(accessibilityLabel)
        )
    }

    private var symbolName: String {
        if event.isMuted || event.percentage == 0 { return "speaker.slash.fill" }
        if event.percentage < 34 { return "speaker.wave.1.fill" }
        if event.percentage < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
