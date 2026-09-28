//
//  AddonRuntimeAssetLifecycleTestSupport.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

#if DEBUG
struct AssetLifecycleFixture: Sendable {
    let root        : URL
    let runtime     : AddonRuntime
    let governor    : ResourceGovernor
    let access      : GatedRuntimeResourceAccess
    let adapter     : RecordingRuntimeAdapter
    let connection  : RuntimeConnection
    let clock       : MutableRuntimeClock
    let ids         : [PublicationID]
    let owner       : AddonID
    let wall        : Date
    let companion   : RuntimeConnection?
    let companionID : PublicationID?

    /// make builds the fixture; mixedPrivacy gives the second host assignment an isolated asset
    /// privacy partition so a cross-private sharing refusal can be exercised against the real
    /// canonical scope check.
    static func make(mixedPrivacy: Bool = false, foreign: Bool = false) async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp/cascade-message-asset-\(UUID())")
        let keyedRoot = root.appendingPathComponent("keyed")
        let checkpoint = root.appendingPathComponent("checkpoint")
        let archive = root.appendingPathComponent("archive")
        for directory in [root, keyedRoot, checkpoint, archive] {
            try FileManager.default.createDirectory(
                at                         : directory,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
        }
        let action = try ActionFixture()
        let installed = try action.context().installed
        let other = foreign ? try ActionFixture(ownerName: "com.example.foreign").context().installed : nil
        let catalog = [installed] + (other.map { [$0] } ?? [])
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let storage = try await AddonStorageCoordinator.make(
            checkpointRoot: checkpoint,
            keyedRoot     : keyedRoot,
            archiveRoot   : archive,
            registrations : catalog.map {
                StateRegistration(identity: $0.verifiedIdentity, maximumSchemaVersion: 1)
            },
            governor      : governor,
            resourceAccess: governor
        )
        try await storage.start()
        let clock = MutableRuntimeClock(
            instant: RuntimeInstant(
                wall     : action.wall,
                monotonic: .zero
            )
        )
        let runtime = try await AddonRuntime.make(
            catalog    : catalog,
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : Dictionary(uniqueKeysWithValues: catalog.map { ($0.manifest.id, Set<String>()) }),
                explicitBindings: [],
                protocolVersion : (1, 2)
            ),
            governor              : governor,
            resourceAccess        : access,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock,
            storageCoordinator    : storage
        )
        var ids: [PublicationID] = []
        ids.append(
            try await runtime.assignPublication(
                owner     : installed.manifest.id,
                featureID : "controls",
                instanceID: UUID()
            )
        )
        ids.append(
            try await runtime.assignPublication(
                owner                : installed.manifest.id,
                featureID            : "controls",
                instanceID           : UUID(),
                assetPrivacyPartition: mixedPrivacy ? .isolated(UUID()) : .addonOwned
            )
        )
        let companionID: PublicationID?
        if let other, foreign {
            companionID = try await runtime.assignPublication(owner: other.manifest.id, featureID: "controls", instanceID: UUID())
        } else { companionID = nil }
        let launch = try await runtime.requestLaunch(owner: installed.manifest.id)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 2,
                contentSchemas: [1]
            )
        )
        let companion: RuntimeConnection?
        if let other {
            let otherLaunch = try await runtime.requestLaunch(owner: other.manifest.id)
            companion = try await runtime.attach(
                launchID: otherLaunch,
                offer: ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: 2, contentSchemas: [1])
            )
        } else { companion = nil }
        return Self(
            root      : root,
            runtime   : runtime,
            governor  : governor,
            access    : access,
            adapter   : adapter,
            connection: connection,
            clock     : clock,
            ids       : ids,
            owner     : installed.manifest.id,
            wall      : action.wall,
            companion : companion,
            companionID: companionID
        )
    }

    func content(_ asset: String?) throws -> PresentationSet {
        try PresentationSet(
            widget: ContentDocument(
                root              : .text("Image"),
                privacy           : .publicContent,
                accessibilityLabel: "Image",
                assetIDs          : asset.map { [$0] } ?? []
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
    }

    func publication(
        id      : PublicationID,
        asset   : String?,
        revision: UInt64 = 1
    ) throws -> Publication {
        try Publication(
            id         : id,
            revision   : revision,
            kind       : .widget,
            content    : content(asset),
            timeline   : nil,
            expiresAt  : wall.addingTimeInterval(60),
            stalePolicy: .remove
        )
    }

    func publish(
        _ publications: [Publication],
        sequence      : UInt64,
        ends          : [PublicationID] = []
    ) async throws -> PublicationAdmission {
        try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : ends.map { .endPublication($0) },
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            sequence  : sequence
        )
    }

    /// exchange forwards one real codec frame through the bridge and decodes the host reply.
    func exchange(
        _ request : AssetTransferRequest,
        sequence  : UInt64
    ) async throws -> AssetTransferResponse {
        try await rawExchange(request, sequence: sequence)
    }

    /// importAlias runs the real begin/chunk/finish frames for one single-chunk alias.
    func importAlias(
        _ png: Data,
        publicationID: PublicationID,
        sequences: (UInt64, UInt64, UInt64)
    ) async throws -> AssetHandle {
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: publicationID,
            totalBytes   : png.count
        )
        let begun = try await exchange(
            begin,
            sequence: sequences.0
        )
        let transferID = try #require(begun.transferID)
        let finishSequence = try await receiveAllChunks(png, transferID: transferID, startingAt: sequences.1)
        let finish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: transferID
        )
        let imported = try await exchange(
            finish,
            sequence: max(sequences.2, finishSequence)
        )
        return try #require(imported.assetHandle)
    }

    /// rawExchange drives one frame directly through the runtime (no bridge) and consumes the
    /// exact host receipt, returning the decoded reply. It is only used where a test deliberately
    /// rejects the handoff and the bridge would therefore refuse the frame.
    func rawExchange(
        _ request : AssetTransferRequest,
        sequence  : UInt64
    ) async throws -> AssetTransferResponse {
        let handle = try #require(
            adapter.stageAssetIngress(
                try AssetTransferFrameCodec.encode(
                    request,
                    profile: .v1
                ),
                incarnation: connection.incarnation,
                sequence   : sequence
            )
        )
        let result = await runtime.receiveAssetRequest(
            handle,
            connection: connection
        )
        guard case .completed(_, .handedOff) = result,
            case .assetResponse(let delivery)? = adapter.currentDelivery(incarnation: connection.incarnation)
        else {
            throw AddonFailure(
                code  : .dependencyUnavailable,
                reason: "The host did not hand off an asset reply."
            )
        }
        guard await runtime.receiveAssetReceipt(
            delivery.receipt,
            connection: connection
        ) else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "The exact asset receipt was refused."
            )
        }
        return try AssetTransferFrameCodec.decodeResponse(
            delivery.payload,
            profile: .v1
        )
    }

    /// rawResult stages and forwards one frame but returns the raw scalar host outcome, so a test
    /// can observe a rejected handoff without the bridge's own refusal.
    func rawResult(
        _ request : AssetTransferRequest,
        sequence  : UInt64
    ) async throws -> AddonRuntime.RuntimeAssetRequestResult {
        let handle = try #require(
            adapter.stageAssetIngress(
                try AssetTransferFrameCodec.encode(
                    request,
                    profile: .v1
                ),
                incarnation: connection.incarnation,
                sequence   : sequence
            )
        )
        return await runtime.receiveAssetRequest(
            handle,
            connection: connection
        )
    }

    func tearDown() async {
        await runtime.stop()
        // No invented exit: stopped logical fixtures retain their provider reservation.
        try? await runtime.flushDisposedAssetsForTesting()
        try? FileManager.default.removeItem(at: root)
    }
}

