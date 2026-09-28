//
//  ContentNode+Components.swift
//  CascadeKit
//

import Foundation

/// ContentNode factories preserve the validated wire representation used by every publisher.
extension ContentNode {
    public static func text(_ text: String) throws -> Self {
        return try Self(
            kind: .text,
            text: text,
            assetID: nil,
            value: nil,
            deadline: nil,
            actionID: nil,
            children: nil
        )
    }

    public static func symbol(_ name: String) throws -> Self {
        return try Self(
            kind: .symbol,
            text: name,
            assetID: nil,
            value: nil,
            deadline: nil,
            actionID: nil,
            children: nil
        )
    }

    public static func image(assetID: String, accessibilityLabel: String) throws -> Self {
        return try Self(
            kind: .image,
            text: nil,
            assetID: assetID,
            value: nil,
            deadline: nil,
            actionID: nil,
            children: nil,
            accessibilityLabel: accessibilityLabel
        )
    }

    public static func row(_ children: [ContentNode]) throws -> Self {
        return try Self(
            kind: .row,
            text: nil,
            assetID: nil,
            value: nil,
            deadline: nil,
            actionID: nil,
            children: children
        )
    }

    public static func column(_ children: [ContentNode]) throws -> Self {
        return try Self(
            kind: .column,
            text: nil,
            assetID: nil,
            value: nil,
            deadline: nil,
            actionID: nil,
            children: children
        )
    }

    public static func progress(value: Double) throws -> Self {
        guard value.isFinite else {
            throw AddonFailure(code: .invalidPayload, reason: "Progress must be finite")
        }
        return try Self(
            kind: .progress,
            text: nil,
            assetID: nil,
            value: min(1, max(0, value)),
            deadline: nil,
            actionID: nil,
            children: nil
        )
    }

    public static func countdown(until: Date) throws -> Self {
        return try Self(
            kind: .countdown,
            text: nil,
            assetID: nil,
            value: nil,
            deadline: until,
            actionID: nil,
            children: nil
        )
    }

    public static func clock(format: ClockFormat = .hourMinute) throws -> Self {
        return try Self(
            kind: .clock,
            text: nil,
            assetID: nil,
            value: nil,
            deadline: nil,
            actionID: nil,
            children: nil,
            clockFormat: format
        )
    }

    public static func action(_ descriptor: ActionDescriptor) throws -> Self {
        return try Self(
            kind: .action,
            text: descriptor.label,
            assetID: nil,
            value: nil,
            deadline: nil,
            actionID: descriptor.id,
            children: nil,
            actionPayload: descriptor.payload
        )
    }

    public static func fileWorkspace(_ presentation: FileWorkspacePresentation) throws -> Self {
        return try Self(
            kind         : .fileWorkspace,
            text         : nil,
            assetID      : nil,
            value        : nil,
            deadline     : nil,
            actionID     : nil,
            children     : nil,
            fileWorkspace: presentation
        )
    }

}
