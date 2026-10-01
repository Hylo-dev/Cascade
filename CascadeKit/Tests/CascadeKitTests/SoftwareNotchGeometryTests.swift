//
//  SoftwareNotchGeometryTests.swift
//  CascadeKit
//

import CoreGraphics
import AppKit
import Testing
@testable import CascadeKit

/// SoftwareNotchGeometryTests keeps the software bump, compact activity band,
/// and expanded droplet independent so changing one cannot distort the others.
struct SoftwareNotchGeometryTests {

    @Test
    func activityContextKeepsOptionalHardwareWidthSourceCompatibility() {
        let implicit = NotchActivityViewContext(
            presentation : .expanded,
            availableSize: CGSize(width: 100, height: 40)
        )
        let explicit = NotchActivityViewContext(
            presentation      : .expanded,
            availableSize     : CGSize(width: 100, height: 40),
            hardwareNotchWidth: nil
        )

        #expect(implicit.hardwareNotchWidth == nil)
        #expect(explicit.hardwareNotchWidth == nil)
    }

    private let configuration = NotchConfiguration.default
    private let metrics       = SoftwareNotchMetrics()

    @Test
    func approvedMetricsKeepRestCompactAndDropletMeasurementsIndependent() {
        #expect(metrics.restingSize == CGSize(width: 96, height: 8))
        #expect(metrics.compactHeight == 32)
        #expect(metrics.compactCenterGap == 24)
        #expect(metrics.neckWidth == 12)
        #expect(metrics.bodyOffset == 8)
    }

    @Test
    func compactContentKeepsHardwareReservationButUsesTheSoftwareCenterGap() {
        let hardware = NotchGeometry.resolve(
            configuration           : configuration,
            restingHalfWidth        : 100,
            restingHeight           : 32,
            compactLeadingExtension : 40,
            compactTrailingExtension: 40,
            compactCenterHalfWidth  : 100,
            compactProgress         : 1,
            resolvedHeight          : 32,
            leadingProgress         : 0,
            trailingProgress        : 0
        )
        let software = NotchGeometry.resolve(
            configuration           : configuration,
            restingHalfWidth        : metrics.restingSize.width / 2
                - configuration.restingTopCornerRadius,
            restingHeight           : metrics.restingSize.height,
            compactLeadingExtension : 40,
            compactTrailingExtension: 40,
            compactCenterHalfWidth  : metrics.compactCenterGap / 2,
            compactProgress         : 1,
            resolvedHeight          : metrics.compactHeight,
            leadingProgress         : 0,
            trailingProgress        : 0
        )

        #expect(hardware.width == 280)
        #expect(software.width == 104)
        #expect(hardware.width - 80 == 200)
        #expect(software.width - 80 == 24)
        #expect(hardware.height == software.height)
    }

    @Test(arguments: [ExternalNotchStyle.notch, .dynamicIsland])
    func bothSoftwareStylesRestInsideTheExactNinetySixByEightBounds(style: ExternalNotchStyle) {
        let resting  = softwareRestingGeometry
        let ordinary = CGPath.notch(
            geometry: resting,
            centerX : 100,
            topY    : 80
        )
        let path = style == .dynamicIsland
            ? CGPath.softwareNotchDroplet(
                resting          : ordinary,
                bodyGeometry     : resting,
                centerX          : 100,
                topY             : 80,
                expansionProgress: 0,
                metrics          : metrics
            )
            : ordinary

        #expect(path.boundingBoxOfPath == CGRect(x: 52, y: 72, width: 96, height: 8))
    }

