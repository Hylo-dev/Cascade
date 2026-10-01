//
//  SnapshotDocumentView.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

@MainActor
struct SnapshotDocumentView: View {

    let document               : ContentDocument
    let assets                 : any ContentAssetResolving
    var redactsSensitiveContent = false
    let dispatch               : @MainActor @Sendable (ActionDescriptor) -> Void

    var body: some View {
        if redactsSensitiveContent && document.privacy == .sensitive {
            Label(String(localized: "Sensitive content hidden", bundle: .module), systemImage: "eye.slash")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Sensitive content hidden", bundle: .module))
        } else if let renderer = try? ContentRenderer(
            document: document,
            assets  : assets,
            dispatch: dispatch
        ) {
            renderer
        }
    }
}
