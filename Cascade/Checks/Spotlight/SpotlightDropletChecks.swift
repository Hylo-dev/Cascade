//
//  SpotlightDropletChecks.swift
//  Cascade
//

#if SPOTLIGHT_DROPLET_TESTS
import AppKit
import CoreGraphics
import Foundation

@main
@MainActor
private enum SpotlightDropletChecks {

    struct Failure: Error {

        let message: String
    }

    static func main() {
        do {
            try checkGlobalLandingGeometry()
            try checkDetachBeforeExpansion()
            try checkContinuousFiniteMotion()
            try checkReducedMotion()
            try checkInvalidNativeSize()
            try checkSoftwareAnchorMetrics()
            try checkNativeWindowHandoff()

            print("Spotlight droplet checks passed (7 behaviors)")
        } catch {
            print("FAILED: \(error)")
            exit(1)
        }
    }

    /// checkGlobalLandingGeometry catches screen-origin loss and an inverted AppKit y axis.
    private static func checkGlobalLandingGeometry() throws {
        let layout = SpotlightDropletLayout(
            screenFrame      : CGRect(x: -1280, y: 160, width: 1280, height: 800),
            hardwareNotchSize: CGSize(width: 180, height: 32),
            nativeSize       : CGSize(width: 520, height: 87)
        )
        try require(
            layout.landingBounds == CGRect(x: -900, y: 809, width: 520, height: 87),
            "Landing must preserve the global display origin and 32-point gap below the notch"
        )
        try require(
            layout.canvasBounds.contains(layout.landingBounds)
                && layout.canvasBounds.contains(layout.sourceBounds)
                && layout.canvasBounds.width < 600
                && layout.canvasBounds.height < 220,
            "One fixed, small canvas must contain both surfaces without covering the screen"
        )

        let narrowLayout = SpotlightDropletLayout(
            screenFrame      : CGRect(x: 0, y: 0, width: 320, height: 200),
            hardwareNotchSize: CGSize(width: 180, height: 32),
            nativeSize       : CGSize(width: 800, height: 87)
        )
        try require(
            narrowLayout.landingBounds == CGRect(x: 24, y: 49, width: 272, height: 87),
            "A narrow display must keep 24-point side margins"
        )
    }

    /// checkDetachBeforeExpansion catches a field-shaped surface appearing while still tethered.
    private static func checkDetachBeforeExpansion() throws {
        let timeline = makeTimeline()

        for millisecond in 0...180 {
            let frame = timeline.frame(at: Double(millisecond) / 1000)
            try require(
                frame.dropletBounds.width <= 80,
                "The gathering and falling drop must remain compact until detachment"
            )
        }

        try require(
            timeline.frame(at: 0.180).isDetached,
            "The neck must release within 180 ms so detachment feels immediate"
        )

        for millisecond in 0...520 {
            let frame = timeline.frame(at: Double(millisecond) / 1000)
            if frame.dropletBounds.width > 80 {
                try require(
                    frame.isDetached
                        && frame.sourceBounds.minY - frame.dropletBounds.maxY > frame.mergeSpacing,
                    "Horizontal expansion requires physical separation beyond native glass merging"
                )
            }
        }

        let finalFrame = timeline.frame(at: 0.400)
        try require(
            finalFrame.isComplete && finalFrame.isDetached
                && finalFrame.dropletBounds == CGRect(x: 496, y: 831, width: 520, height: 87),
            "Completion may be delivered only at the exact detached landing frame"
        )
        try require(
            !timeline.frame(at: 0.399).isComplete,
            "Native Spotlight must not be requested before the visual handoff has landed"
        )
    }

    /// checkContinuousFiniteMotion catches phase jumps, late overshoot and invalid sample times.
    private static func checkContinuousFiniteMotion() throws {
        let timeline = makeTimeline()
        var previous = timeline.frame(at: 0)

        for millisecond in 1...600 {
            let frame       = timeline.frame(at: Double(millisecond) / 1000)
            let coordinates = [
                frame.dropletBounds.minX, frame.dropletBounds.minY,
                frame.dropletBounds.width, frame.dropletBounds.height,
                frame.opacity, frame.cornerRadius, frame.mergeSpacing
            ]
            try require(
                coordinates.allSatisfy { $0.isFinite }
                    && frame.dropletBounds.width > 0 && frame.dropletBounds.height > 0,
                "Every animation sample must contain finite, positive geometry"
            )
            try require(
                abs(frame.dropletBounds.width - previous.dropletBounds.width) < 5
                    && abs(frame.dropletBounds.minY - previous.dropletBounds.minY) < 2
                    && abs(frame.mergeSpacing - previous.mergeSpacing) < 0.75
                    && frame.dropletBounds.width <= 520
                    && frame.dropletBounds.midY <= previous.dropletBounds.midY + 0.001,
                "The drop must travel continuously and settle without an upward bounce or width overshoot"
            )
            previous = frame
        }

        for elapsed in [-1.0, .nan, -.infinity, .infinity] {
            let frame = timeline.frame(at: elapsed)
            try require(
                frame.dropletBounds.minY.isFinite && frame.dropletBounds.width.isFinite,
                "Invalid timestamps must not reach Core Animation as NaN geometry"
            )
        }
    }

