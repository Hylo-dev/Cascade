//
//  RollingDigitsLabelView.swift
//  CascadeKit
//

import AppKit
import QuartzCore

/// RollingDigitsLabelView rolls only the digits that change, the way SwiftUI's `numericText`
/// does, but in the render server. That content transition re-laid the text out on every
/// display frame of each roll: measured at ~16 % of a core for Music's two progress labels
/// ticking once a second, against ~0.2 % for static text. Here a tick sets the string of the
/// one or two digit layers that changed and a push transition moves the old digit out and the
/// new one in; the app does nothing in between.
///
/// It lays one text layer per character side by side. Digits share one width, so a roll never
/// moves its neighbours (a font that does not draw equal digits must be given
/// `monospacingDigits`); a string of a new length is laid out again without animation.
@MainActor
public final class RollingDigitsLabelView: NSView {

    private var font : NSFont
    private var color: NSColor

    private var glyphs: [CATextLayer] = []
    private var text   = ""
    private var widths: [Character: CGFloat] = [:]

    private var lineHeight: CGFloat { ceil(font.ascender - font.descender) }

    public init(
        font : NSFont,
        color: NSColor
    ) {
        self.font  = font
        self.color = color
        super.init(frame: .zero)

        wantsLayer = true
        // A push transition renders outside the layer it runs on, so the
        // clip that keeps a rolling digit inside its line sits on the parent.
        layer?.masksToBounds = true

        // The glyph layers are not accessibility elements, so the view itself is the one
        // static text VoiceOver reads; `show` keeps its value current.
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    public required init?(coder: NSCoder) { nil }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(text.reduce(0) { $0 + width(of: $1) }), height: lineHeight)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        let scale = window?.backingScaleFactor ?? 2
        glyphs.forEach { $0.contentsScale = scale }
    }

    public override func layout() {
        super.layout()
        placeGlyphs()
    }

    /// show makes `text` the label's text. Only the characters that differ roll, and only when
    /// `animates` is set and the length did not change.
    public func show(
        _ text    : String,
        countsDown: Bool,
        animates  : Bool
    ) {
        guard text != self.text else { return }

        let oldCharacters = Array(self.text)
        let newCharacters = Array(text)
        let isRelaid      = oldCharacters.count != newCharacters.count

        self.text = text

        // Only on a change, after the guard: a tick that shows the same text costs nothing.
        setAccessibilityValue(text)
        setAccessibilityLabel(text)

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

    /// restyle gives the label another font or color, without a roll: a node whose modifiers
    /// changed keeps its label, and the glyphs, their measured widths and the label's size
    /// follow. Calling it with the style the label already has does nothing.
    public func restyle(
        font : NSFont,
        color: NSColor
    ) {
        guard font != self.font || color != self.color else { return }

        let isResized = font != self.font

        self.font  = font
        self.color = color

        if isResized {
            widths.removeAll(keepingCapacity: true)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for glyph in glyphs {
            glyph.font            = font
            glyph.fontSize        = font.pointSize
            glyph.foregroundColor = color.cgColor
        }
        CATransaction.commit()

        if isResized {
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
        glyph.foregroundColor = color.cgColor
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