    @Test(arguments: [CGFloat(0), 0.5, 1])
    func dropletPathIsFiniteContainedAndKeepsTheTopBump(progress: CGFloat) {
        let height = metrics.restingSize.height
            + (configuration.expandedHeight - metrics.restingSize.height) * progress
        let body = NotchGeometry.resolve(
            configuration    : configuration,
            restingHalfWidth : metrics.restingSize.width / 2,
            restingHeight    : metrics.restingSize.height,
            expandedHalfWidth: configuration.expandedHalfWidth,
            resolvedHeight   : height,
            leadingProgress  : progress,
            trailingProgress : progress
        )
        let resting = CGPath.notch(
            geometry: softwareRestingGeometry,
            centerX : 300,
            topY    : 240
        )
        let path = CGPath.softwareNotchDroplet(
            resting          : resting,
            bodyGeometry     : body,
            centerX          : 300,
            topY             : 240,
            expansionProgress: progress,
            metrics          : metrics
        )
        let bounds = path.boundingBoxOfPath

        #expect(bounds.minX.isFinite)
        #expect(bounds.minY.isFinite)
        #expect(bounds.maxX.isFinite)
        #expect(bounds.maxY.isFinite)
        #expect(CGRect(x: 0, y: 0, width: 600, height: 240).contains(bounds))
        #expect(path.contains(CGPoint(x: 300, y: 239)))

        if progress == 1 {
            #expect(path.contains(CGPoint(x: 300, y: 228)))
        }

        let expectedHeight = progress == 0
            ? metrics.restingSize.height
            : height + (metrics.restingSize.height + metrics.bodyOffset) * progress
        #expect(bounds.height == expectedHeight)
    }

    @Test
    func returningCompactGeometryReachesTheRestingBumpInsteadOfAThirtyTwoPointBlock() {
        let geometry = NotchGeometry.resolve(
            configuration           : configuration,
            restingHalfWidth        : metrics.restingSize.width / 2
                - configuration.restingTopCornerRadius,
            restingHeight           : metrics.restingSize.height,
            compactLeadingExtension : 0,
            compactTrailingExtension: 0,
            compactCenterHalfWidth  : metrics.compactCenterGap / 2,
            compactProgress         : 0,
            resolvedHeight          : metrics.restingSize.height,
            leadingProgress         : 0,
            trailingProgress        : 0
        )
        let path = CGPath.notch(
            geometry: geometry,
            centerX : 100,
            topY    : 80
        )

        #expect(path.boundingBoxOfPath == CGRect(x: 52, y: 72, width: 96, height: 8))
    }

