//
//  BoundedAssetTransferAssemblerTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1))) struct BoundedAssetTransferAssemblerTests {
    @Test func foreignAuthorityPreservesReceivingTransfer() async throws {
        let fixture = try TransferFixture()
        let token = try await fixture.assembler.begin(
            totalBytes: 65_537,
            binding   : fixture.binding
        )
        let binding = fixture.binding
        let foreignPublication = PublicationID(
            addonID   : binding.publicationID.addonID,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let variants = [
            AssetTransferBinding(
                incarnation    : RuntimeIncarnation(),
                connectionToken: binding.connectionToken,
                publicationID  : binding.publicationID,
                assignmentToken: binding.assignmentToken
            ),
            AssetTransferBinding(
                incarnation    : binding.incarnation,
                connectionToken: UUID(),
                publicationID  : binding.publicationID,
                assignmentToken: binding.assignmentToken
            ),
            AssetTransferBinding(
                incarnation    : binding.incarnation,
                connectionToken: binding.connectionToken,
                publicationID  : foreignPublication,
                assignmentToken: binding.assignmentToken
            ),
            AssetTransferBinding(
                incarnation    : binding.incarnation,
                connectionToken: binding.connectionToken,
                publicationID  : binding.publicationID,
                assignmentToken: UUID()
            )
        ]
        for foreign in variants {
            await #expect(throws: AddonFailure.self) {
                try await fixture.assembler.append(
                    transferID: token,
                    binding   : foreign,
                    offset    : 0,
                    bytes     : Data(count: 65_536)
                )
            }
            await #expect(throws: AddonFailure.self) { try await fixture.assembler.abort(
                transferID: token,
                binding   : foreign
            ) }
            await #expect(throws: AddonFailure.self) { try await fixture.assembler.finish(
                transferID: token,
                binding   : foreign
            ) }
        }
        await #expect(throws: AddonFailure.self) { try await fixture.assembler.abort(
            transferID: UUID(),
            binding   : binding
        ) }
        await #expect(throws: AddonFailure.self) { try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : binding
        ) }
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 135_170)
        #expect(try await fixture.assembler.append(
            transferID: token,
            binding   : binding,
            offset    : 0,
            bytes     : Data(count: 65_536)
        ) == 65_536)
        #expect(try await fixture.assembler.append(
            transferID: token,
            binding   : binding,
            offset    : 65_536,
            bytes     : Data([1])
        ) == 65_537)
        try await fixture.assembler.abort(
            transferID: token,
            binding   : binding
        )
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        try await fixture.assembler.close()
    }

    @Test func malformedExactProgressIsTerminalAndStaleCannotAffectReplacement() async throws {
        let fixture = try TransferFixture()
        for (offset, count) in [(0, 0), (0, 1), (0, 65_537), (1, 65_536), (Int.max, 65_536), (-1, 65_536)] {
            let token = try await fixture.assembler.begin(
                totalBytes: 65_537,
                binding   : fixture.binding
            )
            await #expect(throws: AddonFailure.self) {
                try await fixture.assembler.append(
                    transferID: token,
                    binding   : fixture.binding,
                    offset    : offset,
                    bytes     : Data(count: count)
                )
            }
            #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        }
        let incomplete = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        await #expect(throws: AddonFailure.self) { try await fixture.assembler.finish(
            transferID: incomplete,
            binding   : fixture.binding
        ) }
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        for offset in [0, 65_535, 65_537] {
            let token = try await fixture.assembler.begin(
                totalBytes: 65_537,
                binding   : fixture.binding
            )
            _ = try await fixture.assembler.append(
                transferID: token,
                binding   : fixture.binding,
                offset    : 0,
                bytes     : Data(count: 65_536)
            )
            await #expect(throws: AddonFailure.self) {
                try await fixture.assembler.append(
                    transferID: token,
                    binding   : fixture.binding,
                    offset    : offset,
                    bytes     : Data([1])
                )
            }
            #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        }
        let replacement = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        await #expect(throws: AddonFailure.self) { try await fixture.assembler.finish(
            transferID: incomplete,
            binding   : fixture.binding
        ) }
        _ = try await fixture.assembler.append(
            transferID: replacement,
            binding   : fixture.binding,
            offset    : 0,
            bytes     : Data([1])
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.assembler.append(
                transferID: replacement,
                binding   : fixture.binding,
                offset    : 1,
                bytes     : Data([1])
            )
        }
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        try await fixture.assembler.close()
    }

    @Test func deadlineIsNonrenewableAndInvalidSamplesRevoke() async throws {
        for seconds in [29, 30, 31] {
            let fixture = try TransferFixture()
            let token = try await fixture.assembler.begin(
                totalBytes: 65_537,
                binding   : fixture.binding
            )
            #expect(fixture.assembler.nextDeadline == .seconds(30))
            fixture.clock.set(.seconds(20))
            _ = try await fixture.assembler.append(
                transferID: token,
                binding   : fixture.binding,
                offset    : 0,
                bytes     : Data(count: 65_536)
            )
            #expect(fixture.assembler.nextDeadline == .seconds(30))
            fixture.clock.set(.seconds(seconds))
            if seconds == 29 {
                _ = try await fixture.assembler.append(
                    transferID: token,
                    binding   : fixture.binding,
                    offset    : 65_536,
                    bytes     : Data([1])
                )
            } else {
                await #expect(throws: AddonFailure.self) {
                    try await fixture.assembler.append(
                        transferID: token,
                        binding   : fixture.binding,
                        offset    : 65_536,
                        bytes     : Data([1])
                    )
                }
                #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
            }
            try await fixture.assembler.close()
        }
        let fixture = try TransferFixture()
        _ = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        fixture.clock.set(.seconds(30))
        try await fixture.assembler.expire()
        try await fixture.assembler.expire()
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        for (monotonic, wall) in [(Duration.seconds(-1), 0.0), (.seconds(Int64.max), 0), (.seconds(40), Double.infinity)] {
            fixture.clock.set(.seconds(30))
            let token = try await fixture.assembler.begin(
                totalBytes: 1,
                binding   : fixture.binding
            )
            fixture.clock.set(
                monotonic,
                wall: wall
            )
            await #expect(throws: AddonFailure.self) {
                try await fixture.assembler.append(
                    transferID: token,
                    binding   : fixture.binding,
                    offset    : 0,
                    bytes     : Data([1])
                )
            }
            #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        }
        fixture.clock.set(.seconds(31))
        let backward = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        fixture.clock.set(.seconds(30))
        await #expect(throws: AddonFailure.self) {
            try await fixture.assembler.append(
                transferID: backward,
                binding   : fixture.binding,
                offset    : 0,
                bytes     : Data([1])
            )
        }
        try await fixture.assembler.close()
        try await fixture.assembler.close()
        #expect(fixture.assembler.nextDeadline == nil)
    }

    @Test func decodeCloseAbortExpiryAndCancellationKeepActualWorkerCharged() async throws {
        for mode in 0..<4 {
            let governor = ResourceGovernor()
            let gate = TransferRasterGate(governor: governor)
            let coordinator = try AssetDisposalCoordinator(
                governor: governor,
                access  : gate
            )
            let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
            let fixture = try TransferFixture(
                governor: governor,
                decoder : decoder
            )
            let encoded = try transferImageFixture()
            let token = try await fixture.assembler.begin(
                totalBytes: encoded.count,
                binding   : fixture.binding
            )
            _ = try await fixture.assembler.append(
                transferID: token,
                binding   : fixture.binding,
                offset    : 0,
                bytes     : encoded
            )
            let worker = Task { try await fixture.assembler.finish(
                transferID: token,
                binding   : fixture.binding
            ) }
            await gate.reached()
            let quote = 2 * encoded.count + 4_096
            #expect(await governor.usage(.admittedMemoryBytes) == quote + 10_162_688 + 4_104)
            switch mode {
            case 0: try await fixture.assembler.close()
            case 1: try await fixture.assembler.abort(
                transferID: token,
                binding   : fixture.binding
            )
            case 2:
                fixture.clock.set(.seconds(30))
                try await fixture.assembler.expire()
            default: worker.cancel()
            }
            await governor.releaseAll(owner: fixture.binding.publicationID.addonID)
            #expect(await governor.usage(.admittedMemoryBytes) == quote + 10_162_688 + 4_104)
            await #expect(throws: AddonFailure.self) { try await fixture.assembler.begin(
                totalBytes: 1,
                binding   : fixture.binding
            ) }
            await gate.open()
            if mode == 3 {
                await #expect(throws: CancellationError.self) { try await worker.value }
            } else {
                await #expect(throws: AddonFailure.self) { try await worker.value }
            }
            try await coordinator.flushDisposed()
            #expect(await governor.usage(.admittedMemoryBytes) == 0)
            #expect(await governor.usage(.retainedStateBytes) == 0)
            if mode != 0 {
                let replacement = try await fixture.assembler.begin(
                    totalBytes: 1,
                    binding   : fixture.binding
                )
                try await fixture.assembler.abort(
                    transferID: replacement,
                    binding   : fixture.binding
                )
            }
            try await fixture.assembler.close()
            decoder.close()
        }
    }

    @Test func admissionAndDisposalRemainExclusiveAcrossGovernorHops() async throws {
        let fixture = try TransferFixture()
        let gate = TransferGovernorGate()
        let blocker = Task.detached { await fixture.governor.holdTransferTest(gate) }
        await gate.reached()
        let pending = Task { try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        ) }
        await fixture.clock.reached(1)
        await #expect(throws: AddonFailure.self) {
            try await fixture.assembler.begin(
                totalBytes: 1,
                binding   : fixture.binding
            )
        }
        try await fixture.assembler.close()
        gate.open()
        await blocker.value
        await #expect(throws: AddonFailure.self) { try await pending.value }
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)

        let disposing = try TransferFixture()
        let token = try await disposing.assembler.begin(
            totalBytes: 1,
            binding   : disposing.binding
        )
        let refundGate = TransferGovernorGate()
        let refundBlocker = Task.detached { await disposing.governor.holdTransferTest(refundGate) }
        await refundGate.reached()
        let aborting = Task { try await disposing.assembler.abort(
            transferID: token,
            binding   : disposing.binding
        ) }
        await disposing.clock.reached(3)
        await #expect(throws: AddonFailure.self) {
            try await disposing.assembler.begin(
                totalBytes: 1,
                binding   : disposing.binding
            )
        }
        try await disposing.assembler.close()
        refundGate.open()
        await refundBlocker.value
        try await aborting.value
        #expect(await disposing.governor.usage(.admittedMemoryBytes) == 0)
        #expect(await disposing.governor.usage(.retainedStateBytes) == 0)
    }

    @Test func cancellationAndDecoderBusyErrorRefundOnlyTheirTransfer() async throws {
        let fixture = try TransferFixture()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.assembler.begin(
                totalBytes: 1,
                binding   : fixture.binding
            )
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let token = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        let cancelledAppend = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.assembler.append(
                transferID: token,
                binding   : fixture.binding,
                offset    : 0,
                bytes     : Data([1])
            )
        }
        await #expect(throws: CancellationError.self) { try await cancelledAppend.value }
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        try await fixture.assembler.close()

        let governor = ResourceGovernor()
        let gate = TransferRasterGate(governor: governor)
        let coordinator = try AssetDisposalCoordinator(
            governor: governor,
            access  : gate
        )
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let first = try TransferFixture(
            governor: governor,
            decoder : decoder
        )
        let second = try TransferFixture(
            governor: governor,
            decoder : decoder
        )
        let encoded = try transferImageFixture()
        let firstToken = try await first.assembler.begin(
            totalBytes: encoded.count,
            binding   : first.binding
        )
        _ = try await first.assembler.append(
            transferID: firstToken,
            binding   : first.binding,
            offset    : 0,
            bytes     : encoded
        )
        let decoding = Task { try await first.assembler.finish(
            transferID: firstToken,
            binding   : first.binding
        ) }
        await gate.reached()
        let secondToken = try await second.assembler.begin(
            totalBytes: encoded.count,
            binding   : second.binding
        )
        await #expect(throws: AddonFailure.self) {
            try await second.assembler.append(
                transferID: firstToken,
                binding   : first.binding,
                offset    : 0,
                bytes     : encoded
            )
        }
        _ = try await second.assembler.append(
            transferID: secondToken,
            binding   : second.binding,
            offset    : 0,
            bytes     : encoded
        )
        await #expect(throws: AddonFailure.self) {
            try await second.assembler.finish(
                transferID: secondToken,
                binding   : second.binding
            )
        }
        #expect(await governor.usage(.admittedMemoryBytes) == 2 * encoded.count + 4_096 + 10_162_688 + 4_104)
        try await first.assembler.close()
        await gate.open()
        await #expect(throws: AddonFailure.self) { try await decoding.value }
        try await second.assembler.close()
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
    }

    @Test func exactMebibyteIntegrityUsesSixteenCodecDecodedChunks() async throws {
        let governor = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        let real = BoundedAssetImageDecoder(coordinator: coordinator)
        let inspector = TransferIntegrityDecoder(
            real   : real,
            fixture: try transferImageFixture()
        )
        let fixture = try TransferFixture(
            governor: governor,
            decoder : inspector
        )
        let token = try await fixture.assembler.begin(
            totalBytes: 1_048_576,
            binding   : fixture.binding
        )
        for index in 0..<16 {
            let request = try AssetTransferRequest(
                requestID : UUID(),
                operation : .chunk,
                transferID: token,
                offset    : index * 65_536,
                bytes     : Data(
                    repeating: UInt8(index),
                    count    : 65_536
                )
            )
            let decoded = try AssetTransferFrameCodec.decodeRequest(
                AssetTransferFrameCodec.encode(
                    request,
                    profile: .v1
                ),
                profile: .v1
            )
            _ = try await fixture.assembler.append(
                transferID: token,
                binding   : fixture.binding,
                offset    : try #require(decoded.offset),
                bytes     : try #require(decoded.bytes)
            )
        }
        var raster: AssetRasterBacking? = try await fixture.assembler.finish(
            transferID: token,
            binding   : fixture.binding
        )
        #expect(raster?.image.width == 2)
        #expect(inspector.wasExact)
        raster = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        try await fixture.assembler.close()
    }

    @Test func realMultichunkPNGRetainsPixelsAndRejectsTruncation() async throws {
        let width = 192
        var seed: UInt32 = 42
        var pixels = Data(count: width * width * 4)
        for index in pixels.indices {
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            pixels[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: seed)
        }
        let encoded = try transferImageFixture(
            width     : width,
            height    : width,
            pixelBytes: pixels
        )
        #expect(encoded.count > 65_536 && encoded.count <= 1_048_576)
        let fixture = try TransferFixture()
        let token = try await fixture.assembler.begin(
            totalBytes: encoded.count,
            binding   : fixture.binding
        )
        for offset in stride(
            from: 0,
            to  : encoded.count,
            by  : 65_536
        ) {
            let request = try AssetTransferRequest(
                requestID : UUID(),
                operation : .chunk,
                transferID: token,
                offset    : offset,
                bytes     : Data(encoded[offset..<min(
                    offset + 65_536,
                    encoded.count
                )])
            )
            let decoded = try AssetTransferFrameCodec.decodeRequest(
                AssetTransferFrameCodec.encode(
                    request,
                    profile: .v1
                ),
                profile: .v1
            )
            _ = try await fixture.assembler.append(
                transferID: token,
                binding   : fixture.binding,
                offset    : offset,
                bytes     : try #require(decoded.bytes)
            )
        }
        var raster: AssetRasterBacking? = try await fixture.assembler.finish(
            transferID: token,
            binding   : fixture.binding
        )
        var image: CGImage? = raster?.image
        #expect(image?.dataProvider?.data as Data? == pixels)
        raster = nil
        await fixture.governor.releaseAll(owner: fixture.binding.publicationID.addonID)
        #expect(await fixture.governor.usage(.assetBytes) == pixels.count)
        #expect(image?.width == width)
        image = nil
        try await fixture.coordinator.flushDisposed()
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        for input in [Data(encoded.dropLast()), Data([0, 1, 2])] {
            let next = try await fixture.assembler.begin(
                totalBytes: input.count,
                binding   : fixture.binding
            )
            for offset in stride(
                from: 0,
                to  : input.count,
                by  : 65_536
            ) {
                _ = try await fixture.assembler.append(
                    transferID: next,
                    binding   : fixture.binding,
                    offset    : offset,
                    bytes     : Data(input[offset..<min(
                        offset + 65_536,
                        input.count
                    )])
                )
            }
            await #expect(throws: AddonFailure.self) { try await fixture.assembler.finish(
                transferID: next,
                binding   : fixture.binding
            ) }
            try await fixture.coordinator.flushDisposed()
            #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        }
        try await fixture.assembler.close()
    }
}

