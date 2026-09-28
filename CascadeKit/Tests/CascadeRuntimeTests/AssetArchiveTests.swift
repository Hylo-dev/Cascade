//
//  AssetArchiveTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AssetArchiveTests {
    private let owner: AddonID
    private let foreignOwner: AddonID
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    init() throws {
        owner = try #require(AddonID(rawValue: "com.example.archive-assets"))
        foreignOwner = try #require(AddonID(rawValue: "com.example.foreign-assets"))
    }

    private var identity: VerifiedAddonIdentity {
        VerifiedAddonIdentity(
            publisher: "test.publisher",
            addonID  : owner
        )
    }

    private func scope() -> AssetState.Scope {
        AssetState.Scope(
            identity       : identity,
            verifiedDigest : "verified",
            featureID      : "widget",
            publicationID  : PublicationID(
                addonID   : owner,
                instanceID: UUID(),
                sessionID : UUID()
            ),
            connectionToken: UUID()
        )
    }

    private func presentation(
        aliases: [String],
        privacy: ContentDocument.Privacy = .publicContent
    ) throws -> PresentationSet {
        try PresentationSet(
            widget         : ContentDocument(
                root              : .text("Archive"),
                privacy           : privacy,
                accessibilityLabel: "Archive",
                assetIDs          : aliases
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
    }

    private func publication(
        id      : PublicationID,
        aliases : [String],
        revision: UInt64 = 0,
        future  : Bool = false
    ) throws -> Publication {
        let timeline: [ScheduledEntry]? = future ? [
            try ScheduledEntry(
                date   : now.addingTimeInterval(10),
                content: presentation(aliases: aliases)
            ),
            try ScheduledEntry(
                date   : now.addingTimeInterval(20),
                content: presentation(
                    aliases: aliases,
                    privacy: .sensitive
                )
            ),
        ] : nil
        return try Publication(
            id         : id,
            revision   : revision,
            kind       : .widget,
            content    : future ? nil : presentation(aliases: aliases),
            timeline   : timeline,
            expiresAt  : now.addingTimeInterval(60),
            stalePolicy: .retainMarked
        )
    }

    private func restored(
        _ publications: [Publication],
        in state      : PublicationState = PublicationState(),
        at date       : Date? = nil
    ) throws -> PublicationState.PreparedRestoration {
        try state.prepareRestoration(
            publications.map {
                PublicationArchiveRecord(
                    id             : $0.id,
                    revision       : $0.revision,
                    kind           : $0.kind,
                    sessionDeadline: now.addingTimeInterval(600),
                    publication    : $0
                )
            },
            identity: identity,
            at      : date ?? now
        )
    }

    private func raster(
        _ coordinator: AssetDisposalCoordinator,
        owner        : AddonID? = nil
    ) async throws -> AssetRasterBacking {
        try await coordinator.create(
            pixels: Data([255, 0, 0, 255]),
            width : 1,
            height: 1,
            owner : owner ?? self.owner
        )
    }

    /// publishImported establishes genuine ordinary publication pins before archive capture.
    private func publishImported(
        assets     : inout AssetState,
        scope      : AssetState.Scope,
        publication: Publication
    ) throws {
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection = try publications.openConnection(
            identity              : identity,
            verifiedDigest        : scope.verifiedDigest,
            manifestProtocol      : ProtocolVersion(
                major       : 1,
                minimumMinor: 0
            ),
            offer                 : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            ),
            authorizedPublications: [scope.publicationID]
        )
        let output = try publications.prepareOutput(
            ProviderOutput(
                schemaVersion: 1,
                publications : [publication],
                operations   : [],
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            generation: connection.generation,
            sequence  : 1
        )
        let proposal = try assets.prepareOutput(
            output,
            connectionToken: scope.connectionToken
        ) { _ in scope }
        try assets.validatePrepared(proposal)
        _ = try publications.commitPreparedOutput(
            output,
            at: now
        )
        assets.commitPrepared(proposal)
    }

    @Test
    func captureSurvivesImportRevocationAndIncludesFuturePrivacy() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        let backing = try await raster(coordinator)
        let original = scope()
        var assets = AssetState()
        let handle = try assets.insert(
            backing: backing,
            scope  : original
        )
        let content = try publication(
            id     : original.publicationID,
            aliases: [handle.assetID],
            future : true
        )
        try publishImported(
            assets     : &assets,
            scope      : original,
            publication: content
        )
        assets.revokeImports(connectionToken: original.connectionToken)
        let bytes = assets.retainedBytes
        var count = 0
        try assets.forEachArchivedPin(
            publication: content,
            owner      : owner,
            at         : now
        ) { alias, captured, hasPublic, hasSensitive in
            count += 1
            #expect(alias == handle.assetID)
            #expect(captured === backing)
            #expect(hasPublic && hasSensitive)
        }
        #expect(count == 1)
        #expect(assets.retainedBytes == bytes)
        #expect(throws: AddonFailure.self) {
            try assets.releaseImport(
                assetID: handle.assetID,
                scope  : original
            )
        }
    }

    @Test
    func captureRejectsWrongOwnerRevisionExpiryAndReferenceSetBeforeVisitor() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        let original = scope()
        var assets = AssetState()
        let alias = try assets.insert(
            backing: await raster(coordinator),
            scope  : original
        ).assetID
        let content = try publication(
            id     : original.publicationID,
            aliases: [alias]
        )
        try publishImported(
            assets     : &assets,
            scope      : original,
            publication: content
        )
        let wrongRevision = try publication(
            id      : original.publicationID,
            aliases : [alias],
            revision: 1
        )
        let wrongExpiry = try Publication(
            id         : content.id,
            revision   : content.revision,
            kind       : content.kind,
            content    : content.content,
            timeline   : content.timeline,
            expiresAt  : now.addingTimeInterval(30),
            stalePolicy: content.stalePolicy
        )
        let missingReference = try publication(
            id     : original.publicationID,
            aliases: []
        )
        let extraReference = try publication(
            id     : original.publicationID,
            aliases: [alias, "extra"]
        )
        let wrongPrivacy = try publication(
            id     : original.publicationID,
            aliases: [alias],
            future : true
        )
        for (candidate, candidateOwner, date) in [
            (content, foreignOwner, now),
            (wrongRevision, owner, now),
            (wrongExpiry, owner, now),
            (missingReference, owner, now),
            (extraReference, owner, now),
            (wrongPrivacy, owner, now),
            (content, owner, content.expiresAt),
            (content, owner, Date(timeIntervalSince1970: .nan)),
        ] {
            var visits = 0
            #expect(throws: AddonFailure.self) {
                try assets.forEachArchivedPin(
                    publication: candidate,
                    owner      : candidateOwner,
                    at         : date
                ) { _, _, _, _ in visits += 1 }
            }
            #expect(visits == 0)
        }
        let assetless = try publication(
            id     : scope().publicationID,
            aliases: []
        )
        var visits = 0
        try assets.forEachArchivedPin(
            publication: assetless,
            owner      : owner,
            at         : now
        ) { _, _, _, _ in visits += 1 }
        #expect(visits == 0)
    }

    @Test
    func directPinsHaveExactChargeAndNoImportAuthority() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        let backing = try await raster(coordinator)
        let original = scope()
        let content = try publication(
            id     : original.publicationID,
            aliases: ["fresh-a", "fresh-b"],
            future : true
        )
        var publications = PublicationState()
        let restoration = try restored(
            [content],
            in: publications
        )
        let inputs = [content.id: ["fresh-a": backing, "fresh-b": backing]]
        var assets = AssetState(maximumRetainedBytes: 4_096)
        #expect(try assets.restorationPreparationBytes(
            restoration,
            backings: inputs
        ) == 4_096)
        let proposal = try assets.prepareRestoration(
            restoration,
            backings: inputs
        )
        #expect(proposal.estimatedBytes == 4_096)
        #expect(proposal.requiredGrowth == 4_096)
        #expect(proposal.retainedBytesAfter == 4_096)
        #expect(assets.retainedBytes == 0)
        try publications.validatePreparedRestoration(
            restoration,
            at: now
        )
        try assets.validatePrepared(proposal)
        publications.commitPreparedRestoration(restoration)
        assets.commitPrepared(proposal)
        #expect(assets.retainedBytes(owner: owner) == 4_096)
        var visits = 0
        try assets.forEachArchivedPin(
            publication: content,
            owner      : owner,
            at         : now
        ) { _, captured, hasPublic, hasSensitive in
            visits += 1
            #expect(captured === backing)
            #expect(hasPublic && hasSensitive)
        }
        #expect(visits == 2)
        #expect(throws: AddonFailure.self) {
            try assets.releaseImport(
                assetID: "fresh-a",
                scope  : original
            )
        }
        #expect(throws: AddonFailure.self) {
            try assets.prepareRestoration(
                restoration,
                backings: inputs
            )
        }
    }

    @Test
    func directRestorationRejectsIncompleteForeignAndTerminalInputsAtomically() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        let backing = try await raster(coordinator)
        let foreign = try await raster(
            coordinator,
            owner: foreignOwner
        )
        let content = try publication(
            id     : scope().publicationID,
            aliases: ["fresh"]
        )
        let restoration = try restored([content])
        let assets = AssetState()
        for input in [
            [:],
            [content.id: [:]],
            [content.id: ["fresh": backing, "extra": backing]],
            [content.id: ["fresh": foreign]],
            [scope().publicationID: ["fresh": backing]],
        ] as [[PublicationID: [String: AssetRasterBacking]]] {
            #expect(throws: AddonFailure.self) {
                try assets.prepareRestoration(
                    restoration,
                    backings: input
                )
            }
            #expect(assets.retainedBytes == 0)
        }
        let elapsed = try restored(
            [content],
            at: content.expiresAt
        )
        #expect(throws: AddonFailure.self) {
            try assets.prepareRestoration(
                elapsed,
                backings: [content.id: ["fresh": backing]]
            )
        }
        let terminalProposal = try assets.prepareRestoration(
            elapsed,
            backings: [:]
        )
        #expect(terminalProposal.estimatedBytes == 0)
        #expect(terminalProposal.requiredGrowth == 0)
        let tooSmall = AssetState(maximumRetainedBytes: 3_071)
        #expect(throws: AddonFailure.self) {
            try tooSmall.restorationPreparationBytes(
                restoration,
                backings: [content.id: ["fresh": backing]]
            )
        }
        #expect(tooSmall.retainedBytes == 0)
    }

    @Test
    func copiedDivergentHistoriesRejectProposalWithEqualNumericRevision() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        let backing = try await raster(coordinator)
        let original = scope()
        let empty = AssetState()
        var first = empty
        var second = empty
        let handle = try first.insert(
            backing: backing,
            scope  : original
        )
        try first.releaseImport(
            assetID: handle.assetID,
            scope  : original
        )
        _ = try second.insert(
            backing: backing,
            scope  : original
        )
        _ = try second.insert(
            backing: backing,
            scope  : original
        )
        let content = try publication(
            id     : scope().publicationID,
            aliases: ["fresh"]
        )
        let restoration = try restored([content])
        let proposal = try first.prepareRestoration(
            restoration,
            backings: [content.id: ["fresh": backing]]
        )
        #expect(first.retainedBytes == 0)
        #expect(second.retainedBytes == 8_192)
        #expect(throws: AddonFailure.self) { try second.validatePrepared(proposal) }
        #expect(throws: AddonFailure.self) { try AssetState().validatePrepared(proposal) }
        try first.validatePrepared(proposal)
        first.commitPrepared(proposal)
        #expect(first.retainedBytes == 3_072)
        #expect(first.image(
            assetID            : "fresh",
            publicationID      : content.id,
            publicationRevision: content.revision,
            at                 : now
        ) === backing.image)
        #expect(second.retainedBytes == 8_192)
        #expect(throws: AddonFailure.self) { try first.validatePrepared(proposal) }
    }

    @Test
    func canonicalCopyPreservesNativeBytesWithinPrepaidScopes() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let pixels = Data([255, 0, 0, 255, 0, 128, 0, 128])
        let backing = try await coordinator.create(
            pixels: pixels,
            width : 2,
            height: 1,
            owner : owner
        )
        let scratch = try AssetRasterArchiveCopy.scratchBytes(
            backing: backing,
            owner  : owner
        )
        #expect(scratch == 16)
        let worker = AssetRasterArchiveCopy()
        try await governor.withAssetDecodeReservation(
            bytes: pixels.count,
            owner: owner
        ) {
            try await governor.withAssetDecodeReservation(
                bytes: scratch,
                owner: owner
            ) {
                let copied = try await worker.copy(
                    backing: backing,
                    owner  : owner
                )
                #expect(copied == pixels)
            }
        }
        #expect(throws: AddonFailure.self) {
            try AssetRasterArchiveCopy.scratchBytes(
                backing: backing,
                owner  : foreignOwner
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await worker.copy(
                backing: backing,
                owner  : foreignOwner
            )
        }
    }

    @Test
    func restorationRejectsCurrentAndBatchAliasCollisionsWithoutChangingOwnership() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        let backing = try await raster(coordinator)
        let original = scope()
        var assets = AssetState()
        let alias = try assets.insert(
            backing: backing,
            scope  : original
        ).assetID
        let content = try publication(
            id     : scope().publicationID,
            aliases: [alias]
        )
        let proposal = try restored([content])
        #expect(throws: AddonFailure.self) {
            try assets.prepareRestoration(
                proposal,
                backings: [content.id: [alias: backing]]
            )
        }
        #expect(assets.retainedBytes == 4_096)
        let originalContent = try publication(
            id     : original.publicationID,
            aliases: [alias]
        )
        try publishImported(
            assets     : &assets,
            scope      : original,
            publication: originalContent
        )
        assets.revokeImports(connectionToken: original.connectionToken)
        #expect(throws: AddonFailure.self) {
            try assets.prepareRestoration(
                proposal,
                backings: [content.id: [alias: backing]]
            )
        }
        #expect(assets.retainedBytes == 3_072)
        let other = try publication(
            id     : scope().publicationID,
            aliases: [alias]
        )
        let batch = try restored([content, other])
        #expect(throws: AddonFailure.self) {
            try AssetState().prepareRestoration(
                batch,
                backings: [content.id: [alias: backing], other.id: [alias: backing]]
            )
        }
    }

    @Test
    func allRepresentationsContributeDistinctAndCombinedPrivacyFlags() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        let backing = try await raster(coordinator)
        let publicDocument = try ContentDocument(
            root              : .text("Public"),
            privacy           : .publicContent,
            accessibilityLabel: "Public",
            assetIDs          : ["public", "both"]
        )
        let sensitiveDocument = try ContentDocument(
            root              : .text("Private"),
            privacy           : .sensitive,
            accessibilityLabel: "Private",
            assetIDs          : ["sensitive", "both"]
        )
        let content = try Publication(
            id         : scope().publicationID,
            revision   : 0,
            kind       : .activity,
            content    : PresentationSet(
                widget         : publicDocument,
                compactLeading : sensitiveDocument,
                compactTrailing: publicDocument,
                minimal        : sensitiveDocument,
                expanded       : publicDocument
            ),
            timeline   : nil,
            expiresAt  : now.addingTimeInterval(60),
            stalePolicy: .retainMarked
        )
        var assets = AssetState()
        let proposal = try assets.prepareRestoration(
            restored([content]),
            backings: [content.id: ["public": backing, "sensitive": backing, "both": backing]]
        )
        #expect(proposal.requiredGrowth == 5_120)
        try assets.validatePrepared(proposal)
        assets.commitPrepared(proposal)
        var aliases: Set<String> = []
        try assets.forEachArchivedPin(
            publication: content,
            owner      : owner,
            at         : now
        ) { alias, _, hasPublic, hasSensitive in
            aliases.insert(alias)
            #expect(hasPublic == (alias != "sensitive"))
            #expect(hasSensitive == (alias != "public"))
        }
        #expect(aliases == ["public", "sensitive", "both"])
    }

    @Test(arguments: ArchiveRasterConstruction.Mode.allCases)
    fileprivate func copyRejectsNoncanonicalNativeFormats(_ mode: ArchiveRasterConstruction.Mode) async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(
            governor    : governor,
            construction: ArchiveRasterConstruction(mode: mode)
        )
        let backing = try await raster(coordinator)
        #expect(throws: AddonFailure.self) {
            try AssetRasterArchiveCopy.scratchBytes(
                backing: backing,
                owner  : owner
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await AssetRasterArchiveCopy().copy(
                backing: backing,
                owner  : owner
            )
        }
        #expect(await governor.usage(.assetBytes) == 4)
    }

    @Test
    func restoredPinAndBorrowedImageKeepActualRasterAlive() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var assets = AssetState()
        let content = try publication(
            id     : scope().publicationID,
            aliases: ["fresh"]
        )
        do {
            let backing = try await raster(coordinator)
            let proposal = try assets.prepareRestoration(
                restored([content]),
                backings: [content.id: ["fresh": backing]]
            )
            try assets.validatePrepared(proposal)
            assets.commitPrepared(proposal)
        }
        var borrowed = assets.image(
            assetID            : "fresh",
            publicationID      : content.id,
            publicationRevision: content.revision,
            at                 : now
        )
        #expect(borrowed != nil)
        assets.removeOwner(owner)
        try await coordinator.flushDisposed()
        #expect(coordinator.status().slots == 1)
        #expect(await governor.usage(.assetBytes) == 4)
        #expect(borrowed?.width == 1)
        borrowed = nil
        try await coordinator.flushDisposed()
        #expect(coordinator.status().slots == 0)
        #expect(await governor.usage(.assetBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }
}

