//
//  ServiceInvocationFrameProfile.swift
//  CascadeKit
//

import Foundation

/// ServiceInvocationFrameProfile is proposed syntax only; selecting this profile
/// negotiates or authenticates nothing. Runtime must select a profile from canonical
/// negotiation after host integration.
public enum ServiceInvocationFrameProfile: Equatable, Sendable { case v1_3 }
