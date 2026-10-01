//
//  ContentPreview.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// ContentPreview uses the production renderer with an explicit preview-only dispatcher.
@MainActor
public struct ContentPreview: View {

    private let renderer: ContentRenderer

    public init(
        document         : ContentDocument,
        assets           : any ContentAssetResolving,
        previewDispatcher: @escaping @MainActor (ActionDescriptor) -> Void
    ) throws {
        renderer = try ContentRenderer(
            document: document,
            assets  : assets,
            dispatch: previewDispatcher
        )
    }

    public var body: some View { renderer }
}
