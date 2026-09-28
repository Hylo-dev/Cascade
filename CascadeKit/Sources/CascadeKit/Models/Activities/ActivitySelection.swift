//
//  ActivitySelection.swift
//  CascadeKit
//

/// ActivitySelection describes the shared live registry independently from any
/// one display. Compact choices survive notice overrides and expanded ownership.
struct ActivitySelection {

    let primary  : (any NotchLiveActivity)?
    let secondary: (any NotchLiveActivity)?
    let expanded : (any NotchLiveActivity)?
    let notice   : (any NotchTransientNotice)?
}
