//
//  RuntimeArchiveRemapping.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeArchiveRemapping replaces inert archive aliases inside already validated contract graphs.
/// The caller admits Q before retaining original and remapped values. These pure transformations
/// preserve every other contract field and grant no provider, connection or native raster authority.
enum RuntimeArchiveRemapping {
    /// publication preserves complete timelines and rewrites every declared and drawn asset reference.
    static func publication(
        _ publication: Publication,
        aliases      : [String: String]
    ) throws -> Publication {
        try Publication(
            id         : publication.id,
            revision   : publication.revision,
            kind       : publication.kind,
            content    : publication.content.map { value in
                try presentations(
                    value,
                    aliases: aliases
                )
            },
            timeline   : publication.timeline.map { entries in
                try entries.map { entry in
                    try ScheduledEntry(
                        date   : entry.date,
                        content: presentations(
                            entry.content,
                            aliases: aliases
                        )
                    )
                }
            },
            expiresAt  : publication.expiresAt,
            stalePolicy: publication.stalePolicy
        )
    }

    /// presentations visits all five optional representations without projecting the current entry.
    private static func presentations(
        _ presentation: PresentationSet,
        aliases       : [String: String]
    ) throws -> PresentationSet {
        try PresentationSet(
            widget         : presentation.widget.map { value in
                try document(
                    value,
                    aliases: aliases
                )
            },
            compactLeading : presentation.compactLeading.map { value in
                try document(
                    value,
                    aliases: aliases
                )
            },
            compactTrailing: presentation.compactTrailing.map { value in
                try document(
                    value,
                    aliases: aliases
                )
            },
            minimal        : presentation.minimal.map { value in
                try document(
                    value,
                    aliases: aliases
                )
            },
            expanded       : presentation.expanded.map { value in
                try document(
                    value,
                    aliases: aliases
                )
            }
        )
    }

    /// document uses the full initializer so schema-two glass lights and privacy remain unchanged.
    private static func document(
        _ document: ContentDocument,
        aliases   : [String: String]
    ) throws -> ContentDocument {
        try ContentDocument(
            schemaVersion     : document.schemaVersion,
            root              : node(
                document.root,
                aliases: aliases
            ),
            accessibilityLabel: document.accessibilityLabel,
            privacy           : document.privacy,
            assets            : document.assets.map { previous in
                try alias(
                    previous,
                    in: aliases
                )
            },
            glassLights       : document.glassLights
        )
    }

    /// node retains action payloads, clock format, accessibility and all scalar/optional fields.
    private static func node(
        _ node : ContentNode,
        aliases: [String: String]
    ) throws -> ContentNode {
        try ContentNode(
            kind              : node.kind,
            text              : node.text,
            assetID           : node.assetID.map { previous in
                try alias(
                    previous,
                    in: aliases
                )
            },
            value             : node.value,
            deadline          : node.deadline,
            actionID          : node.actionID,
            children          : node.children.map { children in
                try children.map { child in
                    try self.node(
                        child,
                        aliases: aliases
                    )
                }
            },
            accessibilityLabel: node.accessibilityLabel,
            actionPayload     : node.actionPayload,
            clockFormat       : node.clockFormat
        )
    }

    /// alias rejects incomplete host remapping rather than retaining a serialized handle.
    private static func alias(
        _ previous: String,
        in aliases: [String: String]
    ) throws -> String {
        guard let replacement = aliases[previous] else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Archive image reference has no fresh host alias."
            )
        }
        return replacement
    }
}
