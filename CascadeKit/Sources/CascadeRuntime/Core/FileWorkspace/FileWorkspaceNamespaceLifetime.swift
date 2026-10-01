//
//  FileWorkspaceNamespaceLifetime.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// FileWorkspaceNamespaceLifetime owns one governor ledger and writer slot for a namespace.
/// Reopened store values must reuse this object while the process retains the same governor.
actor FileWorkspaceNamespaceLifetime {

    nonisolated let directory     : URL
    nonisolated let owner         : AddonID
    nonisolated let governorTarget: ResourceGovernor

    private let resources: any RuntimeResourceAccess

    private var token            : ObservedDiskToken?
    private var stateReservation : ResourceReservation?
    private var memoryReservation: ResourceReservation?
    private var chargedBytes      = 0
    private var retainedBytes     = 0
    private var active           : UUID?
    private var writer           : UUID?
    private var deliveryPins      = 0

    init(
        directory: URL,
        owner    : AddonID,
        resources: any RuntimeResourceAccess
    ) {
        self.directory = directory.standardizedFileURL
        self.owner     = owner
        self.resources = resources
        governorTarget = resources.resourceGovernorTarget
    }

    func begin(
        _ operation: UUID,
        directory  : URL,
        owner      : AddonID,
        governor   : ResourceGovernor,
        writer     : UUID,
        restoring  : Bool
    ) throws {
        guard directory.standardizedFileURL == self.directory,
              owner == self.owner,
              governor === governorTarget,
              active == nil,
              restoring ? self.writer == nil : self.writer == writer
        else {
            throw FileWorkspaceError.interrupted
        }

        active = operation
    }

    /// activate makes one successfully restored store the only current cached writer.
    func activate(
        writer   : UUID,
        operation: UUID
    ) throws {
        guard active == operation, deliveryPins == 0 else {
            throw FileWorkspaceError.interrupted
        }

        self.writer = writer
    }

    func addDeliveryPins(
        _ count  : Int,
        writer   : UUID,
        operation: UUID
    ) throws {
        guard active == operation,
              self.writer == writer,
              count > 0,
              deliveryPins <= Int.max - count
        else {
            throw FileWorkspaceError.interrupted
        }

        deliveryPins += count
    }

    func releaseDeliveryPin(
        writer   : UUID,
        operation: UUID
    ) throws {
        guard active == operation, self.writer == writer, deliveryPins > 0 else {
            throw FileWorkspaceError.interrupted
        }

        deliveryPins -= 1
    }

    /// close releases only in-memory reservations; the observed disk ledger remains authoritative.
    func close(
        writer   : UUID,
        operation: UUID
    ) async throws {
        guard active == operation, self.writer == writer, deliveryPins == 0 else {
            throw FileWorkspaceError.interrupted
        }

        if let stateReservation {
            try await resources.release(stateReservation.id, owner: owner)
            self.stateReservation = nil
        }
        if let memoryReservation {
            try await resources.release(memoryReservation.id, owner: owner)
            self.memoryReservation = nil
        }

        retainedBytes = 0
        self.writer   = nil
    }

    func finish(_ operation: UUID) {
        if active == operation { active = nil }
    }

    /// establish adopts existing bytes without treating preexisting debt as fresh admission.
    func establish(
        measuredBytes: Int,
        operation    : UUID
    ) async throws {
        try validate(operation)
        if token == nil {
            let admitted = try await resources.workspaceAdmitObservedDisk(
                bytes                : 0,
                owner                : owner,
                retainedMetadataBytes: 4_096
            )
            token = admitted
        }

        try validate(operation)
        try await reconcile(
            measuredBytes: measuredBytes,
            mayRefund    : true,
            operation    : operation
        )
    }

    /// grow prepays bytes that can coexist with every currently retained file.
    func grow(
        additionalBytes: Int,
        operation      : UUID
    ) async throws {
        try validate(operation)
        guard additionalBytes >= 0, let token else { throw FileWorkspaceError.ioFailure }

        let target = chargedBytes.addingReportingOverflow(additionalBytes)
        guard !target.overflow else { throw FileWorkspaceError.quotaExceeded }

        do {
            guard try await resources.workspaceGrowObservedDisk(
                token,
                owner    : owner,
                fromBytes: chargedBytes,
                toBytes  : target.partialValue
            ) else { throw FileWorkspaceError.ioFailure }

            chargedBytes = target.partialValue
        } catch let error as FileWorkspaceError {
            throw error
        } catch let failure as AddonFailure where failure.code == .resourceDenied {
            throw FileWorkspaceError.quotaExceeded
        } catch {
            throw FileWorkspaceError.ioFailure
        }
    }

    /// reconcile refunds only a complete safe inventory; incomplete scans retain prior charge.
    func reconcile(
        measuredBytes: Int,
        mayRefund    : Bool,
        operation    : UUID
    ) async throws {
        guard let token, measuredBytes >= 0 else { throw FileWorkspaceError.ioFailure }

        let retained = mayRefund ? measuredBytes : max(chargedBytes, measuredBytes)
        guard try await resources.workspaceReconcileObservedDisk(
            token,
            owner        : owner,
            fromBytes    : chargedBytes,
            measuredBytes: retained
        ) else { throw FileWorkspaceError.ioFailure }

        chargedBytes = retained
        try validate(operation)
    }

    /// accountRetained charges decoded manifests, bookmarks and delivery tables to common policy.
    func accountRetained(
        bytes    : Int,
        operation: UUID
    ) async throws {
        try validate(operation)
        guard bytes >= 0 else { throw FileWorkspaceError.quotaExceeded }

        if stateReservation == nil || memoryReservation == nil {
            let state: ResourceReservation
            do {
                state = try await resources.admit(.state(bytes: bytes), owner: owner)
            } catch {
                throw Self.accountingFailure(error)
            }

            do {
                let memory = try await resources.admit(
                    .temporaryMemory(bytes: bytes),
                    owner: owner
                )
                stateReservation  = state
                memoryReservation = memory
                retainedBytes     = bytes
                return
            } catch {
                try? await resources.release(state.id, owner: owner)
                throw Self.accountingFailure(error)
            }
        }

        guard let stateReservation, let memoryReservation, bytes != retainedBytes else { return }

        do {
            guard try await resources.resizeStateReservation(
                stateReservation.id,
                owner    : owner,
                fromBytes: retainedBytes,
                toBytes  : bytes
            ) else { throw FileWorkspaceError.ioFailure }

            do {
                guard try await resources.workspaceResizeMemoryReservation(
                    memoryReservation.id,
                    owner    : owner,
                    fromBytes: retainedBytes,
                    toBytes  : bytes
                ) else { throw FileWorkspaceError.ioFailure }
            } catch {
                _ = try? await resources.resizeStateReservation(
                    stateReservation.id,
                    owner    : owner,
                    fromBytes: bytes,
                    toBytes  : retainedBytes
                )
                throw error
            }

            retainedBytes = bytes
        } catch {
            throw Self.accountingFailure(error)
        }
    }

    private func validate(_ operation: UUID) throws {
        try Task.checkCancellation()
        guard active == operation else { throw FileWorkspaceError.interrupted }
    }

    private static func accountingFailure(_ error: any Error) -> FileWorkspaceError {
        if let error = error as? FileWorkspaceError { return error }
        if let failure = error as? AddonFailure, failure.code == .resourceDenied {
            return .quotaExceeded
        }

        return .ioFailure
    }
}
