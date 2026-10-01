//
//  FileRemovalModifier.swift
//  CascadeKit
//

import CascadeContracts
import AppKit
import SwiftUI

struct FileRemovalModifier: AnimatableModifier {

    nonisolated var progress: CGFloat
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.08)
            .offset(y: reduceMotion ? 0 : -progress * 7)
            .mask {
                if reduceMotion || progress <= 0 {
                    Rectangle()
                } else {
                    FileDissolveMask(progress: progress)
                }
            }
    }
}
