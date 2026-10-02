//
//  RecordingCompletionTests.swift
//  Cascade
//

import Foundation
import Testing
@testable import Cascade

struct RecordingCompletionTests {

    @Test
    func nativeCallbacksCanArriveBeforeTheirAwaiters() async throws {
        let completion = RecordingCompletion()
        let date = Date(timeIntervalSince1970: 42)
        await completion.started(at: date)
        await completion.finished()
        #expect(await completion.hasFinishedSuccessfully)
        #expect(try await completion.waitForStart() == date)
        try await completion.waitForFinish()
    }

    @Test
    func nativeFailureResumesBothPhases() async {
        let completion = RecordingCompletion()
        await completion.fail(.native("Encoder unavailable"))
        #expect(await !completion.hasFinishedSuccessfully)
        await #expect(throws: ScreenCaptureFailure.self) { try await completion.waitForStart() }
        await #expect(throws: ScreenCaptureFailure.self) { try await completion.waitForFinish() }
    }
}