    /// checkReducedMotion catches accidental travel or the full delay with Reduce Motion enabled.
    private static func checkReducedMotion() throws {
        let timeline = makeTimeline(reducesMotion: true)

        for millisecond in 0...100 {
            let frame = timeline.frame(at: Double(millisecond) / 1000)
            try require(
                frame.dropletBounds == CGRect(x: 496, y: 831, width: 520, height: 87)
                    && frame.isDetached,
                "Reduce Motion must keep the surface at its final bounds from the first frame"
            )
        }

        try require(
            timeline.frame(at: 0.100).isComplete && timeline.duration <= 0.100,
            "Reduce Motion must hand over within 100 ms"
        )
    }

    /// checkInvalidNativeSize catches non-finite AX measurements reaching the overlay.
    private static func checkInvalidNativeSize() throws {
        let layout = SpotlightDropletLayout(
            screenFrame      : CGRect(x: 0, y: 0, width: 1512, height: 982),
            hardwareNotchSize: CGSize(width: 180, height: 32),
            nativeSize       : CGSize(width: CGFloat.nan, height: CGFloat.infinity)
        )
        try require(
            layout.landingBounds == CGRect(x: 496, y: 831, width: 520, height: 87),
            "Unreadable native dimensions must use the known 520 × 87-point capsule"
        )
    }

    /// checkSoftwareAnchorMetrics rejects the historical 180 × 32 fallback on
    /// a software-notch display whose real compact surface is 96 × 8.
    private static func checkSoftwareAnchorMetrics() throws {
        let restingBounds = CGRect(x: 708, y: 974, width: 96, height: 8)
        let layout        = SpotlightDropletLayout(
            screenFrame       : CGRect(x: 0, y: 0, width: 1512, height: 982),
            restingNotchBounds: restingBounds,
            nativeSize        : CGSize(width: 520, height: 87)
        )
        try require(
            layout.hardwareNotchBounds == restingBounds,
            "Software Spotlight must start from the engine's actual 96 × 8 resting bounds"
        )
    }

    private static func checkNativeWindowHandoff() throws {
        guard #available(macOS 26, *) else { return }

        _ = NSApplication.shared
        guard let screen = NSScreen.main else { return }

        let presenter = SpotlightDropletPanel()
        presenter.play(
            at        : SpotlightDisplayAnchor(
                displayID    : 0,
                screen       : screen,
                restingBounds: CGRect(
                    x     : screen.frame.midX - 90,
                    y     : screen.frame.maxY - 32,
                    width : 180,
                    height: 32
                )
            ),
            nativeSize: CGSize(width: 520, height: 87)
        ) { _ in }
        defer { presenter.cancel() }

        guard let window = NSApp.windows.compactMap({ $0 as? SpotlightDropletWindow }).first else {
            throw Failure(message: "A live droplet window is required for the handoff check")
        }

        presenter.yieldToNative()
        try require(
            window.isVisible && window.level.rawValue < 23,
            "Before invoking Spotlight, the glass must be underneath its window even if AX focus is delayed"
        )

        presenter.revealNative()
        try require(
            !window.isVisible,
            "Once native geometry is ready the glass must disappear immediately, without another fade"
        )
    }

    private static func makeTimeline(reducesMotion: Bool = false) -> SpotlightDropletTimeline {
        SpotlightDropletTimeline(
            layout       : SpotlightDropletLayout(
                screenFrame      : CGRect(x: 0, y: 0, width: 1512, height: 982),
                hardwareNotchSize: CGSize(width: 180, height: 32),
                nativeSize       : CGSize(width: 520, height: 87)
            ),
            reducesMotion: reducesMotion
        )
    }

    private static func require(
        _ condition: Bool,
        _ message  : String
    ) throws {
        if !condition {
            throw Failure(message: message)
        }
    }
}

#endif