/// ArchiveRasterConstruction preserves native provider ownership while varying image metadata.
private struct ArchiveRasterConstruction: AssetRasterConstruction {
    enum Mode: CaseIterable, Sendable {
        case alpha
        case colorSpace
        case interpolation
    }

    let mode: Mode
    private let native = NativeAssetRasterConstruction()

    func allocate(bytes: Int) -> UnsafeMutableRawPointer? {
        native.allocate(bytes: bytes)
    }

    func deallocate(
        _ pointer: UnsafeMutableRawPointer,
        bytes    : Int
    ) {
        native.deallocate(
            pointer,
            bytes: bytes
        )
    }

    func provider(context: AssetRasterProviderContext) -> CGDataProvider? {
        native.provider(context: context)
    }

    func colorSpace() -> CGColorSpace? {
        mode == .colorSpace ? CGColorSpace(name: CGColorSpace.displayP3) : native.colorSpace()
    }

    func image(
        layout    : AssetRasterLayout,
        provider  : CGDataProvider,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        let alphaInfo = mode == .alpha ? CGImageAlphaInfo.last : CGImageAlphaInfo.premultipliedLast
        return CGImage(
            width            : layout.width,
            height           : layout.height,
            bitsPerComponent : 8,
            bitsPerPixel     : 32,
            bytesPerRow      : layout.rowBytes,
            space            : colorSpace,
            bitmapInfo       : CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | alphaInfo.rawValue),
            provider         : provider,
            decode           : nil,
            shouldInterpolate: mode == .interpolation,
            intent           : .defaultIntent
        )
    }
}