extension BoundedAssetTransferAssemblerTests {
    /// failedAdmissionRefundRetainsExactTokenUntilClose forces the real refund seam to throw
    /// during a begin rollback and proves the assembler still owns the only reservation handle.
    @Test func failedAdmissionRefundRetainsExactTokenUntilClose() async throws {
        let fixture = try TransferFixture()
        await fixture.governor.armAssetTransferRefundFailureForTesting()
        let gate = TransferGovernorGate()
        let blocker = Task.detached { await fixture.governor.holdTransferTest(gate) }
        await gate.reached()
        let pending = Task { try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        ) }
        await fixture.clock.reached(1)
        // Stop arrives while admission is suspended inside the governor actor.
        try await fixture.assembler.close()
        gate.open()
        await blocker.value
        await #expect(throws: AddonFailure.self) { try await pending.value }
        // The refund threw, but the exact token stayed charged and retryable.
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 2 + 4_096)
        #expect(await fixture.governor.usage(.retainedStateBytes) == 1_024)
        #expect(fixture.assembler.nextDeadline != nil)
        // A later close retries the same token and releases it exactly once.
        try await fixture.assembler.close()
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        #expect(await fixture.governor.usage(.retainedStateBytes) == 0)
        #expect(fixture.assembler.nextDeadline == nil)
    }

    /// terminalReceivingFailureOwnsRefund checks exclusivity across a held real governor hop.
    /// It verifies the final invariant; it does not force the former unlock/relock race window.
    @Test func terminalReceivingFailureOwnsRefund() async throws {
        for incompleteFinish in [false, true] {
            let governor = ResourceGovernor()
            let coordinator = AssetDisposalCoordinator(governor: governor)
            let decoder = TransferCountingDecoder(real: BoundedAssetImageDecoder(coordinator: coordinator))
            let fixture = try TransferFixture(
                governor: governor,
                decoder : decoder
            )
            let encoded = try transferImageFixture()
            let token = try await fixture.assembler.begin(
                totalBytes: encoded.count,
                binding   : fixture.binding
            )
            if !incompleteFinish {
                _ = try await fixture.assembler.append(
                    transferID: token,
                    binding   : fixture.binding,
                    offset    : 0,
                    bytes     : encoded
                )
            }
            let gate = TransferGovernorGate()
            let blocker = Task.detached { await governor.holdTransferTest(gate) }
            await gate.reached()
            let rejected = Task {
                if incompleteFinish {
                    _ = try await fixture.assembler.finish(
                        transferID: token,
                        binding   : fixture.binding
                    )
                } else {
                    _ = try await fixture.assembler.append(
                        transferID: token,
                        binding   : fixture.binding,
                        offset    : encoded.count,
                        bytes     : Data([1])
                    )
                }
            }
            // now() signals while holding the receiving lock. Once the competing call
            // acquires that lock, terminal failure must already own the disposal state.
            await fixture.clock.reached(incompleteFinish ? 3 : 4)
            await #expect(throws: AddonFailure.self) {
                try await fixture.assembler.finish(
                    transferID: token,
                    binding   : fixture.binding
                )
            }
            await #expect(throws: AddonFailure.self) {
                try await fixture.assembler.begin(
                    totalBytes: 1,
                    binding   : fixture.binding
                )
            }
            #expect(decoder.calls == 0)
            gate.open()
            await blocker.value
            await #expect(throws: AddonFailure.self) { try await rejected.value }
            #expect(await governor.usage(.admittedMemoryBytes) == 0)
            #expect(await governor.usage(.retainedStateBytes) == 0)
            let replacement = try await fixture.assembler.begin(
                totalBytes: 1,
                binding   : fixture.binding
            )
            try await fixture.assembler.abort(
                transferID: replacement,
                binding   : fixture.binding
            )
            try await fixture.assembler.close()
            decoder.close()
        }
    }
    @Test func synchronousInvalidateRevokesSuspendedFinishWithoutPrematureRefund() async throws {
        let governor = ResourceGovernor()
        let gate = TransferRasterGate(governor: governor)
        let coordinator = try AssetDisposalCoordinator(
            governor: governor,
            access  : gate
        )
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let fixture = try TransferFixture(
            governor: governor,
            decoder : decoder
        )
        let encoded = try transferImageFixture()
        let token = try await fixture.assembler.begin(
            totalBytes: encoded.count,
            binding   : fixture.binding
        )
        _ = try await fixture.assembler.append(
            transferID: token,
            binding   : fixture.binding,
            offset    : 0,
            bytes     : encoded
        )
        let worker = Task { try await fixture.assembler.finish(
            transferID: token,
            binding   : fixture.binding
        ) }
        await gate.reached()
        let charged = await governor.usage(.admittedMemoryBytes)
        // A synchronous stop revokes authority without refunding a live native decode.
        fixture.assembler.invalidate()
        #expect(await governor.usage(.admittedMemoryBytes) == charged)
        #expect(fixture.assembler.nextDeadline == nil)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.assembler.begin(
                totalBytes: 1,
                binding   : fixture.binding
            )
        }
        await gate.open()
        await #expect(throws: AddonFailure.self) { try await worker.value }
        // The suspended finish refunds its own buffer once the native work has ended.
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        try await fixture.assembler.close()
        decoder.close()
    }

    /// exactRevocationIsNonterminalAndReusable proves one exact binding can be revoked without
    /// closing the live process assembler: a foreign binding is ignored, the sole token stays
    /// charged until disposal, new work is refused while the refund is outstanding, and the same
    /// assembler admits a later transfer once the refund completes.
    @Test func exactRevocationIsNonterminalAndReusable() async throws {
        let fixture = try TransferFixture()
        let encoded = try transferImageFixture()
        let token = try await fixture.assembler.begin(
            totalBytes: encoded.count,
            binding   : fixture.binding
        )
        _ = try await fixture.assembler.append(
            transferID: token,
            binding   : fixture.binding,
            offset    : 0,
            bytes     : encoded
        )
        let charged = await fixture.governor.usage(.admittedMemoryBytes)
        // A replacement assignment token must not revoke the exact live transfer.
        let foreign = AssetTransferBinding(
            incarnation    : fixture.binding.incarnation,
            connectionToken: fixture.binding.connectionToken,
            publicationID  : fixture.binding.publicationID,
            assignmentToken: UUID()
        )
        fixture.assembler.revokeTransfer(binding: foreign)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == charged)
        #expect(fixture.assembler.nextDeadline != nil)
        // The exact revocation withdraws return authority at once but keeps the sole token until
        // its refund is drained; a new transfer is refused while that refund is outstanding.
        fixture.assembler.revokeTransfer(binding: fixture.binding)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == charged)
        #expect(fixture.assembler.nextDeadline != nil)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.assembler.begin(
                totalBytes: 1,
                binding   : fixture.binding
            )
        }
        try await fixture.assembler.drainPendingCleanup()
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        #expect(fixture.assembler.nextDeadline == nil)
        // The same live assembler now admits another authorized transfer.
        let replacement = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        try await fixture.assembler.abort(
            transferID: replacement,
            binding   : fixture.binding
        )
        try await fixture.assembler.close()
    }

    /// staleBindingCannotRevokeReplacementRecord exercises a real second admission after
    /// disposal, then delivers the old binding and transfer ID against the new exact owner.
    @Test func staleBindingCannotRevokeReplacementRecord() async throws {
        let fixture = try TransferFixture()
        do {
            let encoded = try transferImageFixture()
            let oldID = try await fixture.assembler.begin(totalBytes: encoded.count, binding: fixture.binding)
            fixture.assembler.revokeTransfer(binding: fixture.binding)
            try await fixture.assembler.drainPendingCleanup()
            let replacement = AssetTransferBinding(
                incarnation: fixture.binding.incarnation,
                connectionToken: fixture.binding.connectionToken,
                publicationID: fixture.binding.publicationID,
                assignmentToken: UUID()
            )
            let currentID = try await fixture.assembler.begin(totalBytes: encoded.count, binding: replacement)
            let charged = await fixture.governor.usage(.admittedMemoryBytes)
            fixture.assembler.revokeTransfer(binding: fixture.binding)
            await #expect(throws: AddonFailure.self) {
                try await fixture.assembler.abort(transferID: oldID, binding: fixture.binding)
            }
            #expect(await fixture.governor.usage(.admittedMemoryBytes) == charged)
            _ = try await fixture.assembler.append(
                transferID: currentID, binding: replacement, offset: 0, bytes: encoded
            )
            var raster: AssetRasterBacking? = try await fixture.assembler.finish(transferID: currentID, binding: replacement)
            #expect(raster?.image.width == 2)
            raster = nil
            try await fixture.coordinator.flushDisposed()
            #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        } catch {
            try await fixture.assembler.close()
            throw error
        }
        try await fixture.assembler.close()
    }

    /// exactRevocationRetainsTheSoleTokenAcrossAFailedRefund proves the exact transfer keeps its
    /// reservation through a real injected refund failure and only then allows reuse.
    @Test func exactRevocationRetainsTheSoleTokenAcrossAFailedRefund() async throws {
        let fixture = try TransferFixture()
        let encoded = try transferImageFixture()
        let token = try await fixture.assembler.begin(
            totalBytes: encoded.count,
            binding   : fixture.binding
        )
        _ = try await fixture.assembler.append(
            transferID: token,
            binding   : fixture.binding,
            offset    : 0,
            bytes     : encoded
        )
        let charged = await fixture.governor.usage(.admittedMemoryBytes)
        await fixture.governor.armAssetTransferRefundFailureForTesting()
        fixture.assembler.revokeTransfer(binding: fixture.binding)
        await #expect(throws: AddonFailure.self) {
            try await fixture.assembler.drainPendingCleanup()
        }
        // The failed refund stays charged and retryable, and blocks new work meanwhile.
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == charged)
        #expect(fixture.assembler.nextDeadline != nil)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.assembler.begin(
                totalBytes: 1,
                binding   : fixture.binding
            )
        }
        try await fixture.assembler.drainPendingCleanup()
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        let replacement = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        try await fixture.assembler.abort(
            transferID: replacement,
            binding   : fixture.binding
        )
        try await fixture.assembler.close()
    }

    /// exactRevocationDuringAdmissionRefundsAndKeepsTheAssemblerUsable proves the narrow
    /// synchronous revocation covers a begin suspended inside protected admission.
    @Test func exactRevocationDuringAdmissionRefundsAndKeepsTheAssemblerUsable() async throws {
        let fixture = try TransferFixture()
        let gate = TransferGovernorGate()
        let blocker = Task.detached { await fixture.governor.holdTransferTest(gate) }
        await gate.reached()
        let pending = Task { try await fixture.assembler.begin(
            totalBytes: 65_536,
            binding   : fixture.binding
        ) }
        // sample() is taken before the governor hop, so this signals the begin is parked there.
        await fixture.clock.reached(1)
        fixture.assembler.revokeTransfer(binding: fixture.binding)
        gate.open()
        await blocker.value
        await #expect(throws: AddonFailure.self) { try await pending.value }
        // The retained admission token was refunded exactly once by the rejection path.
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 0)
        #expect(await fixture.governor.usage(.retainedStateBytes) == 0)
        #expect(fixture.assembler.nextDeadline == nil)
        let replacement = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        try await fixture.assembler.abort(
            transferID: replacement,
            binding   : fixture.binding
        )
        try await fixture.assembler.close()
    }

    /// exactRevocationDuringDecodeLetsTheNativeFinishRefundOnce proves a live native decode keeps
    /// its cleanup owner across a nonterminal revocation and the assembler returns to idle.
    @Test func exactRevocationDuringDecodeLetsTheNativeFinishRefundOnce() async throws {
        let governor = ResourceGovernor()
        let gate = TransferRasterGate(governor: governor)
        let coordinator = try AssetDisposalCoordinator(
            governor: governor,
            access  : gate
        )
        let decoder = BoundedAssetImageDecoder(coordinator: coordinator)
        let fixture = try TransferFixture(
            governor: governor,
            decoder : decoder
        )
        let encoded = try transferImageFixture()
        let token = try await fixture.assembler.begin(
            totalBytes: encoded.count,
            binding   : fixture.binding
        )
        _ = try await fixture.assembler.append(
            transferID: token,
            binding   : fixture.binding,
            offset    : 0,
            bytes     : encoded
        )
        let worker = Task { try await fixture.assembler.finish(
            transferID: token,
            binding   : fixture.binding
        ) }
        await gate.reached()
        let charged = await governor.usage(.admittedMemoryBytes)
        // The revocation must not refund bytes a live native decode still borrows.
        fixture.assembler.revokeTransfer(binding: fixture.binding)
        #expect(await governor.usage(.admittedMemoryBytes) == charged)
        await gate.open()
        await #expect(throws: AddonFailure.self) { try await worker.value }
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
        // Unlike a terminal close, the exact revocation leaves the assembler idle and reusable.
        let replacement = try await fixture.assembler.begin(
            totalBytes: 1,
            binding   : fixture.binding
        )
        try await fixture.assembler.abort(
            transferID: replacement,
            binding   : fixture.binding
        )
        try await fixture.assembler.close()
        decoder.close()
    }

    /// terminalInvalidationClosesWhileExactRevocationReturnsToIdle contrasts the two disposal
    /// owners: a terminally invalidated assembler closes for good, an exact revocation does not.
    @Test func terminalInvalidationClosesWhileExactRevocationReturnsToIdle() async throws {
        let terminal = try TransferFixture()
        let encoded = try transferImageFixture()
        let terminalToken = try await terminal.assembler.begin(
            totalBytes: encoded.count,
            binding   : terminal.binding
        )
        _ = try await terminal.assembler.append(
            transferID: terminalToken,
            binding   : terminal.binding,
            offset    : 0,
            bytes     : encoded
        )
        terminal.assembler.invalidate()
        try await terminal.assembler.drainPendingCleanup()
        #expect(await terminal.governor.usage(.admittedMemoryBytes) == 0)
        await #expect(throws: AddonFailure.self) {
            _ = try await terminal.assembler.begin(
                totalBytes: 1,
                binding   : terminal.binding
            )
        }
        // A later nonterminal drain can never reopen a terminally closed assembler.
        try await terminal.assembler.drainPendingCleanup()
        await #expect(throws: AddonFailure.self) {
            _ = try await terminal.assembler.begin(
                totalBytes: 1,
                binding   : terminal.binding
            )
        }

        let reusable = try TransferFixture()
        let reusableToken = try await reusable.assembler.begin(
            totalBytes: encoded.count,
            binding   : reusable.binding
        )
        _ = try await reusable.assembler.append(
            transferID: reusableToken,
            binding   : reusable.binding,
            offset    : 0,
            bytes     : encoded
        )
        reusable.assembler.revokeTransfer(binding: reusable.binding)
        try await reusable.assembler.drainPendingCleanup()
        #expect(await reusable.governor.usage(.admittedMemoryBytes) == 0)
        let recovered = try await reusable.assembler.begin(
            totalBytes: 1,
            binding   : reusable.binding
        )
        try await reusable.assembler.abort(
            transferID: recovered,
            binding   : reusable.binding
        )
        try await reusable.assembler.close()
    }
}

