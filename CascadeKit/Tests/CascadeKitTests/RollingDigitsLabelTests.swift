//
//  RollingDigitsLabelTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import QuartzCore
import Testing
@testable import CascadeKit

@MainActor
struct RollingDigitsLabelTests {

    private let font  = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let color = NSColor.white.withAlphaComponent(0.55)

    private func label() -> RollingDigitsLabelView {
        RollingDigitsLabelView(
            font : font,
            color: color
        )
    }

    private func glyphs(of label: RollingDigitsLabelView) -> [CATextLayer] {
        label.layer?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
    }

    private func rolling(in label: RollingDigitsLabelView) -> [String] {
        glyphs(of: label)
            .filter { $0.animation(forKey: kCATransition) != nil }
            .compactMap { $0.string as? String }
    }

    @Test
    func onlyChangedDigitsRoll() {
        let label = label()

        label.show("1:23", countsDown: false, animates: true)
        #expect(glyphs(of: label).count == 4)
        #expect(rolling(in: label).isEmpty)

        label.show("1:24", countsDown: false, animates: true)
        let glyphs = glyphs(of: label)

        #expect(rolling(in: label) == ["4"])
        #expect(glyphs.last?.animation(forKey: kCATransition) != nil)
        #expect(glyphs.dropLast().allSatisfy { $0.animation(forKey: kCATransition) == nil })
    }

    @Test
    func everyChangedDigitRollsAndTheColonStays() {
        let label = label()
        label.show("0:59", countsDown: false, animates: true)
        let width = label.intrinsicContentSize.width

        label.show("1:00", countsDown: false, animates: true)

        #expect(rolling(in: label) == ["1", "0", "0"])
        #expect(label.intrinsicContentSize.width == width)
    }

    @Test
    func theRollFollowsTheDirectionOfTheCount() throws {
        let up   = label()
        let down = label()

        up.show("0:01", countsDown: false, animates: true)
        up.show("0:02", countsDown: false, animates: true)
        down.show("0:02", countsDown: true, animates: true)
        down.show("0:01", countsDown: true, animates: true)

        let rise = try #require(glyphs(of: up).last?.animation(forKey: kCATransition) as? CATransition)
        let drop = try #require(glyphs(of: down).last?.animation(forKey: kCATransition) as? CATransition)

        #expect(rise.type == .push)
        #expect(rise.subtype == .fromBottom)
        #expect(drop.subtype == .fromTop)
        #expect(rise.duration == 0.35)
    }

    @Test
    func anUnchangedValueDoesNothing() {
        let label = label()
        label.show("1:00", countsDown: false, animates: true)
        label.show("1:01", countsDown: false, animates: true)
        glyphs(of: label).forEach { $0.removeAllAnimations() }

        label.show("1:01", countsDown: false, animates: true)

        #expect(rolling(in: label).isEmpty)
    }

    @Test
    func aNewLengthRelaysWithoutAnimation() {
        let label = label()
        label.show("1:00", countsDown: false, animates: true)
        let width = label.intrinsicContentSize.width

        label.show("10:00", countsDown: false, animates: true)

        #expect(glyphs(of: label).count == 5)
        #expect(rolling(in: label).isEmpty)
        #expect(label.intrinsicContentSize.width > width)
    }

    @Test
    func reduceMotionSetsTextInPlace() {
        let label = label()
        label.show("10:00", countsDown: false, animates: true)

        label.show("10:01", countsDown: false, animates: false)

        #expect(rolling(in: label).isEmpty)
        #expect(glyphs(of: label).last?.string as? String == "1")
    }

    @Test
    func colorAndFontAreApplied() {
        let label = RollingDigitsLabelView(
            font : .systemFont(ofSize: 17, weight: .bold),
            color: NSColor(srgbRed: 1, green: 0.77, blue: 0.33, alpha: 1)
        )
        label.show("2:30", countsDown: true, animates: true)

        for glyph in glyphs(of: label) {
            #expect(glyph.fontSize == 17)
            #expect(glyph.foregroundColor == NSColor(srgbRed: 1, green: 0.77, blue: 0.33, alpha: 1).cgColor)
        }
    }

