//
//  NotchSizeCalibrationTests.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

@MainActor
struct NotchSizeCalibrationTests {

    private let display = ActiveDisplay(
        displayID   : 42,
        frame       : CGRect(x: 1470, y: -200, width: 1470, height: 956),
        backingScale: 2,
        notch       : HardwareNotch(isPresent: true, size: CGSize(width: 179, height: 34))
    )

    @Test
    func arrowChangesPreviewWithoutSavingAndEscapeRestoresThePreviousSize() {
        let presenter = RecordingCalibrationPresenter()
        let store     = RecordingNotchSizeStore()
        store.sizes[42] = CGSize(width: 180, height: 34)
        let calibration = NotchSizeCalibration(presenter: presenter, store: store)
        calibration.begin(on: display, size: CGSize(width: 180, height: 34))

        presenter.onStep?(1, 0)
        #expect(calibration.size(for: display) == CGSize(width: 181, height: 34))
        #expect(presenter.size == CGSize(width: 181, height: 34))
        #expect(store.sizes[42] == CGSize(width: 180, height: 34))

        presenter.onFinish?(false)
        #expect(!calibration.isActive)
        #expect(calibration.size(for: display) == CGSize(width: 180, height: 34))
        #expect(presenter.hideCount == 1)
    }

    @Test
    func returnSavesOnlyTheCalibratedDisplay() {
        let presenter = RecordingCalibrationPresenter()
        let store     = RecordingNotchSizeStore()
        store.sizes[7] = CGSize(width: 220, height: 32)
        let calibration = NotchSizeCalibration(presenter: presenter, store: store)
        calibration.begin(on: display, size: display.notch.size)

        presenter.onStep?(-1, 1)
        presenter.onFinish?(true)
        #expect(store.sizes[42] == CGSize(width: 178, height: 35))
        #expect(store.sizes[7] == CGSize(width: 220, height: 32))
        #expect(!calibration.isActive)
    }

    @Test
    func invalidInputAndRepeatedBoundaryStepsCannotCorruptGeometry() {
        let presenter        = RecordingCalibrationPresenter()
        let calibration      = NotchSizeCalibration(presenter: presenter, store: RecordingNotchSizeStore())
        var changes          = 0
        calibration.onChange = { changes += 1 }
        calibration.begin(on: display, size: display.notch.size)

        presenter.onStep?(.nan, .infinity)
        #expect(calibration.size(for: display) == display.notch.size)

        presenter.onStep?(-10_000, -10_000)
        let smallest    = calibration.size(for: display)
        let changeCount = changes
        presenter.onStep?(-1, -1)
        #expect(changes == changeCount)
        #expect(smallest?.width == 80)
        #expect(smallest?.height == 16)

        presenter.onStep?(10_000, 10_000)
        #expect(calibration.size(for: display) == CGSize(width: 400, height: 80))
    }

    @Test
    func savedDimensionsFollowTheSameDisplayWhenItsRuntimeIDChanges() throws {
        let suite    = "Cascade.CalibrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NotchSizePreferences(defaults: defaults, displayIdentity: { _ in "display-a" })
        store.setSize(CGSize(width: 181, height: 34), for: 42)

        var resolutions = 0
        let restored    = NotchSizePreferences(defaults: defaults, displayIdentity: { id in
            resolutions += 1
            return id == 71 ? "display-a" : "display-b"
        })

        #expect(restored.size(for: 71) == CGSize(width: 181, height: 34))
        #expect(restored.size(for: 42) == nil)
        #expect(restored.size(for: 71) == CGSize(width: 181, height: 34))
        #expect(restored.size(for: 42) == nil)
        #expect(resolutions == 2)
    }
}