/// TransferCountingDecoder observes attempted decode entry while forwarding real codec work.
private final class TransferCountingDecoder: AssetImageDecoding, @unchecked Sendable {
    private let real: BoundedAssetImageDecoder
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    var assetGovernor: ResourceGovernor { real.assetGovernor }

    init(real: BoundedAssetImageDecoder) { self.real = real }

    func decode(
        encoded: Data,
        owner  : AddonID
    ) async throws -> AssetRasterBacking {
        lock.withLock { count += 1 }
        return try await real.decode(
            encoded: encoded,
            owner  : owner
        )
    }

    func close() { real.close() }
}

private struct TransferFixture {
    let governor   : ResourceGovernor
    let coordinator: AssetDisposalCoordinator
    let clock      = TransferClock()
    let binding    : AssetTransferBinding
    let assembler  : BoundedAssetTransferAssembler

    init(
        governor: ResourceGovernor = ResourceGovernor(),
        decoder : (any AssetImageDecoding)? = nil
    ) throws {
        let incarnation = RuntimeIncarnation()
        let owner = try #require(AddonID(rawValue: "com.example.transfer"))
        binding = AssetTransferBinding(
            incarnation    : incarnation,
            connectionToken: UUID(),
            publicationID  : PublicationID(
                addonID   : owner,
                instanceID: UUID(),
                sessionID : UUID()
            ),
            assignmentToken: UUID()
        )
        self.governor = governor
        coordinator = AssetDisposalCoordinator(governor: governor)
        assembler = BoundedAssetTransferAssembler(
            incarnation: incarnation,
            clock      : clock,
            decoder    : decoder ?? BoundedAssetImageDecoder(coordinator: coordinator)
        )
    }
}