    @Test
    @MainActor
    func productionHostSharesTheDropletPathWithMaskAndHitTesting() throws {
        let host     = NotchHostView(frame: CGRect(x: 0, y: 0, width: 600, height: 180))
        let geometry = NotchGeometry(
            leftExtent        : 180,
            rightExtent       : 180,
            height            : 140,
            bottomCornerRadius: 36,
            topCornerRadius   : 16
        )
        host.apply(
            geometry       : geometry,
            centerX        : 300,
            topY           : 180,
            isChromeVisible: true,
            softwareDroplet: true,
            dropletProgress: 1,
            softwareMetrics: metrics
        )
        let shape = try #require(host.layer?.sublayers?.first as? CAShapeLayer)
        let path  = try #require(shape.path)
        let mask  = try #require(host.subviews.compactMap {
            $0.layer?.mask as? CAShapeLayer
        }.first?.path)

        #expect(mask.boundingBoxOfPath == path.boundingBoxOfPath)

        for point in [
            CGPoint(x: 300, y: 179),
            CGPoint(x: 300, y: 165),
            CGPoint(x: 300, y: 20),
            CGPoint(x: 80, y: 100)
        ] {
            #expect(host.containsInteractivePoint(point) == path.contains(point))
        }
    }

    @Test
    @MainActor
    func renderProductionPathComparisonWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["CASCADE_RENDER_SOFTWARE_NOTCH_ARTIFACT"] == "1" else {
            return
        }

        let cellSize = CGSize(width: 480, height: 220)
        let rows    : [(String, ExternalNotchStyle, Bool)] = [
            ("Notch · no live", .notch, false),
            ("Notch · live", .notch, true),
            ("Dynamic Island · no live", .dynamicIsland, false),
            ("Dynamic Island · live", .dynamicIsland, true)
        ]
        let columns: [(String, CGFloat)] = [
            ("Rest", 0),
            ("Half", 0.5),
            ("Expanded", 1)
        ]
        let imageSize = CGSize(
            width : cellSize.width * CGFloat(columns.count),
            height: cellSize.height * CGFloat(rows.count)
        )
        let image = NSImage(size: imageSize, flipped: false) { bounds in
            NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
            bounds.fill()

            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, column) in columns.enumerated() {
                    let origin = CGPoint(
                        x: CGFloat(columnIndex) * cellSize.width,
                        y: imageSize.height - CGFloat(rowIndex + 1) * cellSize.height
                    )
                    NSColor(calibratedWhite: rowIndex.isMultiple(of: 2) ? 0.86 : 0.90, alpha: 1).setFill()
                    CGRect(origin: origin, size: cellSize).insetBy(dx: 6, dy: 6).fill()

                    let path = productionPath(
                        style   : row.1,
                        hasLive : row.2,
                        progress: column.1,
                        canvas  : cellSize
                    )
                    var translation = CGAffineTransform(
                        translationX: origin.x,
                        y           : origin.y
                    )
                    if let translated = path.copy(using: &translation) {
                        NSColor.black.setFill()
                        NSBezierPath(cgPath: translated).fill()
                    }

                    let label = "\(row.0) · \(column.0)" as NSString
                    label.draw(
                        at            : CGPoint(x: origin.x + 14, y: origin.y + 12),
                        withAttributes: [
                            .font           : NSFont.systemFont(ofSize: 13, weight: .medium),
                            .foregroundColor: NSColor(calibratedWhite: 0.28, alpha: 1)
                        ]
                    )
                }
            }
            return true
        }

        let representation = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init))
        let png            = try #require(representation.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/cascade-software-notch-comparison.png"))
    }

    private var softwareRestingGeometry: NotchGeometry {
        let attachment = min(
            configuration.restingTopCornerRadius,
            metrics.restingSize.height / 2,
            metrics.restingSize.width / 2
        )
        return NotchGeometry.resolve(
            configuration   : configuration,
            restingHalfWidth: metrics.restingSize.width / 2 - attachment,
            restingHeight   : metrics.restingSize.height,
            resolvedHeight  : metrics.restingSize.height,
            leadingProgress : 0,
            trailingProgress: 0
        )
    }

    @MainActor
    private func productionPath(
        style   : ExternalNotchStyle,
        hasLive : Bool,
        progress: CGFloat,
        canvas  : CGSize
    ) -> CGPath {
        let compactProgress = hasLive ? 1 - progress : 0
        let initialHeight   = hasLive ? metrics.compactHeight : metrics.restingSize.height
        let height          = initialHeight
            + (configuration.expandedHeight - initialHeight) * progress
        let geometry = NotchGeometry.resolve(
            configuration           : configuration,
            restingHalfWidth        : metrics.restingSize.width / 2
                - configuration.restingTopCornerRadius,
            restingHeight           : metrics.restingSize.height,
            compactLeadingExtension : configuration.compactActivityExtension * compactProgress,
            compactTrailingExtension: configuration.compactActivityExtension * compactProgress,
            compactCenterHalfWidth  : metrics.compactCenterGap / 2,
            compactProgress         : compactProgress,
            expandedHalfWidth       : configuration.expandedHalfWidth,
            resolvedHeight          : height,
            leadingProgress         : progress,
            trailingProgress        : progress
        )

        let host = NotchHostView(frame: CGRect(origin: .zero, size: canvas))
        host.apply(
            geometry       : geometry,
            centerX        : canvas.width / 2,
            topY           : canvas.height - 4,
            isChromeVisible: true,
            softwareDroplet: style == .dynamicIsland && !hasLive,
            dropletProgress: progress,
            softwareMetrics: metrics
        )
        return (host.layer?.sublayers?.first as? CAShapeLayer)?.path ?? CGMutablePath()
    }
}
