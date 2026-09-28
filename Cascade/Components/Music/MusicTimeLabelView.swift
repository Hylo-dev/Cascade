//
//  MusicTimeLabelView.swift
//  Cascade
//

import AppKit
import QuartzCore
import SwiftUI

/// MusicTimeLabelView lays one text layer per character side by side.
/// Digits share one width, so a roll never moves its neighbours; a string of a
/// new length is laid out again without animation.
@MainActor
final class MusicTimeLabelView: NSView {

    private let font : NSFont
    private let color = NSColor.white.withAlphaComponent(0.55).cgColor

    private var glyphs: [CATextLayer] = []
    private var text   = ""
    private var widths: [Character: CGFloat] = [:]

    private var lineHeight: CGFloat { ceil(font.ascender - font.descender) }

    init(font: NSFont) {
        self.font = font
        super.init(frame: .zero)

        wantsLayer = true
        // A push transition renders outside the layer it runs on, so the
        // clip that keeps a rolling digit inside its line sits on the parent.
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(text.reduce(0) { $0 + width(of: $1) }), height: lineHeight)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        let scale = window?.backingScaleFactor ?? 2
        glyphs.forEach { $0.contentsScale = scale }
    }

    override func layout() {
        super.layout()
        placeGlyphs()
    }

    func show(
        _ text    : String,
        countsDown: Bool,
        animates  : Bool
    ) {
        guard text != self.text else { return }

        let oldCharacters = Array(self.text)
        let newCharacters = Array(text)
        let isRelaid      = oldCharacters.count != newCharacters.count

        self.text = text

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if glyphs.count != newCharacters.count {
            glyphs.forEach { $0.removeFromSuperlayer() }
            glyphs = newCharacters.map { _ in makeGlyph() }
            glyphs.forEach { layer?.addSublayer($0) }
        }

        for (index, character) in newCharacters.enumerated() {
            let glyph = glyphs[index]
            guard isRelaid || oldCharacters[index] != character else { continue }

            if animates && !isRelaid {
                let roll = CATransition()
                roll.type           = .push
                // Counting up, the next digit rises from below; counting down,
                // it drops in from above.
                roll.subtype        = countsDown ? .fromTop : .fromBottom
                roll.duration       = 0.35
                roll.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                glyph.add(roll, forKey: kCATransition)
            }
            glyph.string = String(character)
        }
        CATransaction.commit()

        if isRelaid {
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    private func placeGlyphs() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        var originX: CGFloat = 0
        let originY = ((bounds.height - lineHeight) / 2).rounded()
        for (glyph, character) in zip(glyphs, text) {
            let width = self.width(of: character)
            glyph.frame = CGRect(x: originX, y: originY, width: width, height: lineHeight)
            originX += width
        }

        CATransaction.commit()
    }

    private func makeGlyph() -> CATextLayer {
        let glyph = CATextLayer()
        glyph.font            = font
        glyph.fontSize        = font.pointSize
        glyph.foregroundColor = color
        glyph.alignmentMode   = .center
        glyph.contentsScale   = window?.backingScaleFactor ?? 2

        return glyph
    }

    private func width(of character: Character) -> CGFloat {
        if let width = widths[character] { return width }

        let width = ceil((String(character) as NSString).size(withAttributes: [.font: font]).width)
        widths[character] = width
        return width
    }
}
