//
//  RefreshHarnessFailure.swift
//  ServiceConsumer
//

import Foundation
import Testing
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract
import FocusSessionsExampleProvider

enum RefreshHarnessFailure: Error {

    case completedBeforeInvocation
}