    @Test
    func restylingRecolorsTheGlyphsAndMeasuresAgain() {
        let label = label()
        label.show("12:34", countsDown: false, animates: true)
        let width = label.intrinsicContentSize.width

        label.restyle(
            font : .monospacedDigitSystemFont(ofSize: 22, weight: .regular),
            color: .red
        )

        #expect(glyphs(of: label).allSatisfy { $0.fontSize == 22 })
        #expect(glyphs(of: label).allSatisfy { $0.foregroundColor == NSColor.red.cgColor })
        #expect(label.intrinsicContentSize.width > width)
    }

    @Test
    func voiceOverReadsTheCurrentText() {
        let label = label()

        #expect(label.isAccessibilityElement())
        #expect(label.accessibilityRole() == .staticText)

        label.show("1:24", countsDown: true, animates: true)
        #expect(label.accessibilityValue() as? String == "1:24")

        label.show("1:23", countsDown: true, animates: true)
        #expect(label.accessibilityValue() as? String == "1:23")
        #expect(label.accessibilityLabel() == "1:23")
    }

    @Test
    func theLabelNeverCatchesTheMouse() {
        let label = label()
        label.show("1:00", countsDown: false, animates: true)

        #expect(label.hitTest(NSPoint(x: 1, y: 1)) == nil)
        #expect(label.layer?.masksToBounds == true)
    }

    @Test
    func pluginFontsAndColorsConvertToAppKit() {
        let font = PluginFont(
            size  : 20,
            weight: .bold
        ).nsFont

        #expect(font.pointSize == 20)
        #expect(PluginFont(style: .caption).nsFont.pointSize == NSFont.preferredFont(forTextStyle: .caption1).pointSize)

        let color = PluginColor(red: 1, green: 0.5, blue: 0.25, opacity: 0.5).nsColor
        #expect(color == NSColor(srgbRed: 1, green: 0.5, blue: 0.25, alpha: 0.5))
    }

    @Test
    func anyFontCanBeMadeToUseEqualDigits() {
        func width(_ digit: String, _ font: NSFont) -> CGFloat {
            (digit as NSString).size(withAttributes: [.font: font]).width
        }

        let proportional = NSFont.systemFont(ofSize: 20)
        let tabular      = proportional.monospacingDigits

        #expect(width("1", tabular) == width("0", tabular))
        #expect(tabular.pointSize == 20)
    }

    @Test
    func timerTextFormatsLikeTheSystemTimer() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let end   = start.addingTimeInterval(5_400)

        func text(
            countsDown: Bool,
            at offset  : TimeInterval
        ) -> String {
            TimerText.text(
                start     : start,
                end       : end,
                countsDown: countsDown,
                at        : start.addingTimeInterval(offset),
                locale    : Locale(identifier: "en_US")
            )
        }

        #expect(text(countsDown: true, at: 1) == "1:29:59")
        #expect(text(countsDown: false, at: 65) == "1:05")
        #expect(text(countsDown: true, at: 9_999) == "0:00")
        #expect(text(countsDown: false, at: 9_999) == "1:30:00")
        #expect(text(countsDown: true, at: -30) == "1:30:00")
        #expect(text(countsDown: false, at: -30) == "0:00")
    }

    /// aCountUpPastADayKeepsCounting is an indefinite session's elapsed time: the hours keep
    /// growing past 24 and past 99 instead of wrapping or freezing.
    @Test
    func aCountUpPastADayKeepsCounting() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let end   = start.addingTimeInterval(365 * 86_400)

        func text(at offset: TimeInterval) -> String {
            TimerText.text(
                start     : start,
                end       : end,
                countsDown: false,
                at        : start.addingTimeInterval(offset),
                locale    : Locale(identifier: "en_US")
            )
        }

        #expect(text(at: 30 * 3_600) == "30:00:00")
        #expect(text(at: 30 * 3_600 + 61) == "30:01:01")
        #expect(text(at: 100 * 3_600) == "100:00:00")
    }

    @Test
    func theTimerScheduleTicksWholeSecondsAndStopsAtTheEnd() {
        let start    = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let schedule = TimerTimelineSchedule(
            start: start,
            end  : start.addingTimeInterval(3)
        )

        func entries(from offset: TimeInterval) -> [TimeInterval] {
            schedule
                .entries(from: start.addingTimeInterval(offset), mode: .normal)
                .map { $0.timeIntervalSince(start) }
        }

        #expect(entries(from: 0.5) == [0.5, 1, 2, 3])
        #expect(entries(from: -2) == [-2, 0, 1, 2, 3])
        #expect(entries(from: 10) == [10])
    }
}
