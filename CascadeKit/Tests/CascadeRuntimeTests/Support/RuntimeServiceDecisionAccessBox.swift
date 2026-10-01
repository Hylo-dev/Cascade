//
//  RuntimeServiceDecisionAccessBox.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
@testable import CascadeRuntime

/// RuntimeServiceDecisionAccessBox exposes the wrapper assembled around the runtime's private broker.
final class RuntimeServiceDecisionAccessBox: @unchecked Sendable {
    var access: GatedRuntimeServiceDecisionAccess?
}
