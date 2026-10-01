//
//  SDKReplyDamage.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

enum SDKReplyDamage: Sendable { case outerID, outerContract, outerOperation, nestedContract, nestedOperation, malformed }
