//
//  ContentRenderer.swift
//  Cascade
//

import CascadeContracts
import Foundation
import SwiftUI

/// ContentAssetResolving supplies host-admitted images, without filesystem or network URLs.
@MainActor
public protocol ContentAssetResolving {
    func image(for assetID: String) -> Image?
}

/// ContentRenderer constructs views only after validating the complete durable description.
/// Host callbacks dispatch descriptors across the process boundary; providers never run here.
@MainActor
public struct ContentRenderer: View {
    private let document: ContentDocument
    private let assets: any ContentAssetResolving
    private let dispatch: @MainActor (ActionDescriptor) -> Void

    public init(
        document: ContentDocument,
        assets: any ContentAssetResolving,
        dispatch: @escaping @MainActor (ActionDescriptor) -> Void
    ) throws {
        try document.validate()
        self.document = document
        self.assets = assets
        self.dispatch = dispatch
    }

    public var body: some View {
        nodeView(document.root)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(document.accessibilityLabel)
            .privacySensitive(document.privacy == .sensitive)
            .notchGlassLights(document.glassLights ?? [])
    }

    // Type erasure only wraps host-created views from a bounded tree. No view is serialized.
    private func nodeView(_ node: ContentNode) -> AnyView {
        switch node.kind {
        case .text:
            return AnyView(Text(node.text ?? ""))
        case .symbol:
            return AnyView(
                Image(systemName: node.text ?? "questionmark")
                    .accessibilityHidden(true)
            )
        case .image:
            return AnyView(
                (assets.image(for: node.assetID ?? "") ?? Image(systemName: "photo"))
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(node.accessibilityLabel ?? "")
            )
        case .row:
            return AnyView(
                HStack {
                    ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                        nodeView(child)
                    }
                }
            )
        case .column:
            return AnyView(
                VStack(alignment: .leading) {
                    ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                        nodeView(child)
                    }
                }
            )
        case .progress:
            let fraction = node.value ?? 0
            return AnyView(
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * fraction)
                    }
                }
                .frame(height: 4)
                .accessibilityElement()
                .accessibilityLabel(document.accessibilityLabel)
                .accessibilityValue(fraction.formatted(.percent))
            )
        case .countdown:
            // SwiftUI owns timer text updates and visibility lifetime; no provider timer exists.
            let deadline = node.deadline ?? .distantPast
            return AnyView(
                Text(timerInterval: min(Date.now, deadline)...deadline, countsDown: true)
                    .monospacedDigit()
            )
        case .clock:
            let includesSeconds = node.clockFormat == .hourMinuteSecond
            return AnyView(
                TimelineView(
                    .periodic(
                        from: Date(
                            timeIntervalSince1970: floor(
                                Date.now.timeIntervalSince1970 / (includesSeconds ? 1 : 60)
                            ) * (includesSeconds ? 1 : 60)
                        ),
                        by: includesSeconds ? 1 : 60
                    )
                ) { context in
                    Text(
                        context.date,
                        format: includesSeconds
                            ? .dateTime.hour().minute().second()
                            : .dateTime.hour().minute()
                    )
                    .monospacedDigit()
                }
            )
        case .action:
            // Reconstruction is guaranteed by node validation. Failed validation never dispatches.
            return AnyView(
                Button(node.text ?? "") {
                    do {
                        let action = try ActionDescriptor(
                            id: node.actionID ?? "",
                            label: node.text ?? "",
                            payload: node.actionPayload ?? Data()
                        )
                        dispatch(action)
                    } catch {
                        assertionFailure("Validated action could not be reconstructed: \(error)")
                    }
                }
            )
        }
    }
}
