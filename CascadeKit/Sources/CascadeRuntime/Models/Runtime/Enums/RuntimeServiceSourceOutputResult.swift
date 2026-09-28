//
//  RuntimeServiceSourceOutputResult.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

enum RuntimeServiceSourceOutputResult: Equatable, Sendable {
    case accepted
    case refused(AddonFailure.Code)
}