/// lifecyclePNG encodes an incompressible image so the compressed payload spans several 64 KiB chunks.
func lifecyclePNG(width: Int, height: Int) throws -> Data {
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    var bytes = [UInt8](
        repeating: 0,
        count: width * height * 4
    )
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    for index in bytes.indices {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        bytes[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 33)
    }
    let provider = try #require(
        CGDataProvider(data: Data(bytes) as CFData)
    )
    let image = try #require(
        CGImage(
            width             : width,
            height            : height,
            bitsPerComponent  : 8,
            bitsPerPixel      : 32,
            bytesPerRow       : width * 4,
            space             : colorSpace,
            bitmapInfo        : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider          : provider,
            decode            : nil,
            shouldInterpolate : false,
            intent            : .defaultIntent
        )
    )
    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        )
    )
    CGImageDestinationAddImage(
        destination,
        image,
        nil
    )
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}


/// AssetLifecycleGate owns one checkpoint and one waiter. Terminal notification wakes a test
/// when the real request returns before reaching the checkpoint, avoiding a stranded waiter.
final class AssetLifecycleGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var arrived = false
    private var terminal = false
    private var released = false
    private var waiter: CheckedContinuation<Bool, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    func waitForArrival() async -> Bool {
        await withCheckedContinuation { continuation in
            condition.lock()
            if arrived || terminal {
                let result = arrived
                condition.unlock()
                continuation.resume(returning: result)
            } else {
                precondition(waiter == nil)
                waiter = continuation
                condition.unlock()
            }
        }
    }

    func holdAdmission() async {
        await withCheckedContinuation { continuation in
            condition.lock()
            arrived = true
            let notify = waiter
            waiter = nil
            let alreadyReleased = released
            if !alreadyReleased { blocked = continuation }
            condition.unlock()
            notify?.resume(returning: true)
            if alreadyReleased { continuation.resume() }
        }
    }

    /// holdNative parks only the real off-main native worker, never the governor/runtime actor.
    func holdNative() {
        condition.lock()
        arrived = true
        let notify = waiter
        waiter = nil
        condition.unlock()
        notify?.resume(returning: true)
        condition.lock()
        while !released { condition.wait() }
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        let continuation = blocked
        blocked = nil
        condition.broadcast()
        condition.unlock()
        continuation?.resume()
    }

    func finished() {
        condition.lock()
        terminal = true
        let notify = waiter
        waiter = nil
        let result = arrived
        condition.unlock()
        notify?.resume(returning: result)
    }
}

