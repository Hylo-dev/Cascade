//
//  NotchGlassLightEmission.swift
//  CascadeKit
//

import CascadeContracts

struct NotchGlassLightEmission: Equatable, Sendable {

    let token : NotchGlassLightSources.Token
    let lights: [GlassLight]
}
