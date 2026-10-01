//
//  TransferFixture.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

struct TransferFixture {

    let governor   : ResourceGovernor
    let coordinator: AssetDisposalCoordinator
    let clock       = TransferClock()
    let binding    : AssetTransferBinding
    let assembler  : BoundedAssetTransferAssembler

    init(
        governor: ResourceGovernor = ResourceGovernor(),
        decoder : (any AssetImageDecoding)? = nil
    ) throws {
        let incarnation = RuntimeIncarnation()
        let owner       = try #require(AddonID(rawValue: "com.example.transfer"))
        binding         = AssetTransferBinding(
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
        coordinator   = AssetDisposalCoordinator(governor: governor)
        assembler     = BoundedAssetTransferAssembler(
            incarnation: incarnation,
            clock      : clock,
            decoder    : decoder ?? BoundedAssetImageDecoder(coordinator: coordinator)
        )
    }
}
