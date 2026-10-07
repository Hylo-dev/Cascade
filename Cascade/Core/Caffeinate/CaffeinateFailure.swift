//
//  CaffeinateFailure.swift
//  Cascade
//

import Foundation

/// CaffeinateFailure preserves the power service's error code rather than reporting an
/// active session when macOS refused the assertion.
nonisolated enum CaffeinateFailure: Error, LocalizedError {

    case invalidDeadline
    case native(Int32)

    var errorDescription: String? {
        switch self {
            case .invalidDeadline:
                String(localized: "Choose a session ending within the next 24 hours.")

            case .native(let code):
                String(localized: "Could not change sleep prevention (IOKit error \(code)).")
        }
    }
}
