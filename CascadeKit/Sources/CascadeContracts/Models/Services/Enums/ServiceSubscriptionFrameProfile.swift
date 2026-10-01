//
//  ServiceSubscriptionFrameProfile.swift
//  CascadeKit
//

import Foundation

/// ServiceSubscriptionFrameProfile is a pure syntax selection; it neither
/// negotiates nor authenticates a channel.
public enum ServiceSubscriptionFrameProfile: Equatable, Sendable {

    case v1_4
}
