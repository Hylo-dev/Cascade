//
//  ServiceSourceDescriptor.swift
//  CascadeKit
//

public struct ServiceSourceDescriptor: Equatable, Sendable {

    public let provider       : VerifiedAddonIdentity
    public let digest         : String
    public let contractVersion: String
    public let serviceID      : String
    public let partition      : String
    public let featureID      : String
    public let operation      : String
}
