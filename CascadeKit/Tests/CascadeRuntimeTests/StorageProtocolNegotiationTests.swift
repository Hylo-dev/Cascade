//
//  StorageProtocolNegotiationTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadeRuntime
import Foundation
import Testing

@Suite
struct StorageProtocolNegotiationTests {

    private func negotiate(
        minimum        : Int = 0,
        maximum        : Int = 65_535,
        manifestMinimum: Int = 0,
        enabled        : Bool = false
    ) throws -> NegotiatedProtocol {
        try ProtocolNegotiator.negotiate(
            offer                     : ProtocolOffer(
                major         : 1,
                minimumMinor  : minimum,
                maximumMinor  : maximum,
                contentSchemas: [65_535, 2, 1]
            ),
            manifestProtocol          : ProtocolVersion(major: 1, minimumMinor: manifestMinimum),
            supportsKeyedStorageFrames: enabled
        )
    }

    @Test
    func defaultsStayAtZeroAndOptInSelectsHighestCommonMinor() throws {
        let legacy = try negotiate()

        #expect(legacy.minor == 0)
        #expect(legacy.storageFrameProfile == nil)
        #expect(legacy.contentSchemas == [1, 2])

        let current = try negotiate(enabled: true)

        #expect(current.minor == 1)
        #expect(current.storageFrameProfile == .v1_1)
        #expect(current.contentSchemas == legacy.contentSchemas)
        #expect(try negotiate(maximum: 0, enabled: true).minor == 0)
        #expect(
            try negotiate(
                minimum        : 1,
                maximum        : 1,
                manifestMinimum: 1,
                enabled        : true
            ).minor == 1
        )
        #expect(try negotiate(manifestMinimum: 1, enabled: true).minor == 1)

        let request = try StorageRequest(
            requestID: UUID(),
            operation: .read,
            key      : "key"
        )

        let encoded = try StorageFrameCodec.encode(request, profile: current.storageFrameProfile)

