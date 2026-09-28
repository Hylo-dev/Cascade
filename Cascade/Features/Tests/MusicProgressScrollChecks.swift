#if MUSIC_PROGRESS_TESTS
import AppKit
import Foundation

@main @MainActor
private enum MusicProgressScrollChecks {
    struct Failure: Error { let message: String }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    static func scroll(y: Int32 = 0, x: Int32 = 0, precise: Bool = false,
                       phase: NSEvent.Phase = [], momentum: Int64 = 0) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line,
                            wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!
        // Quartz and AppKit use different bit values for gesture phases.
        let quartzPhase: Int64
        switch phase {
        case .began: quartzPhase = Int64(CGScrollPhase.began.rawValue)
        case .changed: quartzPhase = Int64(CGScrollPhase.changed.rawValue)
        case .ended: quartzPhase = Int64(CGScrollPhase.ended.rawValue)
        case .cancelled: quartzPhase = Int64(CGScrollPhase.cancelled.rawValue)
        default: quartzPhase = 0
        }
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: quartzPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        let native = NSEvent(cgEvent: event)!
        precondition(native.phase == phase && native.hasPreciseScrollingDeltas == precise)
        return native
    }
    static func main() async {
        _ = NSApplication.shared
        do { try await checkScroll(); print("Music progress scroll checks passed") }
        catch { print("FAILED: \(error)"); exit(1) }
    }
    static func checkScroll() async throws {
        let slider = MusicProgressControl(frame: NSRect(x: 0, y: 0, width: 300, height: 18))
        slider.minValue = 0; slider.maxValue = 180; slider.doubleValue = 60
        var previews: [Double] = []
        var commits: [Double] = []
        var cancellations = 0
        slider.onPreview = { previews.append($0) }
        slider.onCommit = { commits.append($0) }
        slider.onCancel = { cancellations += 1 }
        slider.scrollWheel(with: scroll(y: 1))
        slider.scrollWheel(with: scroll(y: 1))
        try require(slider.isScrubbing && slider.doubleValue == 70 && previews == [65, 70], "Wheel must preview immediately in five-second steps")
        try require(commits.isEmpty, "Wheel burst must not send a command for every tick")
        try await Task.sleep(for: .milliseconds(280))
        try require(commits == [70] && !slider.isScrubbing, "A wheel burst must commit exactly once after settling")

        commits.removeAll(); previews.removeAll()
        slider.scrollWheel(with: scroll(x: -10, precise: true, phase: .began))
        try await Task.sleep(for: .milliseconds(250))
        try require(slider.isScrubbing && commits.isEmpty, "A resting finger must not prematurely end a trackpad gesture")
        slider.scrollWheel(with: scroll(x: -5, precise: true, phase: .changed))
        try require(slider.doubleValue == 73, "Horizontal trackpad motion must support fine seeking")
        slider.scrollWheel(with: scroll(precise: true, phase: .ended))
        try require(commits == [73] && !slider.isScrubbing, "Finger release must commit the trackpad gesture once")
        slider.scrollWheel(with: scroll(x: -50, precise: true, momentum: 1))
        try require(slider.doubleValue == 73 && commits == [73], "Momentum must not move playback after finger release")

        slider.scrollWheel(with: scroll(y: -500, precise: true, phase: .began))
        try require(slider.doubleValue == 0, "Scroll must clamp to the beginning")
        slider.scrollWheel(with: scroll(y: 5000, precise: true, phase: .changed))
        try require(slider.doubleValue == 180, "Scroll must clamp to the track duration")
        slider.scrollWheel(with: scroll(precise: true, phase: .cancelled))
        try require(slider.doubleValue == 73 && cancellations == 1 && commits == [73], "Cancelled gestures must restore the position without seeking")

        slider.scrollWheel(with: scroll(y: 1))
        slider.isEnabled = false
        slider.scrollWheel(with: scroll(y: 10))
        try await Task.sleep(for: .milliseconds(280))
        try require(slider.doubleValue == 73 && commits == [73] && !slider.isScrubbing, "Disabling must cancel a queued wheel command")
        slider.isEnabled = true
        slider.scrollWheel(with: scroll(y: -1))
        var replacementCommits = 0
        slider.onCommit = { _ in replacementCommits += 1 }
        try await Task.sleep(for: .milliseconds(280))
        try require(commits == [73, 68] && replacementCommits == 0, "A gesture must keep the original displayed track's callback")
        slider.scrollWheel(with: scroll(y: 1))
        slider.trackIdentity = ["new-player", "new-track"]
        try await Task.sleep(for: .milliseconds(280))
        try require(replacementCommits == 0 && !slider.isScrubbing && slider.doubleValue == 68, "Changing tracks must cancel a queued seek")
        slider.scrollWheel(with: scroll(y: 1))
        slider.viewWillMove(toWindow: nil)
        try await Task.sleep(for: .milliseconds(280))
        try require(replacementCommits == 0 && !slider.isScrubbing, "Detaching the control must cancel pending scroll work")
        slider.moveRight(nil)
        try require(replacementCommits == 1, "Keyboard seeking must still commit immediately")
        _ = slider.accessibilityPerformIncrement()
        try require(replacementCommits == 2, "Accessibility seeking must remain native")
    }
}
#endif
