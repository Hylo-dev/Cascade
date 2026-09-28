//
//  AudioOutputDeviceButton.swift
//  Cascade
//

import AppKit
import CoreAudio

/// AudioOutputDeviceButton carries a typed device ID independently of its
/// localized label. The empty image reserves the current-device check column.
@MainActor
final class AudioOutputDeviceButton: NSButton {

    let deviceID: AudioDeviceID

    init(
        device   : (id: AudioDeviceID, name: String),
        isCurrent: Bool,
        target   : AnyObject,
        action   : Selector
    ) {
        deviceID = device.id
        super.init(frame: .zero)

        title       = device.name
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)

        bezelStyle                      = .recessed
        showsBorderOnlyWhileMouseInside = true
        alignment                       = .left
        imagePosition                   = .imageLeft
        imageHugsTitle                  = true
        font                            = .systemFont(ofSize: NSFont.systemFontSize)
        toolTip                         = device.name
        image = isCurrent ? NSImage(
            systemSymbolName        : "checkmark",
            accessibilityDescription: String(localized: "Selected")
        ) : NSImage(size: CGSize(width: 14, height: 14))

        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityLabel(device.name)
        setAccessibilityValue(isCurrent ? String(localized: "Selected") : "")
    }

    required init?(coder: NSCoder) { nil }
}
