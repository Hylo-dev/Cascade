//
//  AudioProcessResponsibilityTests.swift
//  CascadeKit
//

@testable import CascadeAudioHost
import Darwin
import Testing

@Suite
struct AudioProcessResponsibilityTests {

    /// Under `swift test` the responsible process is the test runner's parent, and under launchd
    /// it is the process itself, so the answer is not pinned: the test proves only that asking
    /// about a live process neither crashes nor returns an empty path.
    @Test
    func theOwnProcessAnswersNilOrAPath() {
        let path = AudioProcessResponsibility.responsibleExecutablePath(ofPID: getpid())

        if let path { #expect(!path.isEmpty) }
    }

    @Test
    func aProcessThatDoesNotExistAnswersNil() {
        #expect(AudioProcessResponsibility.responsibleExecutablePath(ofPID: Int32.max) == nil)
    }
}
