//
//  AssetState.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation

/// AssetState owns synchronous canonical asset ownership directly within AddonRuntime.
/// Scope is supplied only after the runtime checks current host assignment and connection;
/// neither an addon claim nor ContentDocument.Privacy grants that authority.
struct AssetState: Sendable {
    /// Scope carries the immutable host-verified assignment for one connection import.
    struct Scope: Hashable, Sendable {
        let identity        : VerifiedAddonIdentity
        let verifiedDigest  : String
        let featureID       : String
        let publicationID   : PublicationID
        let connectionToken : UUID
        let privacyPartition: AssetPrivacyPartition

        init(
            identity        : VerifiedAddonIdentity,
            verifiedDigest  : String,
            featureID       : String,
            publicationID   : PublicationID,
            connectionToken : UUID,
            privacyPartition: AssetPrivacyPartition = .addonOwned
        ) {
            self.identity         = identity
            self.verifiedDigest   = verifiedDigest
            self.featureID        = featureID
            self.publicationID    = publicationID
            self.connectionToken  = connectionToken
            self.privacyPartition = privacyPartition
        }
    }

    /// AssetHandle exposes common validated metadata without widening host authority.
    typealias AssetHandle = CascadeContracts.AssetHandle

    /// PreparedOutput borrows admitted backings without granting publication authority.
    /// Its metadata remains charged by the runtime until the proposal leaves scope.
    struct PreparedOutput: Sendable {
        fileprivate let authorityID    : UUID
        fileprivate let stateRevision  : UInt64
        fileprivate let changes        : [PublicationID: Change]
        fileprivate let totalBytesAfter: Int
        let owner                      : AddonID
        let retainedBytesAfter         : Int
        let requiredGrowth             : Int
        let estimatedBytes             : Int
    }

    private struct Import: Sendable {
        let scope  : Scope
        let backing: AssetRasterBacking
    }

    /// Pin retains document privacy as reference metadata, independently of authority.
    /// One alias can appear in both public and sensitive documents in a publication.
    fileprivate struct Pin: Sendable {
        let backing              : AssetRasterBacking
        var hasPublicReference   : Bool
        var hasSensitiveReference: Bool
    }

    /// Binding owns every retained timeline reference for one exact publication revision.
    fileprivate struct Binding: Sendable {
        let revision : UInt64
        let expiresAt: Date
        let pins     : [String: Pin]

        var charge: Int {
            MetadataCharge.publication + pins.count * MetadataCharge.pin
        }
    }

    fileprivate enum Change: Sendable {
        case bind(Binding)
        case end
    }

    /// MetadataCharge includes bounded strings, dictionary slack, removal proposals, and
    /// overlapping old/new table storage during compaction. Charges remain reserved until
    /// synchronous cleanup and its proposal leave scope, before the owner pool shrinks.
    fileprivate enum MetadataCharge {
        static let imported    = 4_096
        static let publication = 2_048
        static let pin         = 1_024
    }

    static let maximumStateBytes = 8 * 1_024 * 1_024

    private let maximumRetainedBytes: Int
    private var authorityID         = UUID()
    private var stateRevision       : UInt64                   = 0
    private var isRevisionExhausted                             = false
    private var imports             : [String: Import]         = [:]
    private var bindings            : [PublicationID: Binding] = [:]
    private(set) var retainedBytes                             = 0

    init(maximumRetainedBytes: Int = maximumStateBytes) {
        self.maximumRetainedBytes = min(
            Self.maximumStateBytes,
            max(
                0,
                maximumRetainedBytes
            )
        )
    }

    /// retainedBytes reports the canonical metadata charge attributed to one owner pool.
    func retainedBytes(owner: AddonID) -> Int {
        let importBytes = imports.values.reduce(0) { bytes, imported in
            bytes + (imported.scope.identity.addonID == owner ? MetadataCharge.imported : 0)
        }
        let bindingBytes = bindings.reduce(0) { bytes, entry in
            bytes + (entry.key.addonID == owner ? entry.value.charge : 0)
        }
        return importBytes + bindingBytes
    }

    /// importAdmissionBytes exposes the growth the runtime prepays before insertion.
    func importAdmissionBytes(scope: Scope) throws -> Int {
        try validateScope(scope)
        try requireCapacity(additional: MetadataCharge.imported)
        return MetadataCharge.imported
    }

