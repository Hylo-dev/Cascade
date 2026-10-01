//
//  SDKReplyDamage.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

enum SDKReplyDamage: Sendable {

    case outerID
    case outerContract
    case outerOperation
    case nestedContract
    case nestedOperation
    case malformed
}