/// AssetLifecycleObserver counts real entries and can hold exactly one selected checkpoint.
/// All authority, pixels and accounting come from the production operation being observed.
final class AssetLifecycleObserver: AssetLifecycleTestObserver, @unchecked Sendable {
    enum Point: String, CaseIterable, Sendable { case admission, native, none }
    struct Snapshot: Sendable {
        var reservationID: UUID?
        var binding: AssetTransferBinding?
        var admissions = 0
        var decodeEntries = 0
        var decodeReservations = 0
        var nativeDraws = 0
        var nativeReturns = 0
        var aliasCommits = 0
    }

    let governor: ResourceGovernor
    let point: Point
    let gate = AssetLifecycleGate()
    private let lock = NSLock()
    private var value = Snapshot()

    init(governor: ResourceGovernor, point: Point) {
        self.governor = governor
        self.point = point
    }

    func snapshot() -> Snapshot { lock.withLock { value } }

    func admittedTransfer(reservationID: UUID, binding: AssetTransferBinding) async {
        lock.withLock {
            value.reservationID = reservationID
            value.binding = binding
            value.admissions += 1
        }
        if point == .admission { await gate.holdAdmission() }
    }

    func decodeEntered() { lock.withLock { value.decodeEntries += 1 } }
    func decodeReservationEntered() { lock.withLock { value.decodeReservations += 1 } }
    func nativeDrawCompleted() {
        lock.withLock { value.nativeDraws += 1 }
        if point == .native { gate.holdNative() }
    }
    func nativeScopeReturned() { lock.withLock { value.nativeReturns += 1 } }
    func aliasCommitted() { lock.withLock { value.aliasCommits += 1 } }
}