private final class TransferClock: RuntimeClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value = RuntimeInstant(
        wall     : Date(timeIntervalSince1970: 0),
        monotonic: .zero
    )
    private var samples = 0
    private var wantedSample = 0
    private var arrival: CheckedContinuation<Void, Never>?
    func now() -> RuntimeInstant {
        lock.withLock {
            samples += 1
            if samples >= wantedSample {
                arrival?.resume()
                arrival = nil
            }
            return value
        }
    }
    func reached(_ count: Int) async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if samples >= count { continuation.resume() }
                else {
                    wantedSample = count
                    arrival = continuation
                }
            }
        }
    }
    func set(
        _ monotonic: Duration,
        wall: Double = 0
    ) {
        lock.withLock { value = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: wall),
            monotonic: monotonic
        ) }
    }
}

/// TransferIntegrityDecoder verifies arbitrary byte assembly at a controlled decoder boundary.
/// Its real decoder imports a separate valid fixture; this is not a claim that 1 MiB is a PNG.
private final class TransferIntegrityDecoder: AssetImageDecoding, @unchecked Sendable {
    let real: BoundedAssetImageDecoder
    let fixture: Data
    private let lock = NSLock()
    private var exact = false
    var wasExact: Bool { lock.withLock { exact } }
    var assetGovernor: ResourceGovernor { real.assetGovernor }
    init(
        real   : BoundedAssetImageDecoder,
        fixture: Data
    ) {
        self.real = real
        self.fixture = fixture
    }
    func decode(
        encoded: Data,
        owner  : AddonID
    ) async throws -> AssetRasterBacking {
        let matches = encoded.count == 1_048_576 && encoded.enumerated().allSatisfy { $0.element == UInt8($0.offset / 65_536) }
        lock.withLock { exact = matches }
        return try await real.decode(
            encoded: fixture,
            owner  : owner
        )
    }
    func close() { real.close() }
}

