//
//  RecordingSpotlightDroplet.swift
//  Cascade
//

import AppKit
import CascadeKit
import Testing
@testable import Cascade

@MainActor
final class RecordingSpotlightDroplet: SpotlightDropletPresenting {

    private(set) var previewAnchor: SpotlightDisplayAnchor?
    private(set) var cancelCount   = 0
    private(set) var playCount     = 0
    private(set) var previewCount  = 0

    private var playCompletion   : ((CGRect) -> Void)?
    private var previewCompletion: (() -> Void)?

    func play(
        at anchor : SpotlightDisplayAnchor,
        nativeSize: CGSize,
        completion: @escaping (CGRect) -> Void
    ) {
        playCount      += 1
        playCompletion  = completion
    }

    func yieldToNative() {}

    func revealNative() {}

    func cancel() { cancelCount += 1 }

    func preview(
        at anchor : SpotlightDisplayAnchor,
        completion: @escaping () -> Void
    ) {
        previewCount      += 1
        previewAnchor      = anchor
        previewCompletion  = completion
    }

    func finishPlay() { playCompletion?(.zero) }

    func finishPreview() { previewCompletion?() }
}
