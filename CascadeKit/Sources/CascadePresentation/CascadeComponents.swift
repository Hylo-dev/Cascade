//
//  CascadeComponents.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeText builds a validated durable text description.
public struct CascadeText: CascadeContent {
    public let contentNode: ContentNode

    public init(_ text: String) throws {
        contentNode = try .text(text)
    }
}

/// CascadeSymbol builds a validated durable symbol description.
public struct CascadeSymbol: CascadeContent {
    public let contentNode: ContentNode

    public init(_ name: String) throws {
        contentNode = try .symbol(name)
    }
}

/// CascadeImage builds a validated durable image description.
public struct CascadeImage: CascadeContent {
    public let contentNode: ContentNode

    public init(
        assetID           : String,
        accessibilityLabel: String
    ) throws {
        contentNode = try .image(
            assetID           : assetID,
            accessibilityLabel: accessibilityLabel
        )
    }
}

/// CascadeProgress builds a validated durable progress description.
public struct CascadeProgress: CascadeContent {
    public let contentNode: ContentNode

    public init(value: Double) throws {
        contentNode = try .progress(value: value)
    }
}

/// CascadeCountdown builds a validated durable countdown description.
public struct CascadeCountdown: CascadeContent {
    public let contentNode: ContentNode

    public init(until: Date) throws {
        contentNode = try .countdown(until: until)
    }
}

/// CascadeClock builds a validated durable clock description.
public struct CascadeClock: CascadeContent {
    public let contentNode: ContentNode

    public init(format: ClockFormat = .hourMinute) throws {
        contentNode = try .clock(format: format)
    }
}

/// CascadeButton builds a validated durable button description.
public struct CascadeButton: CascadeContent {
    public let contentNode: ContentNode

    public init(_ action: ActionDescriptor) throws {
        contentNode = try .action(action)
    }
}

/// CascadeRow builds a validated durable row description.
public struct CascadeRow: CascadeContent {
    public let contentNode: ContentNode

    public init(@CascadeContentBuilder content: () throws -> [ContentNode]) throws {
        contentNode = try .row(content())
    }
}

/// CascadeColumn builds a validated durable column description.
public struct CascadeColumn: CascadeContent {
    public let contentNode: ContentNode

    public init(@CascadeContentBuilder content: () throws -> [ContentNode]) throws {
        contentNode = try .column(content())
    }
}