    /// sharingAdmissionBytes validates both scopes before quoting one new alias charge.
    /// The original import must remain current; retained publication pins grant no share.
    func sharingAdmissionBytes(
        assetID: String,
        source : Scope,
        target : Scope
    ) throws -> Int {
        _ = try sharingSource(
            assetID: assetID,
            source : source,
            target : target
        )
        return try importAdmissionBytes(scope: target)
    }

    /// share creates a fresh target-publication alias over the same immutable backing.
    /// Revalidation happens synchronously with insertion, so a prior quote cannot revive
    /// a released alias. No decoder, pixel copy, or new physical reservation is involved.
    mutating func share(
        assetID: String,
        source : Scope,
        target : Scope
    ) throws -> AssetHandle {
        let imported = try sharingSource(
            assetID: assetID,
            source : source,
            target : target
        )
        return try insert(
            backing: imported.backing,
            scope  : target
        )
    }

    /// sharingSource requires the exact stored source and compatible host assignments.
    /// Feature and publication may differ only through this explicit sharing operation;
    /// publisher, addon, digest, connection, and host privacy partition remain identical.
    private func sharingSource(
        assetID: String,
        source : Scope,
        target : Scope
    ) throws -> Import {
        guard let imported = imports[assetID], imported.scope == source else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "Asset sharing requires a current exact-scope source alias."
            )
        }
        guard source.identity == target.identity,
              source.verifiedDigest == target.verifiedDigest,
              source.connectionToken == target.connectionToken,
              source.privacyPartition == target.privacyPartition else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "Asset sharing assignments are not compatible."
            )
        }
        try validateScope(target)
        return imported
    }

    /// insert retains a decoded backing only after scope and metadata admission succeed.
    /// Pixel lifetime accounting remains exclusively with its existing disposal coordinator.
    mutating func insert(
        backing: AssetRasterBacking,
        scope  : Scope
    ) throws -> AssetHandle {
        let charge = try importAdmissionBytes(scope: scope)
        guard backing.owner == scope.identity.addonID else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "Raster accounting owner does not match asset scope."
            )
        }
        let alias = "asset-" + UUID().uuidString
        // A collision must not replace a live import, even though UUID collision is negligible.
        guard imports[alias] == nil else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Asset identity collision."
            )
        }
        let handle = try AssetHandle(
            assetID       : alias,
            owner         : backing.owner,
            publicationID : scope.publicationID,
            rasterRevision: 1,
            width         : backing.image.width,
            height        : backing.image.height,
            byteCount     : backing.image.bytesPerRow * backing.image.height
        )
        imports[alias] = Import(
            scope  : scope,
            backing: backing
        )
        retainedBytes += charge
        advanceRevision()
        return handle
    }

    /// preparationBytes scans without allocation and counts duplicate references too.
    /// New bindings need a complete additive proposal reservation while canonical state
    /// stays live. Removal-only changes fit inside their existing fixed metadata charges,
    /// which remain reserved until the synchronous commit and proposal leave scope. A
    /// mixed batch never funds new pins with refunds from its proposed removals.
    func preparationBytes(_ output: PublicationState.PreparedOutput) throws -> Int {
        var bytes = 0
        try output.forEachChangedPublication { publication in
            var hasChargedBinding = false
            try publication.forEachAssetReference { _, _ in
                if !hasChargedBinding {
                    try addCharge(
                        MetadataCharge.publication,
                        to: &bytes
                    )
                    hasChargedBinding = true
                }
                try addCharge(
                    MetadataCharge.pin,
                    to: &bytes
                )
            }
        }
        try requireCapacity(additional: bytes)
        return bytes
    }

    /// prepareOutput validates every reference against the exact current import scope.
    /// Failed batches discard their borrowed proposal without changing canonical bindings.
    func prepareOutput(
        _ output           : PublicationState.PreparedOutput,
        connectionToken    : UUID,
        scopeForPublication: (PublicationID) throws -> Scope
    ) throws -> PreparedOutput {
        let estimate = try preparationBytes(output)
        var changes             : [PublicationID: Change] = [:]
        var projectedBytes                                = retainedBytes
        var projectedOwnerBytes                           = retainedBytes(owner: output.owner)
        try output.forEachChangedPublication { publication in
            let scope = try scopeForPublication(publication.id)
            try validateScope(scope)
            guard scope.publicationID == publication.id,
                  scope.identity.addonID == output.owner,
                  scope.connectionToken == connectionToken else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "Asset publication scope does not match current host authority."
                )
            }
            var pins: [String: Pin] = [:]
            try publication.forEachAssetReference { alias, privacy in
                guard let imported = imports[alias], imported.scope == scope else {
                    throw AddonFailure(
                        code  : .permissionDenied,
                        reason: "Asset alias is not imported by this publication and connection."
                    )
                }
                var pin = pins[alias] ?? Pin(
                    backing              : imported.backing,
                    hasPublicReference   : false,
                    hasSensitiveReference: false
                )
                switch privacy {
                case .publicContent:
                    pin.hasPublicReference = true
                case .sensitive:
                    pin.hasSensitiveReference = true
                }
                pins[alias] = pin
            }
            guard !pins.isEmpty || bindings[publication.id] != nil else {
                return
            }
            let binding = Binding(
                revision : publication.revision,
                expiresAt: publication.expiresAt,
                pins     : pins
            )
            let previousCharge = bindings[publication.id]?.charge ?? 0
            let chargeChange   = (pins.isEmpty ? 0 : binding.charge) - previousCharge
            projectedBytes += chargeChange
            projectedOwnerBytes += chargeChange
            changes[publication.id] = .bind(binding)
        }
        output.forEachEndedPublicationID { publicationID in
            let importBytes = imports.values.reduce(0) { bytes, imported in
                bytes + (imported.scope.publicationID == publicationID ? MetadataCharge.imported : 0)
            }
            let removedBytes = (bindings[publicationID]?.charge ?? 0) + importBytes
            guard removedBytes > 0 else {
                return
            }
            projectedBytes -= removedBytes
            projectedOwnerBytes -= removedBytes
            changes[publicationID] = .end
        }
        return PreparedOutput(
            authorityID       : authorityID,
            stateRevision     : stateRevision,
            changes           : changes,
            totalBytesAfter   : projectedBytes,
            owner             : output.owner,
            retainedBytesAfter: projectedOwnerBytes,
            requiredGrowth    : max(
                0,
                projectedOwnerBytes - retainedBytes(owner: output.owner)
            ),
            estimatedBytes    : estimate
        )
    }

    /// forEachArchivedPin borrows exact canonical pins after verifying the entire binding.
    /// The host supplies its canonical publication, owner and capture clock in one synchronous
    /// turn. No callback runs for a mismatched graph, even if its ID and revision were copied.
    /// Borrowed backings keep their native lifetime charge; retained capture tables need their
    /// own caller admission. This visitor grants no import, share or connection authority.
    func forEachArchivedPin(
        publication: Publication,
        owner      : AddonID,
        at instant : Date,
        _ visit    : (String, AssetRasterBacking, Bool, Bool) throws -> Void
    ) throws {
        guard publication.id.addonID == owner,
              publication.kind != .notice,
              instant.timeIntervalSince1970.isFinite,
              publication.expiresAt > instant else {
            throw Self.archiveFailure("Asset capture requires a current owner publication.")
        }
        let binding = bindings[publication.id]
        if let binding {
            guard binding.revision == publication.revision,
                  binding.expiresAt == publication.expiresAt else {
                throw Self.archiveFailure("Asset capture does not match the canonical revision and expiry.")
            }
        }
        try publication.forEachAssetReference { alias, _ in
            guard binding?.pins[alias] != nil else {
                throw Self.archiveFailure("Asset capture is missing a canonical pin.")
            }
        }
        guard let binding else {
            return
        }
        // Validate before calling user code, without retaining a second reference table.
        // Cold archive capture is bounded by existing publication and asset-state quotas.
        for (alias, pin) in binding.pins {
            var hasPublic = false
            var hasSensitive = false
            publication.forEachAssetReference { reference, privacy in
                guard reference == alias else {
                    return
                }
                switch privacy {
                case .publicContent:
                    hasPublic = true
                case .sensitive:
                    hasSensitive = true
                }
            }
            guard pin.backing.owner == owner,
                  hasPublic || hasSensitive,
                  pin.hasPublicReference == hasPublic,
                  pin.hasSensitiveReference == hasSensitive else {
                throw Self.archiveFailure("Asset capture references differ from the canonical binding.")
            }
        }
        for (alias, pin) in binding.pins {
            try visit(
                alias,
                pin.backing,
                pin.hasPublicReference,
                pin.hasSensitiveReference
            )
        }
    }

    /// restorationMetadataBytes bounds persistent direct-pin growth before any proposal allocation.
    /// Binding count includes only nonempty live bindings; aliases count distinct per-publication pins.
    func restorationMetadataBytes(
        bindingCount: Int,
        aliasCount  : Int
    ) throws -> Int {
        try requireCapacity(additional: 0)
        guard bindingCount >= 0, aliasCount >= 0, bindingCount <= aliasCount,
              (bindingCount == 0) == (aliasCount == 0),
              bindingCount <= (maximumRetainedBytes - retainedBytes) / MetadataCharge.publication else {
            throw Self.archiveFailure("Invalid or oversized restoration metadata counts.")
        }
        let bindingBytes = bindingCount * MetadataCharge.publication
        guard aliasCount <= (maximumRetainedBytes - retainedBytes - bindingBytes) / MetadataCharge.pin else {
            throw Self.archiveFailure("Restoration pin metadata exceeds the retained-state budget.")
        }
        return bindingBytes + aliasCount * MetadataCharge.pin
    }

    /// restorationPreparationBytes validates host-only direct bindings without allocation.
    /// Inputs contain only final live publications and freshly assigned aliases. The caller
    /// already protects their storage. Each new binding reserves 2048 bytes and each distinct
    /// alias 1024 bytes, including proposal/table overlap; no future removal funds admission.
    /// Empty entries are optional for live assetless publications and incur no retained charge.
    func restorationPreparationBytes(
        _ restoration: PublicationState.PreparedRestoration,
        backings     : [PublicationID: [String: AssetRasterBacking]]
    ) throws -> Int {
        try requireCapacity(additional: 0)
        guard backings.count <= maximumRetainedBytes / MetadataCharge.publication else {
            throw Self.archiveFailure("Restored asset input exceeds the bounded publication table.")
        }
        var estimate = 0
        for aliases in backings.values where !aliases.isEmpty {
            try addCharge(
                MetadataCharge.publication,
                to: &estimate
            )
            guard aliases.count <= (maximumRetainedBytes - retainedBytes - estimate) / MetadataCharge.pin else {
                throw Self.archiveFailure("Restored asset aliases exceed the metadata budget.")
            }
            try addCharge(
                aliases.count * MetadataCharge.pin,
                to: &estimate
            )
        }
        var matchedInputs = 0
        try restoration.forEachRestoredPublication { publication in
            try requireUnboundRestorationID(publication.id)
            guard publication.id.addonID == restoration.owner else {
                throw Self.archiveFailure("Restored asset publication has a foreign owner.")
            }
            if backings[publication.id] != nil {
                matchedInputs += 1
            }
            try publication.forEachAssetReference { alias, _ in
                guard backings[publication.id]?[alias] != nil else {
                    throw Self.archiveFailure("Restored publication is missing an admitted backing.")
                }
            }
            guard let aliases = backings[publication.id] else {
                return
            }
            for (alias, backing) in aliases {
                guard backing.owner == restoration.owner,
                      imports[alias] == nil,
                      !bindings.values.contains(where: { $0.pins[alias] != nil }) else {
                    throw Self.archiveFailure("Restored backing owner or alias collides with canonical assets.")
                }
                var referenced = false
                publication.forEachAssetReference { reference, _ in
                    if reference == alias {
                        referenced = true
                    }
                }
                guard referenced,
                      !backings.contains(where: { $0.key != publication.id && $0.value[alias] != nil }) else {
                    throw Self.archiveFailure("Restoration contains an extra or reused asset alias.")
                }
            }
        }
        try restoration.forEachTerminalPublicationID { publicationID in
            try requireUnboundRestorationID(publicationID)
        }
        guard matchedInputs == backings.count else {
            throw Self.archiveFailure("Asset inputs include a terminal or unrelated publication.")
        }
        return estimate
    }

    /// prepareRestoration creates fresh canonical pins over already admitted native backings.
    /// No Import or provider capability is synthesized. The runtime validates both publication
    /// and asset proposals at its final clock, then commits both without suspension. Inputs and
    /// this proposal must stay prepaid until their references disappear or canonical pins own
    /// the persistent charge; preparation alone does not authorize image resolution.
    func prepareRestoration(
        _ restoration: PublicationState.PreparedRestoration,
        backings     : [PublicationID: [String: AssetRasterBacking]]
    ) throws -> PreparedOutput {
        let estimate = try restorationPreparationBytes(
            restoration,
            backings: backings
        )
        var changes: [PublicationID: Change] = [:]
        restoration.forEachRestoredPublication { publication in
            guard let aliases = backings[publication.id], !aliases.isEmpty else {
                return
            }
            var pins: [String: Pin] = [:]
            publication.forEachAssetReference { alias, privacy in
                // The complete immutable input was checked before any proposal allocation.
                guard let backing = aliases[alias] else {
                    preconditionFailure("Validated restoration backing disappeared.")
                }
                var pin = pins[alias] ?? Pin(
                    backing              : backing,
                    hasPublicReference   : false,
                    hasSensitiveReference: false
                )
                switch privacy {
                case .publicContent:
                    pin.hasPublicReference = true
                case .sensitive:
                    pin.hasSensitiveReference = true
                }
                pins[alias] = pin
            }
            changes[publication.id] = .bind(Binding(
                revision : publication.revision,
                expiresAt: publication.expiresAt,
                pins     : pins
            ))
        }
        return PreparedOutput(
            authorityID       : authorityID,
            stateRevision     : stateRevision,
            changes           : changes,
            totalBytesAfter   : retainedBytes + estimate,
            owner             : restoration.owner,
            retainedBytesAfter: retainedBytes(owner: restoration.owner) + estimate,
            requiredGrowth    : estimate,
            estimatedBytes    : estimate
        )
    }

    /// requireUnboundRestorationID rejects restoration over existing pins or pending imports.
    private func requireUnboundRestorationID(_ publicationID: PublicationID) throws {
        guard bindings[publicationID] == nil,
              !imports.values.contains(where: { $0.scope.publicationID == publicationID }) else {
            throw Self.archiveFailure("Restored publication collides with existing asset ownership.")
        }
    }

    /// archiveFailure reports invalid host archive proposals without changing canonical state.
    private static func archiveFailure(_ reason: String) -> AddonFailure {
        AddonFailure(
            code  : .invalidPayload,
            reason: reason
        )
    }

    /// validatePrepared rejects proposals created by another state or before a mutation.
    func validatePrepared(_ prepared: PreparedOutput) throws {
        guard !isRevisionExhausted,
              prepared.authorityID == authorityID,
              prepared.stateRevision == stateRevision else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "Prepared asset authority changed before commit."
            )
        }
    }

    /// commitPrepared runs immediately after validatePrepared and canonical publication
    /// commit in one synchronous runtime turn. No suspension or asset mutation may intervene.
    /// A proposal cannot introduce a fallible check after publication state has committed.
    mutating func commitPrepared(_ prepared: PreparedOutput) {
        precondition(
            !isRevisionExhausted
                && prepared.authorityID == authorityID
                && prepared.stateRevision == stateRevision
        )
        guard !prepared.changes.isEmpty else {
            advanceRevision()
            return
        }
        for (publicationID, change) in prepared.changes {
            switch change {
            case .bind(let binding):
                if binding.pins.isEmpty {
                    bindings.removeValue(forKey: publicationID)
                } else {
                    bindings[publicationID] = binding
                }
            case .end:
                bindings.removeValue(forKey: publicationID)
            }
        }
        compactImports { imported in
            if case .end? = prepared.changes[imported.scope.publicationID] {
                return false
            }
            return true
        }
        compactBindings { _, _ in true }
        retainedBytes = prepared.totalBytesAfter
        advanceRevision()
    }

    /// releaseImport revokes one exact-scope alias without removing publication pins.
    /// Metadata shrinks immediately; the backing coordinator refunds pixels only after
    /// committed publications, pending proposals, and image consumers release them.
    mutating func releaseImport(
        assetID: String,
        scope  : Scope
    ) throws {
        guard let imported = imports[assetID], imported.scope == scope else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "Asset alias does not belong to this publication and connection."
            )
        }
        imports.removeValue(forKey: assetID)
        compactImports { _ in true }
        retainedBytes -= MetadataCharge.imported
        advanceRevision()
    }

    /// revokeImports removes connection aliases while published immutable backings survive.
    mutating func revokeImports(connectionToken: UUID) {
        let previousCount = imports.count
        compactImports { $0.scope.connectionToken != connectionToken }
        if imports.count != previousCount {
            recalculateBytes()
            advanceRevision()
        }
    }

    /// removeOwner drops logical ownership without refunding images retained by consumers.
    mutating func removeOwner(_ owner: AddonID) {
        let previousImportCount  = imports.count
        let previousBindingCount = bindings.count
        compactImports { $0.scope.identity.addonID != owner }
        compactBindings { publicationID, _ in publicationID.addonID != owner }
        if imports.count != previousImportCount || bindings.count != previousBindingCount {
            recalculateBytes()
            advanceRevision()
        }
    }

    /// reconcile checks retained canonical history, never the presentation projection.
    /// Unpublished import handles survive until their connection exits; known ended or
    /// expired publications lose imports and bindings without a separate timer or history.
    mutating func reconcile(
        publications: PublicationState,
        at instant  : Date
    ) {
        guard instant.timeIntervalSince1970.isFinite else {
            return
        }
        let previousImportCount  = imports.count
        let previousBindingCount = bindings.count
        compactImports { imported in
            let publicationID = imported.scope.publicationID
            return publications.recordAccounting(id: publicationID) == nil
                || publications.publication(
                    id: publicationID,
                    at: instant
                ) != nil
        }
        compactBindings { publicationID, binding in
            guard let publication = publications.publication(
                id: publicationID,
                at: instant
            ) else {
                return false
            }
            return publication.revision == binding.revision
        }
        if imports.count != previousImportCount || bindings.count != previousBindingCount {
            recalculateBytes()
            advanceRevision()
        }
    }

    /// image resolves only an exact, unexpired publication revision using host clock time.
    /// The returned CGImage retains its protected allocation independently of this state.
    func image(
        assetID            : String,
        publicationID      : PublicationID,
        publicationRevision: UInt64,
        at instant         : Date
    ) -> CGImage? {
        guard instant.timeIntervalSince1970.isFinite,
              let binding = bindings[publicationID],
              binding.revision == publicationRevision,
              instant < binding.expiresAt else {
            return nil
        }
        return binding.pins[assetID]?.backing.image
    }

    /// validateScope bounds host-supplied identity strings before fixed metadata admission.
    private func validateScope(_ scope: Scope) throws {
        guard scope.identity.addonID == scope.publicationID.addonID,
              !scope.identity.publisher.isEmpty,
              scope.identity.publisher.utf8.count <= 512,
              !scope.verifiedDigest.isEmpty,
              scope.verifiedDigest.utf8.count <= 512,
              !scope.featureID.isEmpty,
              scope.featureID.utf8.count <= 128 else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "Asset scope lacks bounded host-verified identity and assignment."
            )
        }
    }

    /// requireCapacity checks growth without allocation or overflowing quota arithmetic.
    private func requireCapacity(additional: Int) throws {
        guard !isRevisionExhausted,
              additional >= 0,
              additional <= maximumRetainedBytes - retainedBytes else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Asset retained-state metadata budget is exhausted."
            )
        }
    }

    /// addCharge bounds each proposed metadata entry before any proposal collection grows.
    private func addCharge(
        _ charge: Int,
        to bytes: inout Int
    ) throws {
        guard charge <= maximumRetainedBytes - retainedBytes - bytes else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Asset proposal metadata budget is exhausted."
            )
        }
        bytes += charge
    }

    /// compactImports rebuilds proportional table capacity inside the fixed entry charge.
    private mutating func compactImports(keeping keep: (Import) -> Bool) {
        let survivingCount = imports.values.reduce(0) { count, imported in
            count + (keep(imported) ? 1 : 0)
        }
        var compactedImports = Dictionary<String, Import>(minimumCapacity: survivingCount)
        for (alias, imported) in imports where keep(imported) {
            compactedImports[alias] = imported
        }
        imports = compactedImports
    }

    /// compactBindings releases historical table capacity after publication cleanup.
    private mutating func compactBindings(keeping keep: (PublicationID, Binding) -> Bool) {
        let survivingCount = bindings.reduce(0) { count, entry in
            count + (keep(
                entry.key,
                entry.value
            ) ? 1 : 0)
        }
        var compactedBindings = Dictionary<PublicationID, Binding>(minimumCapacity: survivingCount)
        for (publicationID, binding) in bindings where keep(
            publicationID,
            binding
        ) {
            compactedBindings[publicationID] = binding
        }
        bindings = compactedBindings
    }

    /// recalculateBytes updates canonical accounting after bounded removal operations.
    private mutating func recalculateBytes() {
        retainedBytes = imports.count * MetadataCharge.imported
            + bindings.values.reduce(0) { bytes, binding in bytes + binding.charge }
    }

    /// advanceRevision fails closed at exhaustion instead of replaying an earlier token.
    private mutating func advanceRevision() {
        authorityID = UUID()
        if stateRevision == UInt64.max {
            isRevisionExhausted = true
        } else {
            stateRevision += 1
        }
    }
}
