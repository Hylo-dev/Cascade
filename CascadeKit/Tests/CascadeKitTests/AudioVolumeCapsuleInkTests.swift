//
//  AudioVolumeCapsuleInkTests.swift
//  CascadeKit
//

import SwiftUI
import Testing
@testable import CascadeKit

struct AudioVolumeCapsuleInkTests {

    @Test
    func theIconIsBlueAsSoonAsTheWhiteFillReachesItsBottomEdge() {
        let ink = AudioVolumeCapsule.iconInk(fillHeight: 50, reach: 30, isMuted: false)

        #expect(ink == AudioVolumeCapsule.iconInkOnFill)
    }

    @Test
    func theIconIsWhiteOverTheGlass() {
        let ink = AudioVolumeCapsule.iconInk(fillHeight: 20, reach: 30, isMuted: false)

        #expect(ink == .white)
    }

    @Test
    func theIconIsWhiteOverTheGreyMutedFill() {
        let ink = AudioVolumeCapsule.iconInk(fillHeight: 50, reach: 30, isMuted: true)

        #expect(ink == .white)
    }

    @Test
    func theBlueIsTheReferenceColour() {
        let resolved = AudioVolumeCapsule.iconInkOnFill.resolve(in: EnvironmentValues())

        #expect(resolved.red == 0)
        #expect(abs(resolved.green - 198.0 / 255.0) < 0.01)
        #expect(abs(resolved.blue - 234.0 / 255.0) < 0.01)
    }
}