extension AssetLifecycleFixture {
    /// withHeldRequest opens and joins the actual request on every throwing/assertion path.
    /// Its observation scope is task-local, so unrelated runtimes and their decodes are unaffected.
    func withHeldRequest(
        _ request: AssetTransferRequest,
        sequence: UInt64,
        observer: AssetLifecycleObserver,
        whileHeld: () async throws -> Void
    ) async throws -> AddonRuntime.RuntimeAssetRequestResult {
        let ingress = try #require(adapter.stageAssetIngress(
            AssetTransferFrameCodec.encode(request, profile: .v1),
            incarnation: connection.incarnation,
            sequence: sequence
        ))
        let task = Task {
            let result = await AssetLifecycleTesting.$observer.withValue(observer) {
                await runtime.receiveAssetRequest(ingress, connection: connection)
            }
            observer.gate.finished()
            return result
        }
        return try await withTaskCancellationHandler {
            do {
                let reached = await observer.gate.waitForArrival()
                try #require(reached, "Request returned without reaching the real checkpoint")
                try await whileHeld()
                observer.gate.release()
                return await task.value
            } catch {
                observer.gate.release()
                _ = await task.value
                throw error
            }
        } onCancel: {
            observer.gate.release()
        }
    }

    func consumeReply() async throws -> AssetTransferResponse? {
        guard case .assetResponse(let delivery)? = adapter.currentDelivery(incarnation: connection.incarnation)
        else { return nil }
        try #require(await runtime.receiveAssetReceipt(delivery.receipt, connection: connection))
        return try AssetTransferFrameCodec.decodeResponse(delivery.payload, profile: .v1)
    }

    func receiveAllChunks(_ png: Data, transferID: UUID, startingAt sequence: UInt64) async throws -> UInt64 {
        var next = sequence
        for offset in stride(from: 0, to: png.count, by: 65_536) {
            let chunk = try await exchange(
                AssetTransferRequest(
                    requestID: UUID(), operation: .chunk, transferID: transferID,
                    offset: offset, bytes: png.subdata(in: offset..<min(png.count, offset + 65_536))
                ), sequence: next
            )
            #expect(chunk.result == .acknowledged)
            next += 1
        }
        return next
    }

    func binding(_ index: Int = 0) async throws -> AssetTransferBinding {
        try await runtime.assetBindingForTesting(publicationID: ids[index], connection: connection)
    }

    func publishExpiring(_ index: Int = 0, at seconds: TimeInterval = 5) async throws {
        _ = try await publish([
            Publication(
                id: ids[index], revision: 1, kind: .widget, content: content(nil),
                timeline: nil, expiresAt: wall.addingTimeInterval(seconds), stalePolicy: .remove
            )
        ], sequence: 1)
    }

    func serviceBusyDeadline() async throws {
        do {
            _ = try await runtime.serviceDeadlines()
            Issue.record("The held global admission must refuse the final deadline scheduling admission")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
    }

    /// drainCleanup forwards the public deadline event. Its final scheduling admission may
    /// refuse quiescence/disable, after the real deferred cleanup has already been serviced.
    func drainCleanup() async throws {
        do { _ = try await runtime.serviceDeadlines() }
        catch let error as AddonFailure {
            #expect(error.code == .sessionRevoked || error.code == .resourceDenied)
        }
        try await runtime.flushDisposedAssetsForTesting()
    }

    /// prepareAcknowledgedAction leaves real uncertain work charged while freeing the shared
    /// delivery slot. Service/source deliveries have no independent receipt in this runtime.
    func prepareAcknowledgedAction(controlAsset: String? = nil) async throws -> ActionDispatcher.Delivery {
        let content = try PresentationSet(
            widget: ContentDocument(
                root: .action(ActionDescriptor(id: "pause", label: "Pause", payload: Data([7]))),
                privacy: .publicContent,
                accessibilityLabel: "Controls",
                assetIDs: controlAsset.map { [$0] } ?? []
            ),
            compactLeading: nil, compactTrailing: nil, minimal: nil, expanded: nil
        )
        _ = try await publish([
            Publication(
                id: ids[1], revision: 2, kind: .widget,
                content: content, timeline: nil,
                expiresAt: wall.addingTimeInterval(60), stalePolicy: .remove
            )
        ], sequence: 2)
        _ = try await runtime.submitAction(ActionRequest(
            schemaVersion: 1, requestID: UUID(), publicationID: ids[1], actionID: "pause",
            input: Data([7]), deadline: wall.addingTimeInterval(2), observedRevision: 2
        ))
        try #require(await runtime.pumpReady())
        let delivery = try #require(adapter.lastAction)
        try #require(await runtime.receiveAcknowledgment(delivery, connection: connection))
        return delivery
    }

    func using(_ replacement: RuntimeConnection, ids replacementIDs: [PublicationID]? = nil) -> Self {
        Self(
            root: root, runtime: runtime, governor: governor, access: access, adapter: adapter,
            connection: replacement, clock: clock, ids: replacementIDs ?? ids,
            owner: replacement.identity.addonID, wall: wall, companion: companion, companionID: companionID
        )
    }

    func reconnect() async throws -> Self {
        let launch = try await runtime.requestLaunch(owner: owner)
        let current = try await runtime.attach(
            launchID: launch,
            offer: ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: 2, contentSchemas: [1])
        )
        return using(current)
    }
}

#endif
