//
//  ControllerFixture.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class ControllerFixture {

    let resolver  : MutableDisplayResolver
    let monitor   : RecordingEventMonitor
    let panel     : NotchPanel
    let hostView  : NotchHostView
    let controller: ControllerTestDriver

    let calibrationPresenter = RecordingCalibrationPresenter()
    let sizeStore            = RecordingNotchSizeStore()

    /// point samples the same position below the notch's top across size presets.
    func point(
        x             : CGFloat,
        belowTop depth: CGFloat
    ) -> CGPoint {
        CGPoint(x: x, y: hostView.bounds.maxY - depth)
    }

    init(
        morphEngine         : RecordingMorphEngine? = nil,
        performer           : (any HapticFeedbackPerforming)? = nil,
        reducesMotion       : Bool = false,
        motionPreference    : (() -> Bool)? = nil,
        style               : ExternalNotchStyle = .notch,
        autoGrantExpansions : Bool = true,
        fileDragTopEdgeGuard: (any FileDragTopEdgeGuardOperating)? = nil
    ) {
        let morphEngine = morphEngine ?? RecordingMorphEngine()
        let performer   = performer ?? CountingHapticPerformer()

        let display = ActiveDisplay(
            displayID   : 42,
            frame       : CGRect(x: 0, y: 0, width: 1_000, height: 800),
            backingScale: 2,
            notch       : HardwareNotch(isPresent: true, size: CGSize(width: 200, height: 30))
        )
        let resolver = MutableDisplayResolver(display: display)
        let monitor  = RecordingEventMonitor()
        let hostView = NotchHostView(frame: .zero)
        let panel    = NotchPanel(contentView: hostView)

        self.resolver = resolver
        self.monitor  = monitor
        self.hostView = hostView
        self.panel    = panel

        let activityHost = LiveActivityHost()
        let widgetHost   = WidgetHost()
        let surface      = NotchController(
            configuration       : .default,
            display             : display,
            morphEngine         : morphEngine,
            panel               : panel,
            hostView            : hostView,
            windowPinner        : NoOpWindowPinner(),
            hoverFeedback       : HoverFeedback(performer: performer),
            sizeCalibration     : NotchSizeCalibration(presenter: calibrationPresenter, store: sizeStore),
            activityHost        : activityHost,
            widgetHost          : widgetHost,
            fileDragTopEdgeGuard: fileDragTopEdgeGuard,
            reducesMotion       : { motionPreference?() ?? reducesMotion }
        )

        self.controller = ControllerTestDriver(
            surface            : surface,
            activityHost       : activityHost,
            widgetHost         : widgetHost,
            resolver           : resolver,
            monitor            : monitor,
            style              : style,
            autoGrantExpansions: autoGrantExpansions
        )
    }
}
