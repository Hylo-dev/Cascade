//
//  NotchInteractionKind.swift
//  CascadeKit
//

/// NotchInteractionKind names interactions that pin an owner and its invocation
/// anchor while still allowing focused-window routing to update compact copies.
enum NotchInteractionKind: Hashable {

    case settings
    case spotlight
    case calibration
    case popover
    case drag
}
