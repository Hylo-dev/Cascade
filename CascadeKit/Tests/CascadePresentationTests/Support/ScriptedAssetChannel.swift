//
//  ScriptedAssetChannel.swift
//  CascadeKit
//

@testable import CascadeAddonSDK
import CascadeContracts
import Foundation
import Testing

/// ScriptedAssetChannel is a bounded canned channel for SDK-only tests. It records the exact
/// bounded exchange history and can physically hold one exchange or its close/drain so
/// cancellation and close coordination are deterministic rather than scheduling-dependent.
actor ScriptedAssetChannel: AddonAssetMessageChannel {

    enum Mode: Sendable {

        case normal
        case transportErrorOnChunk
        case malformedReply
        case hostFailure(operation: AssetTransferOperation, code: AddonFailure.Code)
        case responseRequestIDMismatch
        case chunkTransferIDMismatch
        case importOwnerMismatch
        case importPublicationMismatch
        case shareOwnerMismatch
        case sharePublicationMismatch
    }

    nonisolated let generation = ConnectionGeneration()
    nonisolated let profile   : AssetTransferFrameProfile?

    private let mode               : Mode
    private let gateExchange       : Bool
    private let holdAt             : Int?
    private let drainObservation   : SharedDrainObservation?
    private let holdSuccessAt      : Int?
    private let successReturned     = StartGate()
    private let holdClose          : Bool
    private let abortFailureCode   : AddonFailure.Code?
    private var blocked             = false
    private var exchangeIndex       = 0
    private var transferID         : UUID?
    private var observedPublication: PublicationID?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var holdArrived         = false
    private var heldContinuation   : CheckedContinuation<Void, Never>?
    private var heldRelease        : CheckedContinuation<Void, Never>?
    private var closeEntered        = false
    private var closeArrival       : CheckedContinuation<Void, Never>?
    private var closeRelease       : CheckedContinuation<Void, Never>?

    private(set) var observedSequences : [UInt64] = []
    private(set) var observedOperations: [AssetTransferOperation] = []
    private(set) var chunkSizes        : [Int] = []
    private(set) var closeCount         = 0
    private(set) var didCloseComplete   = false
    private(set) var events            : [String] = []

    init(
        profile         : AssetTransferFrameProfile? = .v1,
        mode            : Mode = .normal,
        gateExchange    : Bool = false,
        holdAt          : Int? = nil,
        holdClose       : Bool = false,
        holdSuccessAt   : Int? = nil,
        drainObservation: SharedDrainObservation? = nil,
        abortFailureCode: AddonFailure.Code? = nil
    ) {
        self.profile          = profile
        self.mode             = mode
        self.gateExchange     = gateExchange
        self.drainObservation = drainObservation
        self.holdSuccessAt    = holdSuccessAt
        self.holdAt           = holdAt
        self.holdClose        = holdClose
        self.abortFailureCode = abortFailureCode
    }

    // MARK: Test-only deterministic points

    func waitUntilBlocked() async {
        if blocked { return }

        await withCheckedContinuation { continuation in
            arrivalContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitUntilHeld() async {
        if holdArrived { return }

        await withCheckedContinuation { continuation in
            heldContinuation = continuation
        }
    }

    func releaseHeld() {
        heldRelease?.resume()
        heldRelease = nil
    }

    func waitUntilCloseEntered() async {
        if closeEntered { return }

        await withCheckedContinuation { continuation in
            closeArrival = continuation
        }
    }

    func waitUntilSuccessReturned() async {
        await successReturned.wait()
    }

    func releaseClose() {
        closeRelease?.resume()
        closeRelease = nil
    }

    func recordCallerReturn() {
        events.append("caller-returned")
    }

    // MARK: AddonAssetMessageChannel

    func exchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> Data {
        let request = try AssetTransferFrameCodec.decodeRequest(
            frame,
            profile: .v1
        )

        exchangeIndex += 1
        observedSequences.append(sequence)
        observedOperations.append(request.operation)
        if let bytes = request.bytes, request.operation == .chunk {
            chunkSizes.append(bytes.count)
        }

        if gateExchange, !blocked {
            blocked = true
            arrivalContinuation?.resume()
            arrivalContinuation = nil
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        if let holdAt, holdAt == exchangeIndex {
            holdArrived = true
            heldContinuation?.resume()
            heldContinuation = nil
            await withCheckedContinuation { continuation in
                heldRelease = continuation
            }
        }

        if request.operation == .abort, let abortFailureCode {
            return try AssetTransferFrameCodec.encode(
                try AssetTransferResponse(
                    requestID    : request.requestID,
                    operation    : .abort,
                    result       : .failure,
                    failureCode  : abortFailureCode,
                    failureReason: "Scripted abort refusal."
                ),
                profile: .v1
            )
        }

        switch mode {
            case .normal:
                let encoded = try AssetTransferFrameCodec.encode(
                    try response(for: request),
                    profile: .v1
                )
                if holdSuccessAt == exchangeIndex {
                    holdArrived = true
                    heldContinuation?.resume()
                    heldContinuation = nil
                    await withCheckedContinuation { heldRelease = $0 }
                    events.append("success-returned")
                    await successReturned.open()
                }

                return encoded

            case .transportErrorOnChunk:
                if request.operation == .chunk {
                    throw AddonFailure(
                        code  : .dependencyUnavailable,
                        reason: "Scripted transport failure."
                    )
                }

                return try AssetTransferFrameCodec.encode(
                    try response(for: request),
                    profile: .v1
                )

            case .malformedReply:
                return Data([0xFF, 0x00, 0x01])

            case .responseRequestIDMismatch:
                return try AssetTransferFrameCodec.encode(
                    try AssetTransferResponse(
                        requestID    : UUID(),
                        operation    : request.operation,
                        result       : .failure,
                        failureCode  : .invalidPayload,
                        failureReason: "Scripted correlation mismatch."
                    ),
                    profile: .v1
                )

            case .chunkTransferIDMismatch, .importOwnerMismatch, .importPublicationMismatch,
                 .shareOwnerMismatch, .sharePublicationMismatch:
                return try AssetTransferFrameCodec.encode(
                    try response(for: request),
                    profile: .v1
                )

            case .hostFailure(let operation, let code):
                if request.operation == operation {
                    return try AssetTransferFrameCodec.encode(
                        try AssetTransferResponse(
                            requestID    : request.requestID,
                            operation    : operation,
                            result       : .failure,
                            failureCode  : code,
                            failureReason: "Scripted host refusal."
                        ),
                        profile: .v1
                    )
                }

                return try AssetTransferFrameCodec.encode(
                    try response(for: request),
                    profile: .v1
                )
        }
    }

    func close() async {
        closeCount += 1
        events.append("close-entered")

        if holdClose {
            closeEntered = true
            closeArrival?.resume()
            closeArrival = nil
            await withCheckedContinuation { continuation in
                closeRelease = continuation
            }
            closeRelease = nil
        }

        // The physical channel cannot finish disposal before the held exchange exits.
        if holdSuccessAt != nil { await successReturned.wait() }

        events.append("close-completed")
        didCloseComplete = true
        drainObservation?.physicalCloseCompleted()
    }

    private func response(for request: AssetTransferRequest) throws -> AssetTransferResponse {
        switch request.operation {
            case .begin:
                let id = UUID()
                transferID          = id
                observedPublication = request.publicationID

                return try AssetTransferResponse(
                    requestID : request.requestID,
                    operation : .begin,
                    result    : .begun,
                    transferID: id
                )

            case .chunk:
                let id             = try #require(transferID)
                let offset         = try #require(request.offset)
                let count          = try #require(request.bytes).count
                let acknowledgedID: UUID
                if case .chunkTransferIDMismatch = mode { acknowledgedID = UUID() } else { acknowledgedID = id }

                return try AssetTransferResponse(
                    requestID : request.requestID,
                    operation : .chunk,
                    result    : .acknowledged,
                    transferID: acknowledgedID,
                    nextOffset: offset + count
                )

            case .finish:
                let id                = try #require(transferID)
                let publication       = try #require(observedPublication)
                let owner            : AddonID
                let handlePublication: PublicationID
                switch mode {
                    case .importOwnerMismatch:
                        owner             = try #require(AddonID(rawValue: "com.example.asset-other"))
                        handlePublication = PublicationID(
                            addonID   : owner,
                            instanceID: UUID(),
                            sessionID : UUID()
                        )

                    case .importPublicationMismatch:
                        owner             = publication.addonID
                        handlePublication = PublicationID(
                            addonID   : owner,
                            instanceID: UUID(),
                            sessionID : UUID()
                        )

                    default:
                        owner             = publication.addonID
                        handlePublication = publication
                }

                return try AssetTransferResponse(
                    requestID  : request.requestID,
                    operation  : .finish,
                    result     : .imported,
                    transferID : id,
                    assetHandle: try AssetHandle(
                        assetID       : "asset-" + UUID().uuidString,
                        owner         : owner,
                        publicationID : handlePublication,
                        rasterRevision: 1,
                        width         : 1,
                        height        : 1,
                        byteCount     : 4
                    )
                )

            case .abort:
                return try AssetTransferResponse(
                    requestID : request.requestID,
                    operation : .abort,
                    result    : .acknowledged,
                    transferID: try #require(transferID) as UUID
                )

            case .share:
                let target            = try #require(request.publicationID)
                let source            = try #require(request.sourceHandle)
                let owner            : AddonID
                let handlePublication: PublicationID
                switch mode {
                    case .shareOwnerMismatch:
                        owner             = try #require(AddonID(rawValue: "com.example.asset-other"))
                        handlePublication = PublicationID(
                            addonID   : owner,
                            instanceID: UUID(),
                            sessionID : UUID()
                        )

                    case .sharePublicationMismatch:
                        owner             = source.owner
                        handlePublication = PublicationID(
                            addonID   : owner,
                            instanceID: UUID(),
                            sessionID : UUID()
                        )

                    default:
                        owner             = source.owner
                        handlePublication = target
                }

                return try AssetTransferResponse(
                    requestID  : request.requestID,
                    operation  : .share,
                    result     : .shared,
                    assetHandle: try AssetHandle(
                        assetID       : "asset-" + UUID().uuidString,
                        owner         : owner,
                        publicationID : handlePublication,
                        rasterRevision: 1,
                        width         : 1,
                        height        : 1,
                        byteCount     : 4
                    )
                )

            case .release:
                return try AssetTransferResponse(
                    requestID: request.requestID,
                    operation: .release,
                    result   : .acknowledged
                )
        }
    }
}