/// transferImageFixture uses Apple's encoder; the tiny RGBA fixture has hand-derived premultiplied bytes.
private func transferImageFixture(
    type       : String = "public.png",
    width      : Int = 2,
    height     : Int = 1,
    frames     : Int = 1,
    orientation: Int = 1,
    bits       : Int = 8,
    spaceName  : CFString = CGColorSpace.sRGB,
    pixelBytes : Data? = nil
) throws -> Data {
    let space = try #require(CGColorSpace(name: spaceName))
    let context = try #require(CGContext(
        data            : nil,
        width           : width,
        height          : height,
        bitsPerComponent: bits,
        bytesPerRow     : width * 4 * (bits / 8),
        space           : space,
        bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
            | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : CGBitmapInfo.byteOrder32Big.rawValue)
    ))
    context.setFillColorSpace(space)
    context.setFillColor([1, 0, 0, 0.5])
    context.fill(CGRect(
        x     : 0,
        y     : 0,
        width : width,
        height: height
    ))
    context.setFillColor([0, 1, 0, 1])
    context.fill(CGRect(
        x     : 1,
        y     : 0,
        width : 1,
        height: 1
    ))
    let image: CGImage
    if let pixelBytes {
        let provider = try #require(CGDataProvider(data: pixelBytes as CFData))
        image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    } else {
        image = try #require(context.makeImage())
    }
    let buffer = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        buffer,
        type as CFString,
        frames,
        nil
    ))
    for _ in 0..<frames {
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
    }
    #expect(CGImageDestinationFinalize(destination))
    return buffer as Data
}

