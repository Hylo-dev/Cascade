//
//  SubscriptionSDKObservation.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

actor SubscriptionSDKObservation {
    private(set) var payload: Data?
    func record(_ value: Data) { payload = value }
}
