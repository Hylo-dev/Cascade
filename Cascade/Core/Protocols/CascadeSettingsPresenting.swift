//
//  CascadeSettingsPresenting.swift
//  Cascade
//

import AppKit
import SwiftUI

/// CascadeSettingsPresenting keeps native window ownership out of the services.
@MainActor
protocol CascadeSettingsPresenting: AnyObject {
    func show(
        services  : CascadeServices,
        notchFrame: CGRect
    )
    func updateNotchFrame(_ frame: CGRect?)
    func close()
}
