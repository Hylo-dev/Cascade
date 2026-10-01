//
//  FocusError.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation

public enum FocusError: Error, Equatable, Sendable {

    case busy
    case stopped
    case missingState
    case assignmentMismatch
    case corruptState
    case invalidConfiguration
    case revisionExhausted
}
