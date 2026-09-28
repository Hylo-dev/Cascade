//
//  MusicTrackTransition.swift
//  Cascade
//

import AppKit
import CascadeKit
import CoreImage
import Observation
import QuartzCore
import SwiftUI

/// MusicTrackTransition is the one motion of a track change: the cover blurs
/// from one to the next, the text rises through a blur. It runs once per
/// change, never while a track plays. Reduce Motion keeps a plain crossfade.
enum MusicTrackTransition {
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)
    }

    static func cover(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }

    static func text(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: AnyTransition(.blurReplace).combined(with: .offset(y: 7)),
            removal  : AnyTransition(.blurReplace).combined(with: .offset(y: -7))
        )
    }
}
