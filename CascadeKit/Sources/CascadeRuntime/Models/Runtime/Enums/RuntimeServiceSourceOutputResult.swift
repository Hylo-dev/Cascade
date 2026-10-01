//
//  RuntimeServiceSourceOutputResult.swift
//  CascadeKit
//

import CascadeContracts

enum RuntimeServiceSourceOutputResult: Equatable, Sendable {

    case accepted
    case refused(AddonFailure.Code)
}
