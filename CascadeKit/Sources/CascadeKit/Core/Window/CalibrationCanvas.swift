//
//  CalibrationCanvas.swift
//  CascadeKit
//

import AppKit
import QuartzCore

/// CalibrationCanvas updates one guide path and a small instruction panel only
/// when a key changes the size. Guides touch the straight sides and underside;
/// the small flares at the bezel remain outside the vertical guides.
@MainActor
final class CalibrationCanvas: NSView {

    var onStep  : ((CGFloat, CGFloat) -> Void)?
    var onFinish: ((Bool) -> Void)?
    var scale   : CGFloat = 2

    private let guides       = CAShapeLayer()
    private let instructions = NSStackView()
    private let dimensions   = NSTextField(labelWithString: "")

    private var guideGeometry: NotchGeometry?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        guides.strokeColor = NSColor(srgbRed: 1, green: 0.12, blue: 0.12, alpha: 1).cgColor
        guides.fillColor   = nil
        layer?.addSublayer(guides)

        instructions.orientation            = .vertical
        instructions.spacing                = 12
        instructions.edgeInsets             = NSEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)
        instructions.wantsLayer             = true
        instructions.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.97).cgColor
        instructions.layer?.cornerRadius    = 12
        instructions.appearance             = NSAppearance(named: .darkAqua)
        addSubview(instructions)

        let title = NSTextField(labelWithString: String(localized: "Adjust the notch base", bundle: .module))
        title.font      = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        instructions.addArrangedSubview(title)

        dimensions.font      = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        dimensions.textColor = .white
        instructions.addArrangedSubview(dimensions)

        let controls = NSStackView(views: [
            button("←", action: #selector(narrower), label: String(localized: "Decrease Width", bundle: .module)),
            button("→", action: #selector(wider), label: String(localized: "Increase Width", bundle: .module)),
            button("↑", action: #selector(shorter), label: String(localized: "Decrease Height", bundle: .module)),
            button("↓", action: #selector(taller), label: String(localized: "Increase Height", bundle: .module))
        ])
        controls.spacing = 10
        instructions.addArrangedSubview(controls)

        let help = NSTextField(labelWithString: String(localized: "← → Width   ·   ↑ ↓ Height   ·   Shift: 5 pt", bundle: .module))
        help.font      = .systemFont(ofSize: 12)
        help.textColor = .lightGray
        instructions.addArrangedSubview(help)

        let actions = NSStackView(views: [
            button(
                String(localized: "Cancel · Esc", bundle: .module),
                action: #selector(cancelCalibration),
                label : String(localized: "Cancel Adjustment", bundle: .module)
            ),
            button(
                String(localized: "Save · Return", bundle: .module),
                action: #selector(saveCalibration),
                label : String(localized: "Save Size", bundle: .module)
            )
        ])
        actions.spacing = 12
        instructions.addArrangedSubview(actions)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()

        let size           = instructions.fittingSize
        instructions.frame = CGRect(
            x     : 24,
            y     : 32,
            width : max(420, size.width),
            height: size.height
        )

        updateGuides()
    }

    func update(size: CGSize) {
        dimensions.stringValue = String(
            localized: "Width \(Int(size.width)) pt   ×   Height \(Int(size.height)) pt",
            bundle   : .module
        )
        needsLayout            = true
    }

    func update(geometry: NotchGeometry) {
        guideGeometry = geometry
        updateGuides()
    }

    private func updateGuides() {
        guard let geometry = guideGeometry else { return }

        let left   = bounds.midX - geometry.leftExtent
        let right  = bounds.midX + geometry.rightExtent
        let bottom = bounds.maxY - geometry.height
        let path   = CGMutablePath()

        for guideX in [left, right] {
            path.move(to: CGPoint(x: guideX, y: bounds.minY))
            path.addLine(to: CGPoint(x: guideX, y: bounds.maxY))
        }
        path.move(to: CGPoint(x: bounds.minX, y: bottom))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bottom))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guides.frame         = bounds
        guides.contentsScale = scale
        guides.lineWidth     = 1
        guides.path          = path
        CATransaction.commit()
    }

    private func button(
        _ title: String,
        action : Selector,
        label  : String
    ) -> NSButton {
        let button = NSButton(
            title : title,
            target: self,
            action: action
        )
        button.bezelStyle = .rounded
        button.setAccessibilityLabel(label)
        return button
    }

    @objc
    private func narrower() { onStep?(-1, 0) }

    @objc
    private func wider() { onStep?(1, 0) }

    @objc
    private func shorter() { onStep?(0, -1) }

    @objc
    private func taller() { onStep?(0, 1) }

    @objc
    private func cancelCalibration() { onFinish?(false) }

    @objc
    private func saveCalibration() { onFinish?(true) }
}
