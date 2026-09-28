//
//  NotchGlassLightEmission.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

struct NotchGlassLightEmission: Equatable, Sendable {
    let token: NotchGlassLightSources.Token
    let lights: [GlassLight]
}
