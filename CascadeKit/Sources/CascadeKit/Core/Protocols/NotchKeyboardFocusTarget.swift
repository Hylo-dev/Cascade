//
//  NotchKeyboardFocusTarget.swift
//  CascadeKit
//

/// NotchKeyboardFocusTarget marks a native control that explicitly requests
/// keyboard focus after user interaction. Other notch content remains nonactivating
/// and cannot become the key window.
public protocol NotchKeyboardFocusTarget: AnyObject {}
