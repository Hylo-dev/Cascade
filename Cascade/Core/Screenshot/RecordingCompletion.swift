//
//  RecordingCompletion.swift
//  Cascade
//

import Foundation

/// RecordingCompletion retains native results that arrive before their awaiter.
/// Start and file finalization are bounded so a missing framework callback can
/// never leave termination waiting forever. Each deadline is cancelled on reply.
actor RecordingCompletion {

    private var startResult: Result<Date, ScreenCaptureFailure>?
    private var endResult  : Result<Void, ScreenCaptureFailure>?
    private var startWaiter: CheckedContinuation<Date, any Error>?
    private var endWaiter  : CheckedContinuation<Void, any Error>?
    private var deadline   : Task<Void, Never>?

    var hasFinishedSuccessfully: Bool {
        if case .success? = endResult { return true }
        return false
    }

    func started(at date: Date) {
        guard startResult == nil else { return }

        startResult = .success(date)
        startWaiter?.resume(returning: date)
        startWaiter = nil
        deadline?.cancel()
        deadline = nil
    }

    func finished() {
        guard endResult == nil else { return }

        endResult = .success(())
        endWaiter?.resume()
        endWaiter = nil
        if startResult == nil { fail(.native("Recording finished before it started.")) }
        deadline?.cancel()
        deadline = nil
    }

    func fail(_ error: ScreenCaptureFailure) {
        if startResult == nil {
            startResult = .failure(error)
            startWaiter?.resume(throwing: error)
            startWaiter = nil
        }
        if endResult == nil {
            endResult = .failure(error)
            endWaiter?.resume(throwing: error)
            endWaiter = nil
        }
        deadline?.cancel()
        deadline = nil
    }

    func waitForStart() async throws -> Date {
        if let startResult { return try startResult.get() }

        return try await withCheckedThrowingContinuation { continuation in
            startWaiter = continuation
            armDeadline()
        }
    }

    func waitForFinish() async throws {
        if let endResult { return try endResult.get() }

        try await withCheckedThrowingContinuation { continuation in
            endWaiter = continuation
            armDeadline()
        }
    }

    private func armDeadline() {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
            await self?.fail(.timedOut)
        }
    }
}
