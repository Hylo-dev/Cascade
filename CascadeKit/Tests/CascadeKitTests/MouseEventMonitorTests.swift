//
//  MouseEventMonitorTests.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

@MainActor
struct MouseEventMonitorTests {

    @Test
    func fileIntentRequiresAFreshDragPasteboardAndEmitsOneFiniteGesture() {
        var reducer = NativeFileDragRecognitionReducer()

        #expect(reducer.consume(.mouseDown(changeCount: 4)) == nil)
        #expect(reducer.shouldInspectDrag(changeCount: 4) == false)

        let shouldInspectFirstChange = reducer.shouldInspectDrag(changeCount: 5)
        #expect(shouldInspectFirstChange)
        #expect(reducer.consume(.dragged(changeCount: 5, hasFileIntent: false)) == nil)
        #expect(reducer.shouldInspectDrag(changeCount: 5) == false)

        let shouldInspectSecondChange = reducer.shouldInspectDrag(changeCount: 6)
        #expect(shouldInspectSecondChange)
        #expect(reducer.consume(.dragged(changeCount: 6, hasFileIntent: true)) == true)
        #expect(reducer.shouldInspectDrag(changeCount: 7) == false)
        #expect(reducer.consume(.mouseUp) == false)
        #expect(reducer.consume(.mouseUp) == nil)
    }

    @Test
    func aNewMouseDownOrUnpressedMoveClearsAStaleRecognizedGesture() {
        var reducer = NativeFileDragRecognitionReducer()

        #expect(reducer.consume(.mouseDown(changeCount: 1)) == nil)
        #expect(reducer.consume(.dragged(changeCount: 2, hasFileIntent: true)) == true)
        #expect(reducer.consume(.mouseDown(changeCount: 3)) == false)
        #expect(reducer.consume(.dragged(changeCount: 4, hasFileIntent: true)) == true)
        #expect(reducer.cancelStaleGesture() == false)
        #expect(reducer.cancelStaleGesture() == nil)
    }
}
