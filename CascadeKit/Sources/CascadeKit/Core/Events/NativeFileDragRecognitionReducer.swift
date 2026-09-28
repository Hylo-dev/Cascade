//
//  NativeFileDragRecognitionReducer.swift
//  CascadeKit
//

nonisolated struct NativeFileDragRecognitionReducer {

    enum Input {

        case mouseDown(changeCount: Int)
        case dragged(changeCount: Int, hasFileIntent: Bool)
        case mouseUp
    }

    private var baselineChangeCount     : Int?
    private var isRecognized             = false
    private var lastInspectedChangeCount: Int?

    mutating func shouldInspectDrag(changeCount: Int) -> Bool {
        guard !isRecognized,
              let baselineChangeCount,
              changeCount != baselineChangeCount,
              lastInspectedChangeCount != changeCount
        else { return false }

        lastInspectedChangeCount = changeCount
        return true
    }

    mutating func consume(_ input: Input) -> Bool? {
        switch input {
            case let .mouseDown(changeCount):
                let replacedRecognizedGesture = isRecognized

                baselineChangeCount      = changeCount
                isRecognized             = false
                lastInspectedChangeCount = nil
                return replacedRecognizedGesture ? false : nil

            case let .dragged(changeCount, hasFileIntent):
                guard !isRecognized,
                      hasFileIntent,
                      let baselineChangeCount,
                      changeCount != baselineChangeCount
                else { return nil }

                isRecognized = true
                return true

            case .mouseUp:
                baselineChangeCount      = nil
                lastInspectedChangeCount = nil
                guard isRecognized else { return nil }

                isRecognized = false
                return false
        }
    }

    mutating func cancel() -> Bool? {
        consume(.mouseUp)
    }

    mutating func cancelStaleGesture() -> Bool? {
        guard isRecognized else { return nil }

        return consume(.mouseUp)
    }
}
