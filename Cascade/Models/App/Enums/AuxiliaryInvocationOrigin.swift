//
//  AuxiliaryInvocationOrigin.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import Observation

nonisolated enum AuxiliaryInvocationOrigin {
    case global, settings

    func resolve(
        settingsDisplayID: CGDirectDisplayID?,
        activeDisplayID  : CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        switch self {
        case .global: activeDisplayID
        case .settings: settingsDisplayID ?? activeDisplayID
        }
    }
}
