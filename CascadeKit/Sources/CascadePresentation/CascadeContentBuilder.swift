//
//  CascadeContentBuilder.swift
//  Cascade
//

import CascadeContracts

/// CascadeContentBuilder composes values; layout constructors enforce the final tree budget.
@resultBuilder
public enum CascadeContentBuilder {
    public static func buildExpression(_ component: some CascadeContent) -> [ContentNode] {
        [component.contentNode]
    }
    public static func buildBlock(_ components: [ContentNode]...) -> [ContentNode] {
        components.flatMap { $0 }
    }
    public static func buildOptional(_ component: [ContentNode]?) -> [ContentNode] {
        component ?? []
    }
    public static func buildEither(first component: [ContentNode]) -> [ContentNode] { component }
    public static func buildEither(second component: [ContentNode]) -> [ContentNode] { component }
    public static func buildArray(_ components: [[ContentNode]]) -> [ContentNode] {
        components.flatMap { $0 }
    }
}
