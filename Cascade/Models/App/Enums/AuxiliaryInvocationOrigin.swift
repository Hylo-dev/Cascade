//
//  AuxiliaryInvocationOrigin.swift
//  Cascade
//

import AppKit

nonisolated enum AuxiliaryInvocationOrigin {

    case global
    case settings

    func resolve(
        settingsDisplayID: CGDirectDisplayID?,
        activeDisplayID  : CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        switch self {
            case .global  : activeDisplayID
            case .settings: settingsDisplayID ?? activeDisplayID
        }
    }
}
