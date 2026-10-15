//
//  CaffeinateFailure.swift
//  CascadeKit
//

/// CaffeinateFailure is why the system refused to hold or lengthen a power assertion, with the
/// IOReturn code it answered. It names the step that failed rather than carrying a message, so
/// the widget words it in the user's language and the code stays for diagnosis.
public enum CaffeinateFailure: Equatable, Sendable {

    case assertionRefused(Int32)
    case extensionRefused(Int32)
}
