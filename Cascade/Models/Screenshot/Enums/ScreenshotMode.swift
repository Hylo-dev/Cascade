//
//  ScreenshotMode.swift
//  Cascade
//

/// ScreenshotMode is the user's capture intent, independent of any native
/// capture or recording session. Choosing a mode does not start a recording.
nonisolated enum ScreenshotMode: Equatable {

    case capture
    case recording
}
