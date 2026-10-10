//
//  AudioAppEnforcement.swift
//  CascadeKit
//

import Foundation

/// AudioAppEnforcement says how AudioHost is honouring an app's intent right now. It exists so
/// the interface never claims a control it does not have: a slider is live only when the app
/// is `applied`, and a `notApplied` app (permission denied, tap refused) shows why instead.
public enum AudioAppEnforcement: String, Codable, Sendable {

    /// The app is untouched and plays natively: nothing was asked, so nothing is tapped.
    case native

    /// The app is muted or scaled by a live tap and renders where the intent says.
    case applied

    /// The tap or its output broke (a device vanished, the app relaunched) and is being rebuilt.
    case recovering

    /// The intent could not be enforced; the app plays natively and the user should know.
    case notApplied
}
