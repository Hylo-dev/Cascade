//
//  MusicTimeLabelChecks.swift
//  Cascade
//

#if MUSIC_TIME_LABEL_TESTS
import AppKit

@main
private enum MusicTimeLabelChecks {

    @MainActor
    static func main() {
        do {
            let label = MusicTimeLabelView(
                font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            )

            func glyphs() -> [CATextLayer] {
                label.layer?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
            }

            func rolling() -> [String] {
                glyphs()
                    .filter { $0.animation(forKey: kCATransition) != nil }
                    .compactMap { $0.string as? String }
            }

            label.show(
                "0:59",
                countsDown: false,
                animates  : true
            )
            precondition(
                glyphs().count == 4 && rolling().isEmpty,
                "The first value appears without rolling"
            )
            let width = label.intrinsicContentSize.width

            label.show(
                "1:00",
                countsDown: false,
                animates  : true
            )
            precondition(
                rolling() == ["1", "0", "0"],
                "Only the three changed digits roll; the colon stays"
            )
            precondition(
                label.intrinsicContentSize.width == width,
                "Equal-width digits keep the label still"
            )

            glyphs().forEach { $0.removeAllAnimations() }
            label.show(
                "1:00",
                countsDown: false,
                animates  : true
            )
            precondition(rolling().isEmpty, "An unchanged value does nothing")

            label.show(
                "10:00",
                countsDown: false,
                animates  : true
            )
            precondition(
                glyphs().count == 5 && rolling().isEmpty,
                "A new length is laid out again, not rolled"
            )

            glyphs().forEach { $0.removeAllAnimations() }
            label.show(
                "10:01",
                countsDown: false,
                animates  : false
            )
            precondition(
                rolling().isEmpty && glyphs().last?.string as? String == "1",
                "Reduce Motion and scrubbing change digits in place"
            )

            print("Music time label: 6 behavior checks passed")
        }
    }
}

#endif
