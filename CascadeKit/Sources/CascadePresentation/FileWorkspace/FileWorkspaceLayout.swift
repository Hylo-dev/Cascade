//
//  FileWorkspaceLayout.swift
//  Cascade
//

import CoreGraphics

/// FileCardTransform describes one stable card slot in the four-card fan.
public struct FileCardTransform: Equatable, Sendable {
    public let index          : Int
    public let rotationDegrees: Double
    public let xOffset        : Double
    public let yOffset        : Double
    public let scale          : Double
}

/// FileConversionFrames keeps the conversion arrow centered between nonoverlapping groups.
public struct FileConversionFrames: Equatable, Sendable {
    public let inputs  : CGRect
    public let arrow   : CGRect
    public let selector: CGRect
    public let controls: CGRect
    public let results : CGRect
}

/// FileWorkspaceLayout contains deterministic geometry shared by rendering and previews.
public enum FileWorkspaceLayout {
    public static let maximumVisibleCards = 4

    public static func cardTransforms(
        count       : Int,
        reduceMotion: Bool
    ) -> [FileCardTransform] {
        let visibleCount = min(max(0, count), maximumVisibleCards)
        return (0..<visibleCount).map { index in
            if reduceMotion {
                return FileCardTransform(
                    index          : index,
                    rotationDegrees: 0,
                    xOffset        : -Double(index * 18),
                    yOffset        : 0,
                    scale          : 1 - Double(index) * 0.035
                )
            }
            return FileCardTransform(
                index          : index,
                rotationDegrees: index == 0 ? 4 : -Double(index * 4),
                xOffset        : -Double(index * 18),
                yOffset        : Double(index * 3),
                scale          : 1 - Double(index) * 0.035
            )
        }
    }

    public static func overflowCount(totalCount: Int) -> Int {
        max(0, totalCount - maximumVisibleCards)
    }

    /// conversionFrames reserves a fixed center lane, including at compact notch widths.
    public static func conversionFrames(in bounds: CGRect) -> FileConversionFrames {
        let insetBounds = bounds.insetBy(dx: 12, dy: 10)
        let centerWidth = min(124, max(92, insetBounds.width * 0.28))
        let groupWidth = max(72, (insetBounds.width - centerWidth) / 2)
        let inputs = CGRect(
            x     : insetBounds.minX,
            y     : insetBounds.minY,
            width : groupWidth,
            height: insetBounds.height
        )
        let results = CGRect(
            x     : insetBounds.maxX - groupWidth,
            y     : insetBounds.minY,
            width : groupWidth,
            height: insetBounds.height
        )
        let gapMidX = (inputs.maxX + results.minX) / 2
        let arrow = CGRect(
            x     : gapMidX - 18,
            y     : bounds.midY - 12,
            width : 36,
            height: 24
        )
        let selector = CGRect(
            x     : gapMidX - centerWidth / 2 + 4,
            y     : arrow.minY - 42,
            width : centerWidth - 8,
            height: 28
        )
        let controls = CGRect(
            x     : gapMidX - centerWidth / 2 + 4,
            y     : arrow.maxY + 14,
            width : centerWidth - 8,
            height: 28
        )
        return FileConversionFrames(
            inputs  : inputs,
            arrow   : arrow,
            selector: selector,
            controls: controls,
            results : results
        )
    }
}