/// TransferRasterGate pauses real canonical admission to expose teardown races deterministically.
private actor TransferRasterGate: AssetReservationAccess {
    nonisolated let assetGovernor: ResourceGovernor
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    init(governor: ResourceGovernor) { assetGovernor = governor }

    func reserveRaster(
        bytes: Int,
        owner: AddonID
    ) async throws -> RetainedAssetToken {
        let token = try await assetGovernor.admitRetainedAsset(
            bytes: bytes,
            owner: owner
        )
        entered = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { blocked = $0 }
        return token
    }

    func disposeRaster(_ token: RetainedAssetToken) async throws {
        try await assetGovernor.completeRetainedAsset(
            token,
            owner: token.reservation.owner
        )
    }

    func reached() async {
        if !entered { await withCheckedContinuation { arrival = $0 } }
    }

    func open() {
        blocked?.resume()
        blocked = nil
    }
}

/// TransferGovernorGate holds a real actor hop on a detached test worker, with no wall sleep.
/// Every test releases and awaits its worker before inspecting final accounting.
private final class TransferGovernorGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?

    func hold() {
        condition.lock()
        entered = true
        arrival?.resume()
        arrival = nil
        while !released { condition.wait() }
        condition.unlock()
    }

    func reached() async {
        await withCheckedContinuation { continuation in
            condition.lock()
            if entered { continuation.resume() }
            else { arrival = continuation }
            condition.unlock()
        }
    }

    func open() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

extension ResourceGovernor {
    fileprivate func holdTransferTest(_ gate: TransferGovernorGate) { gate.hold() }
}
