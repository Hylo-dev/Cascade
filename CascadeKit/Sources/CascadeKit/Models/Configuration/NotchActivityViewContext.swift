//
//  NotchActivityViewContext.swift
//  CascadeKit
//

import CoreGraphics

/// NotchActivityViewContext carries the family and usable content bounds in
/// this window's points, not iPhone sizes.
public nonisolated struct NotchActivityViewContext: Sendable, Equatable {
    public let presentation: NotchActivityPresentation
    public let availableSize: CGSize
    public let isStale: Bool
    /// Calibrated cutout width for aligning expanded artwork with its side.
    public let hardwareNotchWidth: CGFloat?

    public init(
        presentation: NotchActivityPresentation,
        availableSize: CGSize,
        isStale: Bool = false,
        hardwareNotchWidth: CGFloat? = nil
    ) {
        self.presentation = presentation
        self.availableSize = availableSize
        self.isStale = isStale
        self.hardwareNotchWidth = hardwareNotchWidth
    }
}