        #expect(try StorageFrameCodec.decodeRequest(encoded, profile: current.storageFrameProfile) == request)
        #expect(throws: AddonFailure.self) {
            _ = try StorageFrameCodec.encode(request, profile: legacy.storageFrameProfile)
        }
        #expect(throws: AddonFailure.self) {
            _ = try StorageFrameCodec.decodeRequest(encoded, profile: legacy.storageFrameProfile)
        }
    }

    @Test
    func assetCapabilityIsCumulativeAndDefaultsOff() throws {
        func makeOffer(maximum: Int) throws -> ProtocolOffer {
            try ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : maximum,
                contentSchemas: [1]
            )
        }

        let requirement = try ProtocolVersion(major: 1, minimumMinor: 0)

        // Storage-only hosts remain on 1.1 and expose no asset profile.
        let storageOnly = try ProtocolNegotiator.negotiate(
            offer                     : makeOffer(maximum: 65_535),
            manifestProtocol          : requirement,
            supportsKeyedStorageFrames: true
        )

        #expect(storageOnly.minor == 1)
        #expect(storageOnly.storageFrameProfile == .v1_1)
        #expect(storageOnly.assetFrameProfile == nil)

        // An asset-capable host advertises cumulative 1.2 only when the peer also allows it.
        let asset = try ProtocolNegotiator.negotiate(
            offer                     : makeOffer(maximum: 65_535),
            manifestProtocol          : requirement,
            supportsKeyedStorageFrames: true,
            supportsAssetFrames       : true
        )

        #expect(asset.minor == 2)
        #expect(asset.storageFrameProfile == .v1_1)
        #expect(asset.assetFrameProfile == .v1)
        #expect(
            try ProtocolNegotiator.negotiate(
                offer                     : makeOffer(maximum: 1),
                manifestProtocol          : requirement,
                supportsKeyedStorageFrames: true,
                supportsAssetFrames       : true
            ).minor == 1
        )

        // Asset capability alone never promotes a host without keyed-storage frames.
        let assetWithoutStorage = try ProtocolNegotiator.negotiate(
            offer                     : makeOffer(maximum: 65_535),
            manifestProtocol          : requirement,
            supportsKeyedStorageFrames: false,
            supportsAssetFrames       : true
        )

        #expect(assetWithoutStorage.minor == 0)
        #expect(assetWithoutStorage.assetFrameProfile == nil)

        // An untrusted offer cannot activate either host capability.
        let untrusted = try ProtocolNegotiator.negotiate(
            offer           : makeOffer(maximum: 65_535),
            manifestProtocol: requirement
        )

        #expect(untrusted.minor == 0)
        #expect(untrusted.storageFrameProfile == nil)
        #expect(untrusted.assetFrameProfile == nil)
    }

    @Test
    func incompatibleIntervalsAndMajorRemainRejected() throws {
        for enabled in [false, true] {
            #expect(throws: AddonFailure.self) {
                _ = try negotiate(minimum: 2, enabled: enabled)
            }
            #expect(throws: AddonFailure.self) {
                _ = try negotiate(manifestMinimum: 2, enabled: enabled)
            }
            #expect(throws: AddonFailure.self) {
                _ = try negotiate(
                    maximum        : 0,
                    manifestMinimum: 1,
                    enabled        : enabled
                )
            }
            #expect(throws: AddonFailure.self) {
                _ = try ProtocolNegotiator.negotiate(
                    offer                     : ProtocolOffer(
                        major         : 2,
                        minimumMinor  : 0,
                        maximumMinor  : 1,
                        contentSchemas: [1]
                    ),
                    manifestProtocol          : ProtocolVersion(major: 1, minimumMinor: 0),
                    supportsKeyedStorageFrames: enabled
                )
            }
            #expect(throws: AddonFailure.self) {
                _ = try ProtocolNegotiator.negotiate(
                    offer                     : ProtocolOffer(
                        major         : 1,
                        minimumMinor  : 0,
                        maximumMinor  : 1,
                        contentSchemas: [1]
                    ),
                    manifestProtocol          : ProtocolVersion(major: 2, minimumMinor: 0),
                    supportsKeyedStorageFrames: enabled
                )
            }
        }

        #expect(throws: AddonFailure.self) { _ = try negotiate(minimum: 1) }
        #expect(throws: AddonFailure.self) { _ = try negotiate(manifestMinimum: 1) }
    }

    @Test
    func optInPreservesContentSchemaPolicyAndSemanticErrorClassification() throws {
        let requirement = try ProtocolVersion(major: 1, minimumMinor: 0)
        let offer       = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 65_535,
            contentSchemas: [65_535, 2, 1]
        )

        #expect(
            try ProtocolNegotiator.negotiate(
                offer                     : offer,
                manifestProtocol          : requirement,
                contentSchemas            : [2],
                supportsKeyedStorageFrames: true
            ).contentSchemas == [2]
        )

        for policy in [[], [3], [1, 1], [1, 2, 3]] {
            do {
                _ = try ProtocolNegotiator.negotiate(
                    offer                     : offer,
                    manifestProtocol          : requirement,
                    contentSchemas            : policy,
                    supportsKeyedStorageFrames: true
                )

                Issue.record("Expected invalid host policy")
            } catch let error as AddonFailure {
                #expect(error.code == .invalidPayload)
            }
        }

        for minimum in [2, 65_535] {
            do {
                _ = try negotiate(minimum: minimum, enabled: true)
                Issue.record("Expected incompatible minor interval")
            } catch let error as AddonFailure {
                #expect(error.code == .versionConflict)
            }
        }

        do {
            _ = try ProtocolNegotiator.negotiate(
                offer                     : ProtocolOffer(
                    major         : 1,
                    minimumMinor  : 0,
                    maximumMinor  : 1,
                    contentSchemas: [3]
                ),
                manifestProtocol          : requirement,
                supportsKeyedStorageFrames: true
            )

            Issue.record("Expected incompatible content schemas")
        } catch let error as AddonFailure {
            #expect(error.code == .versionConflict)
        }
    }
}
