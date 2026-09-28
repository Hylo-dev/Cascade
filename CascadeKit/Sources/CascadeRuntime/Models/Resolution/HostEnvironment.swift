//
//  HostEnvironment.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public struct HostEnvironment: Sendable {
    public let osVersion: SemanticVersion
    public let hostCapabilities: [String: SemanticVersion]
    public let applications: [AddonID: ApplicationAvailability]
    public let grants: [AddonID: Set<String>]
    public var explicitBindings: [ServiceBinding]
    public let protocolVersion: (major: Int, minor: Int)
    public let serviceAccessGrants: Set<ServiceAccessGrant>

    public init(osVersion: SemanticVersion, hostCapabilities: [String: SemanticVersion], applications: [AddonID: ApplicationAvailability], grants: [AddonID: Set<String>], explicitBindings: [ServiceBinding], protocolVersion: (major: Int, minor: Int) = (1, 0), serviceAccessGrants: Set<ServiceAccessGrant> = []) {
        self.osVersion = osVersion; self.hostCapabilities = hostCapabilities; self.applications = applications
        self.grants = grants; self.explicitBindings = explicitBindings
        self.protocolVersion = protocolVersion
        self.serviceAccessGrants = serviceAccessGrants
    }
}
