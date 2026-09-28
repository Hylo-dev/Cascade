//
//  FileShelfDropTarget.swift
//  Cascade
//

import AppKit
import SwiftUI

struct FileShelfDropTarget: View {

    let symbol: String
    let title : String

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 9) {

            MusicControlSymbol(
                symbol      : symbol,
                size        : 40,
                reduceMotion: reduceMotion
            )
            .frame(width: 48, height: 44)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
