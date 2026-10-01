//
//  FocusCommand.swift
//  StandaloneFocus
//

import CascadeContracts
import Foundation

public enum FocusCommand: String, Codable, Sendable, CaseIterable {

    case start
    case pause
    case resume
    case end
}
