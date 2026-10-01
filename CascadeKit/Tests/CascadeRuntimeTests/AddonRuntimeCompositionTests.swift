//
//  AddonRuntimeCompositionTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AddonRuntimeCompositionTests {
    @Test
    func brokerUsesTheInjectedForwarderToReachItsCanonicalGovernor() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let access   = CountingRuntimeResourceAccess(target: governor)
        let broker   = ServiceBroker(
            governor      : governor,
            resourceAccess: access
        )

        _ = try await broker.authorize(fixture.permission())

        #expect(await access.admissionCount == 1)
        #expect(await governor.usage(.retainedStateBytes) == 5_120)
    }

    @Test
    func dispatcherQuotesWithoutRetentionAndConditionallyTakesTheInspectedJob() throws {
        let fixture = try ActionFixture()
        let request = try fixture.request()
        let instant = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        var dispatcher = ActionDispatcher()

        let classification = try dispatcher.classify(
            request: request,
            context: fixture.context(),
            at     : instant
        )
        #expect(classification == .admission(.init(
            owner        : fixture.owner,
            requestID    : request.requestID,
            retainedBytes: 94_208 + request.input.count
        )))
        #expect(dispatcher.retainedBytes == 0)

        _ = try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : instant
        )
        let inspected = try #require(dispatcher.peekReady(at: .zero))
        #expect(dispatcher.takeReady(
            expectedJobID: UUID(),
            at           : .zero
        ) == nil)
        #expect(dispatcher.runningCount == 0)
        #expect(dispatcher.takeReady(
            expectedJobID: inspected.id,
            at           : .zero
        ) != nil)
        #expect(dispatcher.runningCount == 1)
    }

    @Test
    func resourceGateCancellationReleasesItsStructuredChild() async throws {
        let owner = try ActionFixture().owner
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        await access.armJobAdmission()
        let reservation = try await withThrowingTaskGroup(
            of: ResourceReservation.self
        ) { group in
            group.addTask {
                try await access.admit(
                    .job,
                    owner: owner
                )
            }
            await access.waitForArrival()
            group.cancelAll()
            return try #require(try await group.next())
        }
        try await governor.release(
            reservation.id,
            owner: owner
        )
        #expect(await governor.usage(.jobs, owner: owner) == 0)
    }

    @Test
    func oversizedHostProjectionIsRejectedBeforeCatalogRetention() async throws {
        let fixture = try ActionFixture()
        let governor = ResourceGovernor()
        let capabilities = Dictionary(uniqueKeysWithValues: (0..<129).map {
            ("capability.\($0)", SemanticVersion(1, 0, 0))
        })
        await #expect(throws: AddonFailure.self) {
            _ = try await AddonRuntime.make(
                catalog: [fixture.context().installed],
                environment: HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: capabilities,
                    applications    : [:],
                    grants          : [fixture.owner: []],
                    explicitBindings: []
                ),
                governor: governor,
                adapter : RecordingRuntimeAdapter()
            )
        }
        #expect(await governor.usage(.retainedStateBytes, owner: fixture.owner) == 0)

        let featureTemplate = try (0..<64).map { index in
            try AddonFeature(
                id      : "feature_\(index)",
                requires: [requirement("missing.service.\(index)", ">=1.0.0 <2.0.0")],
                actions : nil
            )
        }
        let base = try installedFixture("consumer")
        let resultHeavyCatalog = try (0..<32).map { index in
            try replacing(
                base,
                id      : "com.example.result-heavy-\(index)",
                requires: [],
                provides: [],
                features: featureTemplate
            )
        }
        let resultHeavyGrants = Dictionary(uniqueKeysWithValues: resultHeavyCatalog.map {
            ($0.manifest.id, Set<String>())
        })
        await #expect(throws: AddonFailure.self) {
            _ = try await AddonRuntime.make(
                catalog: resultHeavyCatalog,
                environment: HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : resultHeavyGrants,
                    explicitBindings: []
                ),
                governor: governor,
                adapter : RecordingRuntimeAdapter()
            )
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)

        let oversizedKey = String(repeating: "x", count: 192 * 1_024)
        await #expect(throws: AddonFailure.self) {
            _ = try await AddonRuntime.make(
                catalog: [fixture.context().installed],
                environment: HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [oversizedKey: SemanticVersion(1, 0, 0)],
                    applications    : [:],
                    grants          : [fixture.owner: []],
                    explicitBindings: []
                ),
                governor: governor,
                adapter : RecordingRuntimeAdapter()
            )
        }
        #expect(await governor.usage(.retainedStateBytes, owner: fixture.owner) == 0)

        let oversizedVersion = SemanticVersion(
            1,
            0,
            0,
            prerelease   : String(repeating: "p", count: 70 * 1_024),
            buildMetadata: String(repeating: "b", count: 70 * 1_024)
        )
        let nestedEnvironment = HostEnvironment(
            osVersion       : oversizedVersion,
            hostCapabilities: ["short": oversizedVersion],
            applications    : [:],
            grants          : [fixture.owner: []],
            explicitBindings: [ServiceBinding(
                requirementID  : "short",
                consumer       : fixture.owner,
                provider       : fixture.owner,
                providerIdentity: try fixture.context().installed.verifiedIdentity,
                contractVersion: oversizedVersion,
                digest          : "short",
                featureID       : "controls"
            )]
        )
        #expect(AddonRuntime.environmentProjectionBytes(nestedEnvironment) == nil)
        await #expect(throws: AddonFailure.self) {
            _ = try await AddonRuntime.make(
                catalog    : [fixture.context().installed],
                environment: nestedEnvironment,
                governor   : governor,
                adapter    : RecordingRuntimeAdapter()
            )
        }
        #expect(await governor.usage(.retainedStateBytes, owner: fixture.owner) == 0)
    }

    @Test
    func endedPublicationAssignmentsBecomeReusableAfterExactExit() async throws {
        let fixture = try ActionFixture()
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog: [fixture.context().installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor: governor,
            adapter : adapter,
            clock   : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        var ids: [PublicationID] = []
        for _ in 0..<16 {
            ids.append(try await runtime.assignPublication(
                owner     : fixture.owner,
                featureID : "controls",
                instanceID: UUID()
            ))
        }
        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let document = try #require(fixture.presentation().widget)
        let activityContent = try PresentationSet(
            widget          : nil,
            compactLeading  : document,
            compactTrailing : document,
            minimal         : document,
            expanded        : document
        )
        let noticeContent = try PresentationSet(
            widget          : nil,
            compactLeading  : document,
            compactTrailing : document,
            minimal         : document,
            expanded        : nil
        )
        let publications = try ids.enumerated().map { index, id in
            try Publication(
                id         : id,
                revision   : 1,
                kind       : index == 0 ? .activity : index == 1 ? .notice : .widget,
                content    : index == 0
                    ? activityContent
                    : index == 1 ? noticeContent : fixture.presentation(),
                timeline   : nil,
                expiresAt  : fixture.wall.addingTimeInterval(100),
                stalePolicy: .remove
            )
        }
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : try ProviderOutput(
                schemaVersion: 1,
                publications: publications,
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        #expect(await governor.usage(.publications, owner: fixture.owner) == 16)
        #expect(await governor.usage(.activities, owner: fixture.owner) == 1)
        #expect(await governor.usage(.notices, owner: fixture.owner) == 1)
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : try ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations  : ids.map { .endPublication($0) },
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 2
        )
        #expect(await governor.usage(.publications, owner: fixture.owner) == 0)
        #expect(await governor.usage(.activities, owner: fixture.owner) == 0)
        #expect(await governor.usage(.notices, owner: fixture.owner) == 0)
        _ = try await runtime.serviceDeadlines()
        await #expect(throws: AddonFailure.self) {
            _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : ProviderOutput(
                    schemaVersion: 1,
                    publications: [publications[0]],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : nil
                ),
                connection: connection,
                sequence  : 3
            )
        }
        await runtime.observeExit(connection.incarnation)
        _ = try await runtime.serviceDeadlines()
        _ = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
    }

    @Test
    func disabledAuthorizationRollsBackItsExactBrokerPermission() async throws {
        let consumer = try installedFixture("consumer", publisher: "shared.publisher")
        let provider = try installedFixture("focus", publisher: "shared.publisher")
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog: [consumer, provider],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [consumer.manifest.id: [], provider.manifest.id: []],
                explicitBindings: []
            ),
            governor             : governor,
            resourceAccess       : access,
            serviceDecisionFactory: { $0 },
            adapter              : adapter,
            clock                : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000),
                monotonic: .zero
            ))
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let launch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : offer
        )
        let scope = try ServiceScope(
            featureID: "summary",
            operation: "read"
        )
        await access.armStateAdmission()
        async let authorizing = runtime.authorizeService(
            connection           : connection,
            requirementID        : "com.example.focus.sessions",
            scope                : scope,
            partition            : "account-a",
            crossPublisherConsent: true
        )
        await access.waitForArrival()
        await runtime.disable(owner: consumer.manifest.id)
        await access.releaseGate()
        do {
            _ = try await authorizing
            Issue.record("Disabled authority completed a suspended service authorization.")
        } catch is AddonFailure {}
        await runtime.observeExit(connection.incarnation)
        try await runtime.enable(owner: consumer.manifest.id)
        let replacementLaunch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let replacement = try await runtime.attach(
            launchID: replacementLaunch,
            offer   : offer
        )
        _ = try await runtime.authorizeService(
            connection           : replacement,
            requirementID        : "com.example.focus.sessions",
            scope                : scope,
            partition            : "account-a",
            crossPublisherConsent: true
        )
    }

    @Test
    func synchronousNeverHandedOffRejectionRetainsRecoverableHistory() throws {
        let fixture = try ActionFixture()
        let request = try fixture.request()
        let instant = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        let generation = ConnectionGeneration()
        var dispatcher = ActionDispatcher()
        _ = try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : instant
        )
        let inspected = try #require(dispatcher.peekReady(at: .zero))
        let ticketValue = dispatcher.takeReady(
            expectedJobID: inspected.id,
            at           : .zero
        )
        let ticket = try #require(ticketValue)
        let delivery = try #require(try dispatcher.consume(
            ticket,
            context   : fixture.context(),
            generation: generation,
            at        : instant
        ))
        let failure = AddonFailure(
            code  : .dependencyUnavailable,
            reason: "The transport rejected the delivery before handoff."
        )

        let firstRejection = dispatcher.rejectNeverHandedOff(
            delivery: delivery,
            failure : failure
        )
        let repeatedRejection = dispatcher.rejectNeverHandedOff(
            delivery: delivery,
            failure : failure
        )
        #expect(firstRejection)
        #expect(!repeatedRejection)
        #expect(dispatcher.runningCount == 0)
        #expect(dispatcher.jobCount == 0)
        #expect(try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : instant
        ) == .duplicate(.finished(.rejected(reason: failure))))
    }

    @Test
    func tightGovernorDenialsLeaveCatalogLaunchAndConnectionTransactional() async throws {
        let fixture = try ActionFixture()
        let installed = try fixture.context().installed
        let deniedGovernor = ResourceGovernor(policy: ResourcePolicy(
            maximumRetainedStateBytes: 214_015
        ))
        await #expect(throws: AddonFailure.self) {
            try await AddonRuntime.make(
                catalog: [installed],
                environment: HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [fixture.owner: []],
                    explicitBindings: []
                ),
                governor: deniedGovernor,
                adapter : RecordingRuntimeAdapter(),
                clock   : FixedRuntimeClock(instant: RuntimeInstant(
                    wall     : fixture.wall,
                    monotonic: .zero
                ))
            )
        }
        #expect(await deniedGovernor.usage(.retainedStateBytes) == 0)

        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog: [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor: governor,
            adapter : adapter,
            clock   : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        let baseline = await governor.usage(.retainedStateBytes)
        let fillerOwner = AddonID(rawValue: "com.example.runtime-pressure-filler")!
        var filler = try await governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - baseline - 1_024),
            owner: fillerOwner
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.requestLaunch(owner: fixture.owner)
        }
        #expect(adapter.startCount(owner: fixture.owner) == 0)
        #expect(await governor.usage(.providers, owner: fixture.owner) == 0)
        #expect(await runtime.diagnostics(owner: fixture.owner)?.hasProcess == false)
        try await governor.release(
            filler.id,
            owner: fillerOwner
        )

        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let beforeConnection = await governor.usage(.retainedStateBytes)
        filler = try await governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - beforeConnection - 1_024),
            owner: fillerOwner
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.attach(
                launchID: launch,
                offer   : ProtocolOffer(
                    major         : 1,
                    minimumMinor  : 0,
                    maximumMinor  : 0,
                    contentSchemas: [1]
                )
            )
        }
        #expect(await runtime.diagnostics(owner: fixture.owner)?.hasProcess == true)
        #expect(await governor.usage(.retainedStateBytes) == 8 * 1_024 * 1_024)
        try await governor.release(
            filler.id,
            owner: fillerOwner
        )
        _ = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        #expect(await governor.usage(.retainedStateBytes) == beforeConnection + 5_120 + 2_048)

        let disabled = try InstalledAddon(
            manifest        : installed.manifest,
            verifiedIdentity: installed.verifiedIdentity,
            digest          : installed.digest,
            enabled         : false
        )
        let disabledGovernor = ResourceGovernor()
        let disabledAdapter = RecordingRuntimeAdapter()
        let disabledRuntime = try await AddonRuntime.make(
            catalog: [disabled],
            environment: HostEnvironment(
                osVersion         : SemanticVersion(14, 0, 0),
                hostCapabilities  : [:],
                applications      : [:],
                grants            : [fixture.owner: []],
                explicitBindings  : []
            ),
            governor: disabledGovernor,
            adapter : disabledAdapter,
            clock   : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        await #expect(throws: AddonFailure.self) {
            try await disabledRuntime.requestLaunch(owner: fixture.owner)
        }
        #expect(disabledAdapter.startCount(owner: fixture.owner) == 0)
        #expect(await disabledGovernor.usage(.providers, owner: fixture.owner) == 0)
    }

    @Test
    func runtimePublishesDispatchesCompletesAndRefundsOnRealExit() async throws {
        let fixture   = try ActionFixture()
        let context   = try fixture.context()
        let installed = context.installed
        let governor  = ResourceGovernor()
        let adapter   = RecordingRuntimeAdapter()
        let clock     = MutableRuntimeClock(instant: RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        ))
        let environment = HostEnvironment(
            osVersion         : SemanticVersion(14, 0, 0),
            hostCapabilities  : [:],
            applications      : [:],
            grants            : [fixture.owner: []],
            explicitBindings  : [],
            protocolVersion   : (1, 0),
            serviceAccessGrants: []
        )
        let runtime = try await AddonRuntime.make(
            catalog    : [installed],
            environment: environment,
            governor   : governor,
            adapter    : adapter,
            clock      : clock
        )
        let publicationID = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launchID = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launchID,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1, 2]
            )
        )
        let publication = try Publication(
            id         : publicationID,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
        let memoryFiller = try await governor.admit(
            .temporaryMemory(bytes: 64 * 1_024 * 1_024),
            owner: fixture.owner
        )
        await #expect(throws: AddonFailure.self) {
            try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
                ProviderOutput(
                    schemaVersion: 1,
                    publications: [publication],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : nil
                ),
                connection: connection,
                sequence  : 1
            )
        }
        try await governor.release(
            memoryFiller.id,
            owner: fixture.owner
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [publication],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        let updatedPublication = try Publication(
            id         : publicationID,
            revision   : 2,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
        let unassignedPublication = try Publication(
            id: PublicationID(
                addonID   : fixture.owner,
                instanceID: UUID(),
                sessionID : UUID()
            ),
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
        await #expect(throws: AddonFailure.self) {
            try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
                ProviderOutput(
                    schemaVersion: 1,
                    publications: [updatedPublication, unassignedPublication],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : nil
                ),
                connection: connection,
                sequence  : 2
            )
        }
        #expect(await runtime.snapshot(at: fixture.wall).publications == [publication])
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [updatedPublication],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 2
        )
        let request = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 2
        )
        var commandFillers: [ResourceReservation] = []
        for _ in 0..<4 {
            commandFillers.append(try await governor.admit(
                .command,
                owner: fixture.owner
            ))
        }
        let stateBeforeDeniedCommand = await governor.usage(
            .retainedStateBytes,
            owner: fixture.owner
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.submitAction(request)
        }
        #expect(await runtime.actionState(request.requestID, owner: fixture.owner) == nil)
        #expect(await governor.usage(.retainedStateBytes, owner: fixture.owner) == stateBeforeDeniedCommand)
        for reservation in commandFillers {
            try await governor.release(
                reservation.id,
                owner: fixture.owner
            )
        }
        #expect(try await runtime.submitAction(request) == .admitted)
        #expect(try await runtime.pumpReady())
        #expect(try await !runtime.pumpReady())
        #expect(await runtime.diagnostics(owner: fixture.owner)?.hasOutstandingDelivery == true)
        _ = try #require(adapter.lastAction)
        let completedPublication = try Publication(
            id         : publicationID,
            revision   : 3,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
        await #expect(throws: AddonFailure.self) {
            try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
                ProviderOutput(
                    schemaVersion: 1,
                    publications: [completedPublication],
                    operations  : [],
                    completion  : .action(
                        requestID: UUID(),
                        outcome  : .completed(payload: Data([9]))
                    ),
                    checkpoint: nil
                ),
                connection: connection,
                sequence  : 3
            )
        }
        #expect(await runtime.snapshot(at: fixture.wall).publications == [updatedPublication])
        await #expect(throws: AddonFailure.self) {
            try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
                ProviderOutput(
                    schemaVersion: 1,
                    publications: [completedPublication],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : Data([1])
                ),
                connection: connection,
                sequence  : 3
            )
        }
        let correlatedAdmission = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [completedPublication],
                operations  : [],
                completion  : .action(
                    requestID: request.requestID,
                    outcome  : .completed(payload: Data([9]))
                ),
                checkpoint: nil
            ),
            connection: connection,
            sequence  : 3
        )
        #expect(correlatedAdmission.completion == .action(
            requestID: request.requestID,
            outcome  : .completed(payload: Data([9]))
        ))
        #expect(await runtime.diagnostics(owner: fixture.owner)?.hasOutstandingDelivery == false)
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
        #expect(await governor.usage(.providers, owner: fixture.owner) == 1)
        #expect(await runtime.snapshot(at: fixture.wall).publications == [completedPublication])
        let usedState = await governor.usage(.retainedStateBytes)
        let fillerOwner = AddonID(rawValue: "com.example.runtime-filler")!
        let filler = try await governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - usedState - 1_024),
            owner: fillerOwner
        )
        #expect(await governor.usage(.retainedStateBytes) == 8 * 1_024 * 1_024)
        #expect(try await runtime.submitAction(request) == .duplicate(.finished(
            .completed(payload: Data([9]))
        )))
        try await governor.release(
            filler.id,
            owner: fillerOwner
        )

        let firstAtRevisionThree = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 3
        )
        let secondAtRevisionThree = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 3
        )
        _ = try await runtime.submitAction(firstAtRevisionThree)
        _ = try await runtime.submitAction(secondAtRevisionThree)
        #expect(try await runtime.pumpReady())
        let revisionFour = try Publication(
            id         : publicationID,
            revision   : 4,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [revisionFour],
                operations  : [],
                completion  : .action(
                    requestID: firstAtRevisionThree.requestID,
                    outcome  : .completed(payload: Data())
                ),
                checkpoint: nil
            ),
            connection: connection,
            sequence  : 4
        )
        await #expect(throws: ActionAuthorizer.Failure.self) {
            try await runtime.pumpReady()
        }
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)

        let maximumResultRequest = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 4
        )
        _ = try await runtime.submitAction(maximumResultRequest)
        #expect(try await runtime.pumpReady())
        let runningState = await governor.usage(.retainedStateBytes)
        let completionFiller = try await governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - runningState - 1_024),
            owner: fillerOwner
        )
        #expect(await governor.usage(.retainedStateBytes) == 8 * 1_024 * 1_024)
        let maximumResult = Data(
            repeating: 9,
            count    : 65_536
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations  : [],
                completion  : .action(
                    requestID: maximumResultRequest.requestID,
                    outcome  : .completed(payload: maximumResult)
                ),
                checkpoint: nil
            ),
            connection: connection,
            sequence  : 5
        )
        #expect(await runtime.actionState(
            maximumResultRequest.requestID,
            owner: fixture.owner
        ) == .finished(.completed(payload: maximumResult)))
        try await governor.release(
            completionFiller.id,
            owner: fillerOwner
        )

        let uncertain = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 4
        )
        _ = try await runtime.submitAction(uncertain)
        #expect(try await runtime.pumpReady())
        let uncertainDelivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveAcknowledgment(
            uncertainDelivery,
            connection: connection
        ))
        #expect(await governor.usage(.commands, owner: fixture.owner) == 1)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 1)
        #expect(await governor.usage(.providers, owner: fixture.owner) == 1)
        clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(700),
            monotonic: .seconds(700)
        ))
        _ = try await runtime.serviceDeadlines()
        #expect(await runtime.actionState(
            uncertain.requestID,
            owner: fixture.owner
        ) == nil)
        #expect(await governor.usage(.commands, owner: fixture.owner) == 1)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 1)
        #expect(await governor.usage(.providers, owner: fixture.owner) == 1)
        #expect(await runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes ?? 0 >= 884_736)
        #expect(adapter.stopCount(incarnation: connection.incarnation) == 1)
        await runtime.disable(owner: fixture.owner)
        #expect(adapter.stopCount(incarnation: connection.incarnation) == 1)
        await #expect(throws: AddonFailure.self) {
            try await runtime.receiveActionCompletion(
                uncertainDelivery,
                connection: connection,
                outcome   : .completed(payload: Data([8]))
            )
        }
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 1)
        await #expect(throws: AddonFailure.self) {
            try await runtime.requestLaunch(owner: fixture.owner)
        }
        await runtime.observeExit(connection.incarnation)
        #expect(adapter.tryHandoff(
            incarnation: connection.incarnation,
            delivery   : .action(uncertainDelivery)
        ) == .rejectedBeforeHandoff)
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
        #expect(await governor.usage(.providers, owner: fixture.owner) == 0)
        try await runtime.enable(owner: fixture.owner)
        let replacementLaunch = try await runtime.requestLaunch(owner: fixture.owner)
        let replacement = try await runtime.attach(
            launchID: replacementLaunch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1, 2]
            )
        )
        await runtime.observeExit(connection.incarnation)
        #expect(await governor.usage(.providers, owner: fixture.owner) == 1)
        await #expect(throws: AddonFailure.self) {
            try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
                ProviderOutput(
                    schemaVersion: 1,
                    publications: [updatedPublication],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : nil
                ),
                connection: connection,
                    sequence  : 6
            )
        }
        await runtime.stop()
        await runtime.observeExit(replacement.incarnation)
        #expect(await governor.usage(.providers, owner: fixture.owner) == 0)
        await #expect(throws: AddonFailure.self) {
            try await runtime.requestLaunch(owner: fixture.owner)
        }
    }

    @Test
    func directServiceWorkCompetesForSharedCommandAndJobPermits() async throws {
        let serviceConsumer = try installedFixture("consumer", publisher: "shared.publisher")
        let actionFixture = try ActionFixture()
        let actionAddon = try actionFixture.context().installed
        let consumer = try replacing(
            serviceConsumer,
            features: serviceConsumer.manifest.features + actionAddon.manifest.features
        )
        let baseProvider = try installedFixture("focus", publisher: "shared.publisher")
        let leafService = try ProvidedService(
            kind   : .service,
            id     : "com.example.runtime.leaf",
            version: "1.0.0"
        )
        let leaf = try replacing(
            baseProvider,
            id      : "com.example.runtime.leaf-provider",
            requires: [],
            provides: [leafService],
            features: baseProvider.manifest.features + actionAddon.manifest.features
        )
        let provider = try replacing(
            baseProvider,
            id      : "com.example.runtime.focus-provider",
            requires: [requirement("com.example.runtime.leaf", ">=1.0.0 <2.0.0")],
            features: baseProvider.manifest.features + actionAddon.manifest.features
        )
        let governor = ResourceGovernor()
        let resourceAccess = GatedRuntimeResourceAccess(target: governor)
        let adapter  = RecordingRuntimeAdapter()
        let decisionBox = RuntimeServiceDecisionAccessBox()
        let now = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .seconds(10)
        )
        let clock = MutableRuntimeClock(instant: now)
        let runtime = try await AddonRuntime.make(
            catalog: [consumer, provider, leaf],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants: [
                    consumer.manifest.id: [],
                    provider.manifest.id: [],
                    leaf.manifest.id    : []
                ],
                explicitBindings: []
            ),
            governor      : governor,
            resourceAccess: resourceAccess,
            serviceDecisionFactory: { broker in
                let access = GatedRuntimeServiceDecisionAccess(target: broker)
                decisionBox.access = access
                return access
            },
            adapter: adapter,
            clock  : clock
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let actionPublicationID = try await runtime.assignPublication(
            owner     : consumer.manifest.id,
            featureID : "controls",
            instanceID: UUID()
        )
        let leafPublicationID = try await runtime.assignPublication(
            owner     : leaf.manifest.id,
            featureID : "controls",
            instanceID: UUID()
        )
        let consumerLaunch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let consumerConnection = try await runtime.attach(
            launchID: consumerLaunch,
            offer   : offer
        )
        let actionPublication = try Publication(
            id         : actionPublicationID,
            revision   : 1,
            kind       : .widget,
            content    : actionFixture.presentation(),
            timeline   : nil,
            expiresAt  : now.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [actionPublication],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: consumerConnection,
            sequence  : 1
        )
        let scope = try ServiceScope(
            featureID: "summary",
            operation: "read"
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.authorizeService(
                connection           : consumerConnection,
                requirementID        : "com.example.focus.sessions",
                scope                : try ServiceScope(
                    featureID: "not-assigned",
                    operation: "read"
                ),
                partition            : "account-a",
                crossPublisherConsent: true
            )
        }
        let permissionID = try await runtime.authorizeService(
            connection           : consumerConnection,
            requirementID        : "com.example.focus.sessions",
            scope                : scope,
            partition            : "account-a",
            crossPublisherConsent: true
        )
        do {
            _ = try await runtime.acquireService(
                connection  : consumerConnection,
                permissionID: permissionID,
                lifetime    : .seconds(30)
            )
            Issue.record("A service acquisition completed before its missing provider attached.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .dependencyUnavailable)
        }
        let leafStart = try #require(adapter.lastStart(owner: leaf.manifest.id))
        let providerStart = try #require(adapter.lastStart(owner: provider.manifest.id))
        #expect(adapter.startOwners.suffix(2) == [
            leaf.manifest.id,
            provider.manifest.id
        ])
        let leafConnection = try await runtime.attach(
            launchID: leafStart.launchID,
            offer   : offer
        )
        #expect(adapter.startCount(owner: provider.manifest.id) == 1)
        #expect(await governor.usage(.providers, owner: provider.manifest.id) == 1)
        let providerConnection = try await runtime.attach(
            launchID: providerStart.launchID,
            offer   : offer
        )
        let leafPublication = try Publication(
            id         : leafPublicationID,
            revision   : 1,
            kind       : .widget,
            content    : actionFixture.presentation(),
            timeline   : nil,
            expiresAt  : now.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [leafPublication],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: leafConnection,
            sequence  : 1
        )
        let blockedSourceJob = try await governor.admit(
            .job,
            owner: provider.manifest.id
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : consumerConnection,
                permissionID: permissionID,
                lifetime    : .seconds(30)
            )
        }
        try await governor.release(
            blockedSourceJob.id,
            owner: provider.manifest.id
        )
        let decisionAccess = try #require(decisionBox.access)
        await decisionAccess.armSource()
        async let expiringSource = runtime.acquireService(
            connection  : consumerConnection,
            permissionID: permissionID,
            lifetime    : .seconds(1)
        )
        await decisionAccess.waitForArrival()
        let busyOutput = try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations  : [],
            completion  : nil,
            checkpoint  : nil
        )
        let busyIngress = try #require(adapter.stageIngress(
            busyOutput,
            incarnation: providerConnection.incarnation
        ))
        await #expect(throws: AddonFailure.self) {
            try await runtime.receivePublicationOutput(
                busyIngress,
                connection: providerConnection,
                sequence  : 1
            )
        }
        let restagedIngress = try #require(adapter.stageIngress(
            busyOutput,
            incarnation: providerConnection.incarnation
        ))
        adapter.rejectIngress(
            restagedIngress,
            incarnation: providerConnection.incarnation
        )
        clock.set(RuntimeInstant(
            wall     : now.wall.addingTimeInterval(2),
            monotonic: now.monotonic + .seconds(2)
        ))
        await decisionAccess.releaseGate()
        do {
            _ = try await expiringSource
            Issue.record("An expired source acquisition completed after its suspended consume.")
        } catch is AddonFailure {}
        #expect(adapter.sourceDeliveryCount == 0)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
        clock.set(now)
        let acquisition = try await runtime.acquireService(
            connection  : consumerConnection,
            permissionID: permissionID,
            lifetime    : .seconds(30)
        )
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 1)
        let sourceRowReserved = try #require(await runtime.diagnostics(
            owner: provider.manifest.id
        )).reservedStateBytes
        #expect(try await runtime.receiveSourceStartupCompletion(
            acquisition.sourceID,
            connection: providerConnection
        ))
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
        #expect(try #require(await runtime.diagnostics(
            owner: provider.manifest.id
        )).reservedStateBytes == sourceRowReserved - 4_096)
        await #expect(throws: AddonFailure.self) {
            try await runtime.beginServiceInvocation(
                connection: consumerConnection,
                grantID   : acquisition.grant.id,
                invocation: ServiceInvocation(
                    schemaVersion: 1,
                    requestID    : UUID(),
                    contractID   : "com.example.focus.sessions",
                    operation    : "write",
                    payload      : Data(),
                    deadline     : now.wall.addingTimeInterval(20)
                )
            )
        }
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
        let work = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([1]),
                deadline     : now.wall.addingTimeInterval(5)
            )
        )
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 1)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 1)
        #expect(try await runtime.pumpServiceInvocation(work.id))
        let nestedPermissionID = try await runtime.authorizeService(
            connection           : providerConnection,
            requirementID        : "com.example.runtime.leaf",
            scope                : try ServiceScope(
                featureID: "controls",
                operation: "read"
            ),
            partition            : "account-a",
            crossPublisherConsent: true
        )
        let nestedAcquisition = try await runtime.acquireService(
            connection  : providerConnection,
            permissionID: nestedPermissionID,
            lifetime    : .seconds(30)
        )
        if await governor.usage(.jobs, owner: leaf.manifest.id) == 1 {
            #expect(try await runtime.receiveSourceStartupCompletion(
                nestedAcquisition.sourceID,
                connection: leafConnection
            ))
        }
        await #expect(throws: AddonFailure.self) {
            try await runtime.beginServiceInvocation(
                connection: providerConnection,
                grantID   : nestedAcquisition.grant.id,
                invocation: ServiceInvocation(
                    schemaVersion: 1,
                    requestID    : UUID(),
                    contractID   : "com.example.runtime.leaf",
                    operation    : "read",
                    payload      : Data([5]),
                    deadline     : now.wall.addingTimeInterval(20)
                )
            )
        }
        #expect(await governor.usage(.commands, owner: provider.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: leaf.manifest.id) == 0)
        #expect(adapter.serviceDeliveryCount == 1)
        let firstAction = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : actionPublicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : now.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        let secondAction = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : leafPublicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : now.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(firstAction)
        _ = try await runtime.submitAction(secondAction)
        #expect(try await runtime.pumpReady())
        await #expect(throws: AddonFailure.self) {
            try await runtime.pumpReady()
        }
        #expect(await governor.usage(.jobs, owner: leaf.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: consumer.manifest.id) == 1)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 1)
        let firstDelivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveActionCompletion(
            firstDelivery,
            connection: consumerConnection,
            outcome   : .completed(payload: Data())
        ))
        #expect(try await runtime.pumpReady())
        let secondDelivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveActionCompletion(
            secondDelivery,
            connection: leafConnection,
            outcome   : .completed(payload: Data())
        ))
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : "com.example.focus.sessions",
            operation    : "read",
            payload      : Data([2])
        )
        let actionDuringCompletion = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : actionPublicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : now.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(actionDuringCompletion)
        await resourceAccess.armJobAdmission()
        async let pumpingWhileCompletionArrives = runtime.pumpReady()
        await resourceAccess.waitForArrival()
        let serviceOutput = try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations  : [],
            completion  : .service(
                requestID: work.invocation.requestID,
                response : response
            ),
            checkpoint: nil
        )
        let serviceIngress = try #require(adapter.stageIngress(
            serviceOutput,
            incarnation: providerConnection.incarnation
        ))
        #expect(try await runtime.receivePublicationOutput(
            serviceIngress,
            connection: providerConnection,
            sequence  : 1
        ) == .pendingServiceCompletion)
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 2)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 1)
        await #expect(throws: AddonFailure.self) {
            try await runtime.serviceOutcome(
                connection: consumerConnection,
                grantID   : acquisition.grant.id,
                requestID : work.invocation.requestID
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await runtime.receiveServiceCompletion(
                work.id,
                connection: providerConnection,
                response  : try ServiceResponse(
                    schemaVersion: 1,
                    contractID   : "com.example.focus.sessions",
                    operation    : "read",
                    payload      : Data([3])
                )
            )
        }
        clock.set(RuntimeInstant(
            wall     : now.wall.addingTimeInterval(6),
            monotonic: now.monotonic + .seconds(6)
        ))
        await resourceAccess.releaseGate()
        #expect(try await pumpingWhileCompletionArrives)
        #expect(try await runtime.serviceOutcome(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            requestID : work.invocation.requestID
        ) == .completed(response))
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: providerConnection,
            sequence  : 2
        )
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 1)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
        let actionDuringCompletionDelivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveActionCompletion(
            actionDuringCompletionDelivery,
            connection: consumerConnection,
            outcome   : .completed(payload: Data())
        ))
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 0)
        clock.set(now)

        let beforeShortGrant = try #require(await runtime.diagnostics(
            owner: consumer.manifest.id
        ))
        let shortGrant = try await runtime.acquireService(
            connection  : consumerConnection,
            permissionID: permissionID,
            lifetime    : .seconds(1)
        )
        let duringShortGrant = try #require(await runtime.diagnostics(
            owner: consumer.manifest.id
        ))
        #expect(duringShortGrant.reservedStateBytes - beforeShortGrant.reservedStateBytes == 2_048)
        let shortWork = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : shortGrant.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([8]),
                deadline     : now.wall.addingTimeInterval(20)
            )
        )
        #expect(try await runtime.pumpServiceInvocation(shortWork.id))
        await resourceAccess.armReduction()
        async let acceptingShortCompletion = runtime.receiveServiceCompletion(
            shortWork.id,
            connection: providerConnection,
            response  : response
        )
        await resourceAccess.waitForArrival()
        await #expect(throws: AddonFailure.self) {
            try await runtime.receiveServiceCompletion(
                shortWork.id,
                connection: providerConnection,
                response  : ServiceResponse(
                    schemaVersion: 1,
                    contractID   : "com.example.focus.sessions",
                    operation    : "read",
                    payload      : Data([4])
                )
            )
        }
        clock.set(RuntimeInstant(
            wall     : now.wall.addingTimeInterval(2),
            monotonic: now.monotonic + .seconds(2)
        ))
        await #expect(throws: AddonFailure.self) {
            try await runtime.serviceOutcome(
                connection: consumerConnection,
                grantID   : shortGrant.grant.id,
                requestID : shortWork.invocation.requestID
            )
        }
        await resourceAccess.releaseGate()
        #expect(try await acceptingShortCompletion == .accepted(response))
        await #expect(throws: AddonFailure.self) {
            try await runtime.serviceOutcome(
                connection: consumerConnection,
                grantID   : shortGrant.grant.id,
                requestID : shortWork.invocation.requestID
            )
        }
        let beforeShortGrantExpiry = try #require(await runtime.diagnostics(
            owner: consumer.manifest.id
        ))
        _ = try await runtime.serviceDeadlines()
        let afterShortGrant = try #require(await runtime.diagnostics(
            owner: consumer.manifest.id
        ))
        #expect(afterShortGrant.reservedStateBytes == beforeShortGrantExpiry.reservedStateBytes - 2_048)
        await #expect(throws: AddonFailure.self) {
            try await runtime.serviceOutcome(
                connection: consumerConnection,
                grantID   : shortGrant.grant.id,
                requestID : UUID()
            )
        }
        clock.set(now)

        let expiredBeforeConsume = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([3]),
                deadline     : now.wall.addingTimeInterval(1)
            )
        )
        clock.set(RuntimeInstant(
            wall     : now.wall.addingTimeInterval(2),
            monotonic: now.monotonic + .seconds(2)
        ))
        await #expect(throws: AddonFailure.self) {
            try await runtime.pumpServiceInvocation(expiredBeforeConsume.id)
        }
        #expect(try await runtime.serviceOutcome(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            requestID : expiredBeforeConsume.invocation.requestID
        ) == .unsent)
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
        clock.set(now)

        let timedWork = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([3]),
                deadline     : now.wall.addingTimeInterval(5)
            )
        )
        await decisionAccess.armInvocation()
        async let timedPump = runtime.pumpServiceInvocation(timedWork.id)
        await decisionAccess.waitForArrival()
        clock.set(RuntimeInstant(
            wall     : now.wall.addingTimeInterval(6),
            monotonic: now.monotonic + .seconds(6)
        ))
        await decisionAccess.releaseGate()
        do {
            _ = try await timedPump
            Issue.record("An expired service decision was handed off after its suspended consume.")
        } catch is AddonFailure {}
        #expect(adapter.serviceDeliveryCount == 2)
        #expect(try await runtime.serviceOutcome(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            requestID : timedWork.invocation.requestID
        ) == .unsent)
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)

        let blockedWork = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([3]),
                deadline     : now.wall.addingTimeInterval(20)
            )
        )
        await decisionAccess.armInvocation()
        async let pumping = runtime.pumpServiceInvocation(blockedWork.id)
        await decisionAccess.waitForArrival()
        await runtime.disable(owner: consumer.manifest.id)
        await decisionAccess.releaseGate()
        do {
            _ = try await pumping
            Issue.record("A consumed service decision survived canonical disable.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .sessionRevoked)
        }
        #expect(adapter.serviceDeliveryCount == 2)
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
        await #expect(throws: AddonFailure.self) {
            try await runtime.serviceOutcome(
                connection: consumerConnection,
                grantID   : acquisition.grant.id,
                requestID : blockedWork.invocation.requestID
            )
        }

        await runtime.observeExit(consumerConnection.incarnation)
        try await runtime.enable(owner: consumer.manifest.id)
        let replacementConsumerLaunch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let replacementConsumerConnection = try await runtime.attach(
            launchID: replacementConsumerLaunch,
            offer   : offer
        )
        let replacementPermissionID = try await runtime.authorizeService(
            connection           : replacementConsumerConnection,
            requirementID        : "com.example.focus.sessions",
            scope                : scope,
            partition            : "account-a",
            crossPublisherConsent: true
        )
        let replacementAcquisition = try await runtime.acquireService(
            connection  : replacementConsumerConnection,
            permissionID: replacementPermissionID,
            lifetime    : .seconds(30)
        )
        if await governor.usage(.jobs, owner: provider.manifest.id) == 1 {
            _ = try await runtime.receiveSourceStartupCompletion(
                replacementAcquisition.sourceID,
                connection: providerConnection
            )
        }
        let handedOffWork = try await runtime.beginServiceInvocation(
            connection: replacementConsumerConnection,
            grantID   : replacementAcquisition.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([4]),
                deadline     : now.wall.addingTimeInterval(25)
            )
        )
        #expect(try await runtime.pumpServiceInvocation(handedOffWork.id))
        let unrelatedParkedRequest = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : leafPublicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : now.wall.addingTimeInterval(25),
            observedRevision: 1
        )
        await resourceAccess.armResize()
        async let unrelatedParkedAdmission = runtime.submitAction(unrelatedParkedRequest)
        await resourceAccess.waitForArrival()
        clock.set(RuntimeInstant(
            wall     : now.wall.addingTimeInterval(26),
            monotonic: now.monotonic + .seconds(26)
        ))
        await #expect(throws: AddonFailure.self) {
            _ = try await runtime.serviceDeadlines()
        }
        #expect(adapter.stopCount(incarnation: providerConnection.incarnation) == 1)
        clock.set(now)
        await runtime.disable(owner: consumer.manifest.id)
        await #expect(throws: AddonFailure.self) {
            try await runtime.receiveServiceCompletion(
                handedOffWork.id,
                connection: providerConnection,
                response  : response
            )
        }
        #expect(adapter.stopCount(incarnation: providerConnection.incarnation) == 1)
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 1)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 1)
        await resourceAccess.releaseGate()
        do {
            _ = try await unrelatedParkedAdmission
            Issue.record("Unrelated parked admission survived the disable authority transition.")
        } catch is AddonFailure {}
        await runtime.observeExit(providerConnection.incarnation)
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
    }

    @Test
    func coldActionStartsItsProviderAndAttachRepumpsTheQueuedCommand() async throws {
        let fixture = try ActionFixture()
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog: [fixture.context().installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor: governor,
            adapter : adapter,
            clock   : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        let publicationID = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launchID = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launchID,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let publication = try Publication(
            id         : publicationID,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications: [publication],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        await runtime.observeExit(connection.incarnation)
        let request = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(request)
        #expect(try await runtime.pumpReady() == false)
        #expect(await governor.usage(.commands, owner: fixture.owner) == 1)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
        let replacementStart = try #require(adapter.lastStart(owner: fixture.owner))
        #expect(adapter.startCount(owner: fixture.owner) == 2)
        let replacementConnection = try await runtime.attach(
            launchID: replacementStart.launchID,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 1)
        let delivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveActionCompletion(
            delivery,
            connection: replacementConnection,
            outcome   : .completed(payload: Data())
        ))
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
    }

    @Test
    func pendingServiceReceiptCannotSurviveConsumerDisable() async throws {
        let consumer = try installedFixture("consumer", publisher: "shared.publisher")
        let provider = try installedFixture("focus", publisher: "shared.publisher")
        let actionFixture = try ActionFixture()
        let leaf = try actionFixture.context().installed
        let governor = ResourceGovernor()
        let resourceAccess = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let now = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .seconds(10)
        )
        let runtime = try await AddonRuntime.make(
            catalog: [consumer, provider, leaf],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants: [
                    consumer.manifest.id: [],
                    provider.manifest.id: [],
                    leaf.manifest.id    : []
                ],
                explicitBindings: []
            ),
            governor      : governor,
            resourceAccess: resourceAccess,
            serviceDecisionFactory: { $0 },
            adapter: adapter,
            clock  : FixedRuntimeClock(instant: now)
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let consumerLaunch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let consumerConnection = try await runtime.attach(
            launchID: consumerLaunch,
            offer   : offer
        )
        let permissionID = try await runtime.authorizeService(
            connection           : consumerConnection,
            requirementID        : "com.example.focus.sessions",
            scope                : ServiceScope(
                featureID: "summary",
                operation: "read"
            ),
            partition            : "account-a",
            crossPublisherConsent: true
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : consumerConnection,
                permissionID: permissionID,
                lifetime    : .seconds(30)
            )
        }
        let providerStart = try #require(adapter.lastStart(owner: provider.manifest.id))
        let providerConnection = try await runtime.attach(
            launchID: providerStart.launchID,
            offer   : offer
        )
        let acquisition = try await runtime.acquireService(
            connection  : consumerConnection,
            permissionID: permissionID,
            lifetime    : .seconds(30)
        )
        if await governor.usage(.jobs, owner: provider.manifest.id) == 1 {
            #expect(try await runtime.receiveSourceStartupCompletion(
                acquisition.sourceID,
                connection: providerConnection
            ))
        }
        let work = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([1]),
                deadline     : now.wall.addingTimeInterval(20)
            )
        )
        #expect(try await runtime.pumpServiceInvocation(work.id))

        await resourceAccess.armResize()
        async let unrelatedAssignment = runtime.assignPublication(
            owner     : leaf.manifest.id,
            featureID : "controls",
            instanceID: UUID()
        )
        await resourceAccess.waitForArrival()
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : "com.example.focus.sessions",
            operation    : "read",
            payload      : Data([2])
        )
        let ingress = try #require(adapter.stageIngress(
            ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations  : [],
                completion  : .service(
                    requestID: work.invocation.requestID,
                    response : response
                ),
                checkpoint: nil
            ),
            incarnation: providerConnection.incarnation
        ))
        #expect(try await runtime.receivePublicationOutput(
            ingress,
            connection: providerConnection,
            sequence  : 1
        ) == .pendingServiceCompletion)
        await runtime.disable(owner: consumer.manifest.id)
        #expect(adapter.stopCount(incarnation: providerConnection.incarnation) == 1)
        await resourceAccess.releaseGate()
        do {
            _ = try await unrelatedAssignment
            Issue.record("The unrelated assignment survived the consumer authority transition.")
        } catch is AddonFailure {
        }
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 1)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 1)
        await #expect(throws: AddonFailure.self) {
            try await runtime.serviceOutcome(
                connection: consumerConnection,
                grantID   : acquisition.grant.id,
                requestID : work.invocation.requestID
            )
        }
        await runtime.observeExit(providerConnection.incarnation)
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
    }

    @Test
    func independentPendingServiceCompletionsKeepExactSequenceAuthority() async throws {
        let baseConsumer = try installedFixture("consumer", publisher: "shared.publisher")
        let secondServiceID = "com.example.focus-b.sessions"
        let consumerA = try replacing(
            baseConsumer,
            requires: baseConsumer.manifest.requires + [
                requirement(secondServiceID, ">=1.0.0 <2.0.0")
            ]
        )
        let baseProvider = try installedFixture("focus", publisher: "shared.publisher")
        let providerA = baseProvider
        let providerB = try replacing(
            baseProvider,
            id      : "com.example.runtime.focus-provider-b",
            provides: [ProvidedService(
                kind   : .service,
                id     : secondServiceID,
                version: "1.0.0"
            )]
        )
        let actionFixture = try ActionFixture()
        let actionAddon = try actionFixture.context().installed
        let governor = ResourceGovernor()
        let resourceAccess = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let decisionBox = RuntimeServiceDecisionAccessBox()
        let now = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .seconds(10)
        )
        let bindings = [
            ServiceBinding(
                requirementID  : "com.example.focus.sessions",
                consumer       : consumerA.manifest.id,
                provider       : providerA.manifest.id,
                providerIdentity: providerA.verifiedIdentity,
                contractVersion: SemanticVersion(1, 0, 0),
                digest          : providerA.digest,
                featureID       : "summary"
            ),
            ServiceBinding(
                requirementID  : secondServiceID,
                consumer       : consumerA.manifest.id,
                provider       : providerB.manifest.id,
                providerIdentity: providerB.verifiedIdentity,
                contractVersion: SemanticVersion(1, 0, 0),
                digest          : providerB.digest,
                featureID       : "summary"
            )
        ]
        let runtime = try await AddonRuntime.make(
            catalog: [consumerA, providerA, providerB, actionAddon],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants: [
                    consumerA.manifest.id: [],
                    providerA.manifest.id: [],
                    providerB.manifest.id: [],
                    actionAddon.manifest.id: []
                ],
                explicitBindings: bindings
            ),
            governor      : governor,
            resourceAccess: resourceAccess,
            serviceDecisionFactory: { broker in
                let access = GatedRuntimeServiceDecisionAccess(target: broker)
                decisionBox.access = access
                return access
            },
            adapter: adapter,
            clock  : FixedRuntimeClock(instant: now)
        )
        let decisionAccess = try #require(decisionBox.access)
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let providerPublicationID = try await runtime.assignPublication(
            owner     : providerA.manifest.id,
            featureID : "localTimer",
            instanceID: UUID()
        )
        let consumerALaunch = try await runtime.requestLaunch(owner: consumerA.manifest.id)
        let consumerAConnection = try await runtime.attach(
            launchID: consumerALaunch,
            offer   : offer
        )
        let scope = try ServiceScope(
            featureID: "summary",
            operation: "read"
        )
        let permissionA = try await runtime.authorizeService(
            connection           : consumerAConnection,
            requirementID        : "com.example.focus.sessions",
            scope                : scope,
            partition            : "account-a",
            crossPublisherConsent: true
        )
        let permissionB = try await runtime.authorizeService(
            connection           : consumerAConnection,
            requirementID        : secondServiceID,
            scope                : scope,
            partition            : "account-b",
            crossPublisherConsent: true
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : consumerAConnection,
                permissionID: permissionA,
                lifetime    : .seconds(30)
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : consumerAConnection,
                permissionID: permissionB,
                lifetime    : .seconds(30)
            )
        }
        let providerAStart = try #require(adapter.lastStart(owner: providerA.manifest.id))
        let providerBStart = try #require(adapter.lastStart(owner: providerB.manifest.id))
        let providerAConnection = try await runtime.attach(
            launchID: providerAStart.launchID,
            offer   : offer
        )
        let providerBConnection = try await runtime.attach(
            launchID: providerBStart.launchID,
            offer   : offer
        )
        let acquisitionA = try await runtime.acquireService(
            connection  : consumerAConnection,
            permissionID: permissionA,
            lifetime    : .seconds(30)
        )
        let acquisitionB = try await runtime.acquireService(
            connection  : consumerAConnection,
            permissionID: permissionB,
            lifetime    : .seconds(30)
        )
        for (acquisition, connection, owner) in [
            (acquisitionA, providerAConnection, providerA.manifest.id),
            (acquisitionB, providerBConnection, providerB.manifest.id)
        ] where await governor.usage(.jobs, owner: owner) == 1 {
            #expect(try await runtime.receiveSourceStartupCompletion(
                acquisition.sourceID,
                connection: connection
            ))
        }

        let invocationA = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : "com.example.focus.sessions",
            operation    : "read",
            payload      : Data([1]),
            deadline     : now.wall.addingTimeInterval(20)
        )
        let invocationB = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : secondServiceID,
            operation    : "read",
            payload      : Data([2]),
            deadline     : now.wall.addingTimeInterval(20)
        )
        let workA = try await runtime.beginServiceInvocation(
            connection: consumerAConnection,
            grantID   : acquisitionA.grant.id,
            invocation: invocationA
        )
        let workB = try await runtime.beginServiceInvocation(
            connection: consumerAConnection,
            grantID   : acquisitionB.grant.id,
            invocation: invocationB
        )
        #expect(try await runtime.pumpServiceInvocation(workA.id))
        #expect(try await runtime.pumpServiceInvocation(workB.id))
        let responseA = try ServiceResponse(
            schemaVersion: 1,
            contractID   : invocationA.contractID,
            operation    : invocationA.operation,
            payload      : Data([11])
        )
        let responseB = try ServiceResponse(
            schemaVersion: 1,
            contractID   : invocationB.contractID,
            operation    : invocationB.operation,
            payload      : Data([22])
        )
        let outputA = try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations  : [],
            completion  : .service(
                requestID: invocationA.requestID,
                response : responseA
            ),
            checkpoint: nil
        )
        let outputB = try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations  : [],
            completion  : .service(
                requestID: invocationB.requestID,
                response : responseB
            ),
            checkpoint: nil
        )
        let assignmentOwner = actionAddon.manifest.id
        await resourceAccess.armResize()
        async let unrelatedAssignment = runtime.assignPublication(
            owner     : assignmentOwner,
            featureID : "controls",
            instanceID: UUID()
        )
        await resourceAccess.waitForArrival()
        let ingressA = try #require(adapter.stageIngress(
            outputA,
            incarnation: providerAConnection.incarnation
        ))
        #expect(try await runtime.receivePublicationOutput(
            ingressA,
            connection: providerAConnection,
            sequence  : 1
        ) == .pendingServiceCompletion)
        await #expect(throws: AddonFailure.self) {
            try await runtime.receivePublicationOutput(
                ingressA,
                connection: providerAConnection,
                sequence  : 1
            )
        }
        #expect(adapter.stageIngress(
            outputA,
            incarnation: providerAConnection.incarnation
        ) == nil)
        let ingressB = try #require(adapter.stageIngress(
            outputB,
            incarnation: providerBConnection.incarnation
        ))
        #expect(try await runtime.receivePublicationOutput(
            ingressB,
            connection: providerBConnection,
            sequence  : 1
        ) == .pendingServiceCompletion)
        await resourceAccess.releaseGate()
        _ = try await unrelatedAssignment
        #expect(try await runtime.serviceOutcome(
            connection: consumerAConnection,
            grantID   : acquisitionA.grant.id,
            requestID : invocationA.requestID
        ) == .completed(responseA))
        #expect(try await runtime.serviceOutcome(
            connection: consumerAConnection,
            grantID   : acquisitionB.grant.id,
            requestID : invocationB.requestID
        ) == .completed(responseB))
        #expect(adapter.stopCount(incarnation: providerAConnection.incarnation) == 0)
        #expect(adapter.stopCount(incarnation: providerBConnection.incarnation) == 0)
        for connection in [providerAConnection, providerBConnection] {
            _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : ProviderOutput(
                    schemaVersion: 1,
                    publications: [],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : nil
                ),
                connection: connection,
                sequence  : 2
            )
        }

        let correlatedInvocationB = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : invocationB.contractID,
            operation    : invocationB.operation,
            payload      : Data([3]),
            deadline     : now.wall.addingTimeInterval(20)
        )
        let correlatedWorkB = try await runtime.beginServiceInvocation(
            connection: consumerAConnection,
            grantID   : acquisitionB.grant.id,
            invocation: correlatedInvocationB
        )
        #expect(try await runtime.pumpServiceInvocation(correlatedWorkB.id))
        let publication = try Publication(
            id         : providerPublicationID,
            revision   : 1,
            kind       : .widget,
            content    : actionFixture.presentation(),
            timeline   : nil,
            expiresAt  : now.wall.addingTimeInterval(60),
            stalePolicy: .remove
        )
        let publicationOutput = try ProviderOutput(
            schemaVersion: 1,
            publications: [publication],
            operations  : [],
            completion  : nil,
            checkpoint  : nil
        )
        let publicationIngress = try #require(adapter.stageIngress(
            publicationOutput,
            incarnation: providerAConnection.incarnation
        ))
        await resourceAccess.armResize()
        async let publicationMutation = runtime.receivePublicationOutput(
            publicationIngress,
            connection: providerAConnection,
            sequence  : 3
        )
        await resourceAccess.waitForArrival()
        let correlatedResponseB = try ServiceResponse(
            schemaVersion: 1,
            contractID   : correlatedInvocationB.contractID,
            operation    : correlatedInvocationB.operation,
            payload      : Data([33])
        )
        let correlatedOutputB = try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations  : [],
            completion  : .service(
                requestID: correlatedInvocationB.requestID,
                response : correlatedResponseB
            ),
            checkpoint: nil
        )
        let correlatedIngressB = try #require(adapter.stageIngress(
            correlatedOutputB,
            incarnation: providerBConnection.incarnation
        ))
        #expect(try await runtime.receivePublicationOutput(
            correlatedIngressB,
            connection: providerBConnection,
            sequence  : 3
        ) == .pendingServiceCompletion)
        await resourceAccess.releaseGate()
        _ = try await publicationMutation
        #expect(try await runtime.serviceOutcome(
            connection: consumerAConnection,
            grantID   : acquisitionB.grant.id,
            requestID : correlatedInvocationB.requestID
        ) == .completed(correlatedResponseB))
        #expect(adapter.stopCount(incarnation: providerBConnection.incarnation) == 0)

        let secondInvocationB = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : invocationB.contractID,
            operation    : invocationB.operation,
            payload      : Data([4]),
            deadline     : now.wall.addingTimeInterval(20)
        )
        let secondWorkB = try await runtime.beginServiceInvocation(
            connection: consumerAConnection,
            grantID   : acquisitionB.grant.id,
            invocation: secondInvocationB
        )
        #expect(try await runtime.pumpServiceInvocation(secondWorkB.id))
        await decisionAccess.armCompletionPreparation()
        async let directCompletion = runtime.receiveServiceCompletion(
            secondWorkB.id,
            connection: providerBConnection,
            response  : responseB
        )
        await decisionAccess.waitForArrival()
        await runtime.observeExit(providerBConnection.incarnation)
        await decisionAccess.releaseGate()
        do {
            _ = try await directCompletion
            Issue.record("Exact exit before broker acceptance was reported as an accepted direct result.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .sessionRevoked)
        }
        #expect(await governor.usage(.commands, owner: consumerA.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: providerB.manifest.id) == 0)
    }

    @Test
    func correlatedServiceCompletionCannotCommitAfterExactExitDuringBrokerReduction() async throws {
        let consumer = try installedFixture("consumer", publisher: "shared.publisher")
        let provider = try installedFixture("focus", publisher: "shared.publisher")
        let governor = ResourceGovernor()
        let resourceAccess = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let now = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .seconds(10)
        )
        let runtime = try await AddonRuntime.make(
            catalog: [consumer, provider],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants: [
                    consumer.manifest.id: [],
                    provider.manifest.id: []
                ],
                explicitBindings: []
            ),
            governor      : governor,
            resourceAccess: resourceAccess,
            serviceDecisionFactory: { $0 },
            adapter: adapter,
            clock  : FixedRuntimeClock(instant: now)
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let consumerLaunch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let consumerConnection = try await runtime.attach(
            launchID: consumerLaunch,
            offer   : offer
        )
        let permissionID = try await runtime.authorizeService(
            connection           : consumerConnection,
            requirementID        : "com.example.focus.sessions",
            scope                : ServiceScope(
                featureID: "summary",
                operation: "read"
            ),
            partition            : "account-a",
            crossPublisherConsent: true
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : consumerConnection,
                permissionID: permissionID,
                lifetime    : .seconds(30)
            )
        }
        let providerStart = try #require(adapter.lastStart(owner: provider.manifest.id))
        let providerConnection = try await runtime.attach(
            launchID: providerStart.launchID,
            offer   : offer
        )
        let acquisition = try await runtime.acquireService(
            connection  : consumerConnection,
            permissionID: permissionID,
            lifetime    : .seconds(30)
        )
        if await governor.usage(.jobs, owner: provider.manifest.id) == 1 {
            #expect(try await runtime.receiveSourceStartupCompletion(
                acquisition.sourceID,
                connection: providerConnection
            ))
        }
        let work = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([1]),
                deadline     : now.wall.addingTimeInterval(20)
            )
        )
        #expect(try await runtime.pumpServiceInvocation(work.id))
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : "com.example.focus.sessions",
            operation    : "read",
            payload      : Data([2])
        )
        let ingress = try #require(adapter.stageIngress(
            ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations  : [],
                completion  : .service(
                    requestID: work.invocation.requestID,
                    response : response
                ),
                checkpoint: nil
            ),
            incarnation: providerConnection.incarnation
        ))

        await resourceAccess.armReduction()
        async let completion = runtime.receivePublicationOutput(
            ingress,
            connection: providerConnection,
            sequence  : 1
        )
        await resourceAccess.waitForArrival()
        await runtime.observeExit(providerConnection.incarnation)
        await resourceAccess.releaseGate()
        do {
            _ = try await completion
            Issue.record("Exact provider exit during broker reduction advanced the correlated sequence.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .sessionRevoked)
        }
        #expect(await governor.usage(.commands, owner: consumer.manifest.id) == 0)
        #expect(await governor.usage(.jobs, owner: provider.manifest.id) == 0)
    }

    @Test
    func missingProviderPathRetainsStartedPrefixAndRefundsRejectedSuffix() async throws {
        let consumer = try installedFixture("consumer", publisher: "shared.publisher")
        let baseProvider = try installedFixture("focus", publisher: "shared.publisher")
        let leaf = try replacing(
            baseProvider,
            id      : "com.example.runtime.rejected-leaf",
            requires: [],
            provides: [ProvidedService(
                kind   : .service,
                id     : "com.example.runtime.rejected-dependency",
                version: "1.0.0"
            )]
        )
        let provider = try replacing(
            baseProvider,
            id      : "com.example.runtime.rejected-provider",
            requires: [requirement(
                "com.example.runtime.rejected-dependency",
                ">=1.0.0 <2.0.0"
            )]
        )
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter(
            rejectedStartOwners: [provider.manifest.id]
        )
        let now = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .seconds(10)
        )
        let runtime = try await AddonRuntime.make(
            catalog: [consumer, provider, leaf],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants: [
                    consumer.manifest.id: [],
                    provider.manifest.id: [],
                    leaf.manifest.id    : []
                ],
                explicitBindings: []
            ),
            governor: governor,
            adapter : adapter,
            clock   : FixedRuntimeClock(instant: now)
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let consumerLaunch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let consumerConnection = try await runtime.attach(
            launchID: consumerLaunch,
            offer   : offer
        )
        let scope = try ServiceScope(
            featureID: "summary",
            operation: "read"
        )
        let permissionID = try await runtime.authorizeService(
            connection           : consumerConnection,
            requirementID        : "com.example.focus.sessions",
            scope                : scope,
            partition            : "account-a",
            crossPublisherConsent: true
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : consumerConnection,
                permissionID: permissionID,
                lifetime    : .seconds(30)
            )
        }
        let leafStart = try #require(adapter.lastStart(owner: leaf.manifest.id))
        #expect(adapter.startOwners.suffix(2) == [
            leaf.manifest.id,
            provider.manifest.id
        ])
        #expect(await governor.usage(.providers, owner: leaf.manifest.id) == 1)
        #expect(await governor.usage(.providers, owner: provider.manifest.id) == 0)
        #expect(await runtime.diagnostics(owner: leaf.manifest.id)?.hasProcess == true)
        #expect(await runtime.diagnostics(owner: provider.manifest.id)?.hasProcess == false)
        await runtime.observeExit(leafStart.incarnation)
        #expect(await governor.usage(.providers, owner: leaf.manifest.id) == 0)
    }

    @Test
    func directConsumersReuseOneCanonicalProviderIncarnation() async throws {
        let first = try installedFixture("consumer", publisher: "shared.publisher")
        let second = try replacing(
            first,
            id: "com.example.runtime.second-consumer"
        )
        let provider = try installedFixture("focus", publisher: "provider.publisher")
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter()
        let now = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .seconds(10)
        )
        let runtime = try await AddonRuntime.make(
            catalog: [first, second, provider],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants: [
                    first.manifest.id   : [],
                    second.manifest.id  : [],
                    provider.manifest.id: []
                ],
                explicitBindings: [],
                serviceAccessGrants: [
                    ServiceAccessGrant(
                        consumer        : first.manifest.id,
                        requirementID   : "com.example.focus.sessions",
                        providerIdentity: provider.verifiedIdentity
                    ),
                    ServiceAccessGrant(
                        consumer        : second.manifest.id,
                        requirementID   : "com.example.focus.sessions",
                        providerIdentity: provider.verifiedIdentity
                    )
                ]
            ),
            governor: governor,
            adapter : adapter,
            clock   : FixedRuntimeClock(instant: now)
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let firstLaunch = try await runtime.requestLaunch(owner: first.manifest.id)
        let firstConnection = try await runtime.attach(
            launchID: firstLaunch,
            offer   : offer
        )
        let secondLaunch = try await runtime.requestLaunch(owner: second.manifest.id)
        let secondConnection = try await runtime.attach(
            launchID: secondLaunch,
            offer   : offer
        )
        let scope = try ServiceScope(
            featureID: "summary",
            operation: "read"
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.authorizeService(
                connection           : firstConnection,
                requirementID        : "com.example.focus.sessions",
                scope                : scope,
                partition            : "shared",
                crossPublisherConsent: false
            )
        }
        let firstPermission = try await runtime.authorizeService(
            connection           : firstConnection,
            requirementID        : "com.example.focus.sessions",
            scope                : scope,
            partition            : "shared",
            crossPublisherConsent: true
        )
        let secondPermission = try await runtime.authorizeService(
            connection           : secondConnection,
            requirementID        : "com.example.focus.sessions",
            scope                : scope,
            partition            : "shared",
            crossPublisherConsent: true
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : firstConnection,
                permissionID: firstPermission,
                lifetime    : .seconds(30)
            )
        }
        let providerStart = try #require(adapter.lastStart(owner: provider.manifest.id))
        let providerConnection = try await runtime.attach(
            launchID: providerStart.launchID,
            offer   : offer
        )
        let firstAcquisition = try await runtime.acquireService(
            connection  : firstConnection,
            permissionID: firstPermission,
            lifetime    : .seconds(30)
        )
        #expect(try await runtime.receiveSourceStartupCompletion(
            firstAcquisition.sourceID,
            connection: providerConnection
        ))
        let secondAcquisition = try await runtime.acquireService(
            connection  : secondConnection,
            permissionID: secondPermission,
            lifetime    : .seconds(30)
        )
        #expect(secondAcquisition.sourceID == firstAcquisition.sourceID)
        #expect(adapter.startCount(owner: provider.manifest.id) == 1)
        #expect(await governor.usage(.providers, owner: provider.manifest.id) == 1)
        await runtime.observeExit(providerConnection.incarnation)
        #expect(try await !runtime.receiveSourceStartupCompletion(
            firstAcquisition.sourceID,
            connection: providerConnection
        ))
        await #expect(throws: AddonFailure.self) {
            try await runtime.beginServiceInvocation(
                connection: firstConnection,
                grantID   : firstAcquisition.grant.id,
                invocation: ServiceInvocation(
                    schemaVersion: 1,
                    requestID    : UUID(),
                    contractID   : "com.example.focus.sessions",
                    operation    : "read",
                    payload      : Data(),
                    deadline     : now.wall.addingTimeInterval(20)
                )
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : firstConnection,
                permissionID: firstPermission,
                lifetime    : .seconds(30)
            )
        }
        let replacementStart = try #require(adapter.lastStart(owner: provider.manifest.id))
        #expect(adapter.startCount(owner: provider.manifest.id) == 2)
        let replacementConnection = try await runtime.attach(
            launchID: replacementStart.launchID,
            offer   : offer
        )
        let replacementAcquisition = try await runtime.acquireService(
            connection  : firstConnection,
            permissionID: firstPermission,
            lifetime    : .seconds(30)
        )
        #expect(replacementAcquisition.sourceID == firstAcquisition.sourceID)
        #expect(replacementAcquisition.decisions == [.startSource(firstAcquisition.sourceID)])
        #expect(adapter.sourceDeliveryCount == 2)
        #expect(try await runtime.receiveSourceStartupCompletion(
            replacementAcquisition.sourceID,
            connection: replacementConnection
        ))
        await runtime.observeExit(providerConnection.incarnation)
        #expect(await governor.usage(.providers, owner: provider.manifest.id) == 1)
    }

    @Test
    func disableDuringCompletedPoolGrowthCannotCommitOrKeepTheGrowth() async throws {
        let fixture   = try ActionFixture()
        let installed = try fixture.context().installed
        let governor  = ResourceGovernor()
        let access    = GatedRuntimeResourceAccess(target: governor)
        let runtime = try await AddonRuntime.make(
            catalog: [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor             : governor,
            resourceAccess       : access,
            serviceDecisionFactory: { $0 },
            adapter              : RecordingRuntimeAdapter(),
            clock                : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        await access.armResize()
        async let assignment = runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        await access.waitForArrival()
        await runtime.disable(owner: fixture.owner)
        await access.releaseGate()
        do {
            _ = try await assignment
            Issue.record("Disabled authority committed a suspended assignment.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .sessionRevoked)
        }
        // Each installed owner now prepays 4 KiB for bounded CPU attribution.
        // The suspended assignment still leaves only the established 1 KiB
        // governor accounting difference, with no publication growth retained.
        #expect(await runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == 217_600)
        #expect(await governor.usage(.retainedStateBytes, owner: fixture.owner) == 218_624)

        let stopGovernor = ResourceGovernor()
        let stopAccess = GatedRuntimeResourceAccess(target: stopGovernor)
        let stopRuntime = try await AddonRuntime.make(
            catalog: [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor             : stopGovernor,
            resourceAccess       : stopAccess,
            serviceDecisionFactory: { $0 },
            adapter              : RecordingRuntimeAdapter(),
            clock                : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        await stopAccess.armResize()
        async let stoppedAssignment = stopRuntime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        await stopAccess.waitForArrival()
        await stopRuntime.stop()
        await stopAccess.releaseGate()
        do {
            _ = try await stoppedAssignment
            Issue.record("Stopped authority committed a suspended assignment.")
        } catch is AddonFailure {}
        #expect(await stopRuntime.diagnostics(owner: fixture.owner)?.reservedStateBytes == 217_600)
        await #expect(throws: AddonFailure.self) {
            try await stopRuntime.requestLaunch(owner: fixture.owner)
        }
    }

    @Test
    func expiredPreparedPublicationCannotCommitOrAdvanceSequence() async throws {
        let fixture = try ActionFixture()
        let installed = try fixture.context().installed
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let clock = MutableRuntimeClock(instant: RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        ))
        let runtime = try await AddonRuntime.make(
            catalog: [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor             : governor,
            resourceAccess       : access,
            serviceDecisionFactory: { $0 },
            adapter              : adapter,
            clock                : clock
        )
        let id = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer: ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let expiring = try Publication(
            id         : id,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(1),
            stalePolicy: .remove
        )
        await access.armResize()
        async let admission = receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications: [expiring],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        await access.waitForArrival()
        clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(2),
            monotonic: .seconds(2)
        ))
        await access.releaseGate()
        do {
            _ = try await admission
            Issue.record("An expired prepared publication committed after suspended growth.")
        } catch is AddonFailure {}
        #expect(await runtime.snapshot(at: fixture.wall).publications.isEmpty)
        clock.set(RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        ))
        let replacement = try Publication(
            id         : id,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [replacement],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        #expect(await runtime.snapshot(at: fixture.wall).publications == [replacement])
        let largerContent = try PresentationSet(
            widget: try ContentDocument(
                root              : try .text(String(repeating: "x", count: 4_096)),
                privacy           : .publicContent,
                accessibilityLabel: "Large"
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
        let laterReplacement = try Publication(
            id         : id,
            revision   : 2,
            kind       : .widget,
            content    : largerContent,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(200),
            stalePolicy: .remove
        )
        await access.armResize()
        async let replacingExpiredPrevious = receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications: [laterReplacement],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 2
        )
        await access.waitForArrival()
        clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(101),
            monotonic: .seconds(101)
        ))
        await access.releaseGate()
        do {
            _ = try await replacingExpiredPrevious
            Issue.record("A replacement revived prior publication content that expired during growth.")
        } catch is AddonFailure {}
        #expect(await runtime.snapshot(at: fixture.wall).publications == [replacement])
    }

    @Test
    func sameSizeReplacementCommitsAfterScratchWasAdmittedAtFullStateQuota() async throws {
        let fixture = try ActionFixture()
        let installed = try fixture.context().installed
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog: [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor             : governor,
            resourceAccess       : access,
            serviceDecisionFactory: { $0 },
            adapter              : adapter,
            clock                : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        let id = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let secondID = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer: ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        func publication(revision: UInt64) throws -> Publication {
            try Publication(
                id         : id,
                revision   : revision,
                kind       : .widget,
                content    : fixture.presentation(),
                timeline   : nil,
                expiresAt  : fixture.wall.addingTimeInterval(100),
                stalePolicy: .remove
            )
        }
        let first = try publication(revision: 1)
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [first],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        await access.armTemporaryMemory()
        let replacement = try publication(revision: 2)
        async let replacing = receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications: [replacement],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 2
        )
        await access.waitForArrival()
        let used = await governor.usage(.retainedStateBytes)
        let fillerOwner = AddonID(rawValue: "com.example.replacement-filler")!
        let filler = try await governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - used - 1_024),
            owner: fillerOwner
        )
        #expect(await governor.usage(.retainedStateBytes) == 8 * 1_024 * 1_024)
        await access.releaseGate()
        _ = try await replacing
        #expect(await runtime.snapshot(at: fixture.wall).publications == [replacement])
        let largerContent = try PresentationSet(
            widget: try ContentDocument(
                root              : try .text(String(repeating: "x", count: 4_096)),
                privacy           : .publicContent,
                accessibilityLabel: "Large"
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
        let larger = try Publication(
            id         : id,
            revision   : 3,
            kind       : .widget,
            content    : largerContent,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        await #expect(throws: AddonFailure.self) {
            try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
                ProviderOutput(
                    schemaVersion: 1,
                    publications: [larger],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : nil
                ),
                connection: connection,
                sequence  : 3
            )
        }
        let secondPublication = try Publication(
            id         : secondID,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        await #expect(throws: AddonFailure.self) {
            try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
                ProviderOutput(
                    schemaVersion: 1,
                    publications: [secondPublication],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : nil
                ),
                connection: connection,
                sequence  : 3
            )
        }
        #expect(await runtime.snapshot(at: fixture.wall).publications == [replacement])
        try await governor.release(
            filler.id,
            owner: fillerOwner
        )
    }

    @Test
    func submittingForOneOwnerRefundsOnlyExpiredHistoryForAnotherOwner() async throws {
        let fixture = try ActionFixture()
        let first = try fixture.context().installed
        let second = try replacing(
            first,
            id: "com.example.runtime.second-action-owner"
        )
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter()
        let clock = MutableRuntimeClock(instant: RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        ))
        let runtime = try await AddonRuntime.make(
            catalog: [first, second],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants: [
                    first.manifest.id : [],
                    second.manifest.id: []
                ],
                explicitBindings: []
            ),
            governor: governor,
            adapter : adapter,
            clock   : clock
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let firstID = try await runtime.assignPublication(
            owner     : first.manifest.id,
            featureID : "controls",
            instanceID: UUID()
        )
        let secondID = try await runtime.assignPublication(
            owner     : second.manifest.id,
            featureID : "controls",
            instanceID: UUID()
        )
        let firstLaunch = try await runtime.requestLaunch(owner: first.manifest.id)
        let firstConnection = try await runtime.attach(
            launchID: firstLaunch,
            offer   : offer
        )
        let secondLaunch = try await runtime.requestLaunch(owner: second.manifest.id)
        let secondConnection = try await runtime.attach(
            launchID: secondLaunch,
            offer   : offer
        )
        for (id, connection) in [(firstID, firstConnection), (secondID, secondConnection)] {
            _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
                ProviderOutput(
                    schemaVersion: 1,
                    publications: [Publication(
                        id         : id,
                        revision   : 1,
                        kind       : .widget,
                        content    : fixture.presentation(),
                        timeline   : nil,
                        expiresAt  : fixture.wall.addingTimeInterval(1_000),
                        stalePolicy: .remove
                    )],
                    operations  : [],
                    completion  : nil,
                    checkpoint  : nil
                ),
                connection: connection,
                sequence  : 1
            )
        }
        let firstRequest = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : firstID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(firstRequest)
        #expect(try await runtime.pumpReady())
        let delivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveActionCompletion(
            delivery,
            connection: firstConnection,
            outcome   : .completed(payload: Data([9]))
        ))
        let firstBefore = try #require(await runtime.diagnostics(owner: first.manifest.id))
        let secondBefore = try #require(await runtime.diagnostics(owner: second.manifest.id))
        clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(601),
            monotonic: .seconds(601)
        ))
        let secondRequest = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : secondID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(620),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(secondRequest)
        let firstAfter = try #require(await runtime.diagnostics(owner: first.manifest.id))
        let secondAfter = try #require(await runtime.diagnostics(owner: second.manifest.id))
        #expect(firstBefore.reservedStateBytes - firstAfter.reservedStateBytes == 24_578)
        #expect(secondAfter.reservedStateBytes > secondBefore.reservedStateBytes)
        #expect(await runtime.actionState(
            firstRequest.requestID,
            owner: first.manifest.id
        ) == nil)
        #expect(await governor.usage(.providers, owner: first.manifest.id) == 1)
        #expect(await governor.usage(.providers, owner: second.manifest.id) == 1)
    }

    @Test
    func completionDuringPoolGrowthDefersResizeAndReconcilesCurrentCharges() async throws {
        let fixture = try ActionFixture()
        let installed = try fixture.context().installed
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog: [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor             : governor,
            resourceAccess       : access,
            serviceDecisionFactory: { $0 },
            adapter              : adapter,
            clock                : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        let id = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer: ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let first = try Publication(
            id         : id,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [first],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        let request = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : id,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(request)
        #expect(try await runtime.pumpReady())
        let delivery = try #require(adapter.lastAction)
        let largerContent = try PresentationSet(
            widget: try ContentDocument(
                root              : try .text(String(repeating: "x", count: 4_096)),
                privacy           : .publicContent,
                accessibilityLabel: "Large"
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
        let second = try Publication(
            id         : id,
            revision   : 2,
            kind       : .widget,
            content    : largerContent,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        await access.armResize()
        async let publishing = receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications: [second],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 2
        )
        await access.waitForArrival()
        #expect(try await runtime.receiveActionCompletion(
            delivery,
            connection: connection,
            outcome   : .completed(payload: Data([9]))
        ))
        #expect(await governor.usage(.commands, owner: fixture.owner) == 1)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 1)
        await access.releaseGate()
        _ = try await publishing
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
        #expect(await runtime.snapshot(at: fixture.wall).publications == [second])
        let diagnostics = try #require(await runtime.diagnostics(owner: fixture.owner))
        #expect(diagnostics.reservedStateBytes < 1_000_000)
        let actionable = try Publication(
            id         : id,
            revision   : 3,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [actionable],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 3
        )
        let idleCompletionRequest = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : id,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 3
        )
        _ = try await runtime.submitAction(idleCompletionRequest)
        #expect(try await runtime.pumpReady())
        let idleCompletionDelivery = try #require(adapter.lastAction)
        await access.armReduction()
        async let idleCompletion = runtime.receiveActionCompletion(
            idleCompletionDelivery,
            connection: connection,
            outcome   : .completed(payload: Data())
        )
        await access.waitForArrival()
        let overtakingRequest = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : id,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 3
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.submitAction(overtakingRequest)
        }
        #expect(await runtime.actionState(
            overtakingRequest.requestID,
            owner: fixture.owner
        ) == nil)
        await access.releaseGate()
        #expect(try await idleCompletion)
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
        let queuedAcrossExit = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : id,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 3
        )
        _ = try await runtime.submitAction(queuedAcrossExit)
        await access.armJobAdmission()
        async let pumpingAcrossExit = runtime.pumpReady()
        await access.waitForArrival()
        await runtime.observeExit(connection.incarnation)
        await access.releaseGate()
        do {
            _ = try await pumpingAcrossExit
            Issue.record("An action was handed to an incarnation that exited during job admission.")
        } catch is AddonFailure {}
        #expect(await runtime.actionState(
            queuedAcrossExit.requestID,
            owner: fixture.owner
        ) == .queued)
        #expect(await governor.usage(.commands, owner: fixture.owner) == 1)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
    }

    @Test
    func acknowledgmentFreesAdapterPayloadWhileProviderJobRemains() async throws {
        let fixture = try ActionFixture()
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog: [fixture.context().installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor: governor,
            adapter : adapter,
            clock   : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        let id = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let publication = try Publication(
            id         : id,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [publication],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        let first = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : id,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(first)
        #expect(try await runtime.pumpReady())
        let delivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveAcknowledgment(
            delivery,
            connection: connection
        ))
        #expect(adapter.lastAction == nil)
        let second = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : id,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(second)
        #expect(try await runtime.pumpReady() == false)
        let commandsAfterRejection = await governor.usage(.commands, owner: fixture.owner)
        let jobsAfterRejection = await governor.usage(.jobs, owner: fixture.owner)
        #expect(commandsAfterRejection == 2)
        #expect(jobsAfterRejection == 1)
        #expect(try await runtime.receiveActionCompletion(
            delivery,
            connection: connection,
            outcome   : .completed(payload: Data([9]))
        ))
        let commandsAfterCompletion = await governor.usage(.commands, owner: fixture.owner)
        let jobsAfterCompletion = await governor.usage(.jobs, owner: fixture.owner)
        #expect(commandsAfterCompletion == 1)
        #expect(jobsAfterCompletion == 0)
        #expect(try await runtime.pumpReady())
        let secondDelivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveActionCompletion(
            secondDelivery,
            connection: connection,
            outcome   : .completed(payload: Data([9]))
        ))
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
    }

    @Test
    func ingressCapacityIsPaidAndTransferOccupiesSlotUntilFinish() async throws {
        let fixture = try ActionFixture()
        let adapter = RecordingRuntimeAdapter()
        let governor = ResourceGovernor()
        let resourceAccess = GatedRuntimeResourceAccess(target: governor)
        let runtime = try await AddonRuntime.make(
            catalog: [fixture.context().installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor      : governor,
            resourceAccess: resourceAccess,
            serviceDecisionFactory: { $0 },
            adapter       : adapter,
            clock         : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            )),
            maximumEnvelopeBytes: 8 * 1_024
        )
        let publicationID = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let oversized = try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations  : [],
            completion  : nil,
            checkpoint  : Data(repeating: 7, count: 16 * 1_024)
        )
        #expect(adapter.stageIngress(
            oversized,
            incarnation: connection.incarnation
        ) == nil)
        let publication = try Publication(
            id         : publicationID,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(60),
            stalePolicy: .remove
        )
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications: [publication],
            operations  : [],
            completion  : nil,
            checkpoint  : nil
        )
        let first = try #require(adapter.stageIngress(
            output,
            incarnation: connection.incarnation
        ))
        await resourceAccess.armResize()
        async let receiving = runtime.receivePublicationOutput(
            first,
            connection: connection,
            sequence  : 1
        )
        await resourceAccess.waitForArrival()
        await #expect(throws: AddonFailure.self) {
            try await runtime.receivePublicationOutput(
                first,
                connection: connection,
                sequence  : 1
            )
        }
        #expect(adapter.stageIngress(
            output,
            incarnation: connection.incarnation
        ) == nil)
        await resourceAccess.releaseGate()
        let result = try await receiving
        guard case .committed(let admission) = result else {
            Issue.record("Expected the empty publication output to commit after the ingress gate.")
            return
        }
        #expect(admission.operations.isEmpty)
        #expect(admission.completion == nil)
        #expect(admission.checkpoint == nil)
        let retry = try #require(adapter.stageIngress(
            output,
            incarnation: connection.incarnation
        ))
        adapter.rejectIngress(
            retry,
            incarnation: connection.incarnation
        )
        await runtime.observeExit(connection.incarnation)
        #expect(adapter.stageIngress(
            output,
            incarnation: connection.incarnation
        ) == nil)
    }

    @Test
    func wallJumpExpiresPublicationWithoutExpiringMonotonicAction() async throws {
        let fixture  = try ActionFixture()
        let governor = ResourceGovernor()
        let adapter  = RecordingRuntimeAdapter()
        let clock    = MutableRuntimeClock(instant: RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        ))
        let runtime = try await AddonRuntime.make(
            catalog: [fixture.context().installed],
            environment: HostEnvironment(
                osVersion         : SemanticVersion(14, 0, 0),
                hostCapabilities  : [:],
                applications      : [:],
                grants            : [fixture.owner: []],
                explicitBindings  : []
            ),
            governor: governor,
            adapter : adapter,
            clock   : clock
        )
        let publicationID = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let publication = try Publication(
            id         : publicationID,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(10),
            stalePolicy: .remove
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [publication],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        let request = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(request)
        #expect(try await runtime.pumpReady())
        let delivery = try #require(adapter.lastAction)

        clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(1_000),
            monotonic: .seconds(5)
        ))
        let wallOnlyDelay = try await runtime.serviceDeadlines()
        #expect(try #require(wallOnlyDelay) > .zero)
        #expect(await runtime.snapshot(at: clock.now().wall).publications.isEmpty)
        #expect(await runtime.actionState(
            request.requestID,
            owner: fixture.owner
        ) == .sent(delivery.generation))
        #expect(adapter.stopCount(incarnation: connection.incarnation) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 1)

        clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(1_000),
            monotonic: .seconds(25)
        ))
        let terminalDelay = try await runtime.serviceDeadlines()
        #expect(try #require(terminalDelay) > .zero)
        #expect(await runtime.actionState(
            request.requestID,
            owner: fixture.owner
        ) == .finished(.outcomeUnknown))
        #expect(adapter.stopCount(incarnation: connection.incarnation) == 1)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 1)
        let repeatedDelay = try await runtime.serviceDeadlines()
        #expect(try #require(repeatedDelay) > .zero)
        #expect(adapter.stopCount(incarnation: connection.incarnation) == 1)
        await runtime.observeExit(connection.incarnation)
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
        #expect(await governor.usage(.providers, owner: fixture.owner) == 0)
    }

    @Test
    func deadlineProjectionRejectsAStoppedRuntimeAfterBrokerSuspension() async throws {
        let fixture = try ActionFixture()
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter()
        let decisionBox = RuntimeServiceDecisionAccessBox()
        let instant = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .seconds(4)
        )
        let runtime = try await AddonRuntime.make(
            catalog: [fixture.context().installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor      : governor,
            resourceAccess: governor,
            serviceDecisionFactory: { broker in
                let access = GatedRuntimeServiceDecisionAccess(target: broker)
                decisionBox.access = access
                return access
            },
            adapter: adapter,
            clock  : FixedRuntimeClock(instant: instant)
        )
        let access = try #require(decisionBox.access)
        await access.armDeadline()
        async let projected = runtime.nextDelay(at: instant)
        await access.waitForArrival()
        await runtime.stop()
        await access.releaseGate()
        do {
            _ = try await projected
            Issue.record("Expected the stopped runtime to reject the parked projection.")
        } catch is AddonFailure {
        } catch {
            Issue.record("Expected AddonFailure, received \(error).")
        }
        #expect(try await runtime.nextDelay(at: instant) == nil)
    }

    @Test
    func exactCompletedActionRecoversAfterEndPublicationAtFullStateQuota() async throws {
        let fixture  = try ActionFixture()
        let governor = ResourceGovernor()
        let adapter  = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog: [fixture.context().installed],
            environment: HostEnvironment(
                osVersion         : SemanticVersion(14, 0, 0),
                hostCapabilities  : [:],
                applications      : [:],
                grants            : [fixture.owner: []],
                explicitBindings  : []
            ),
            governor: governor,
            adapter : adapter,
            clock   : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
        )
        let publicationID = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: fixture.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let publication = try Publication(
            id         : publicationID,
            revision   : 1,
            kind       : .widget,
            content    : fixture.presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [publication],
                operations  : [],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 1
        )
        let request = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(request)
        #expect(try await runtime.pumpReady())
        let delivery = try #require(adapter.lastAction)
        let outcome = ActionOutcome.completed(payload: Data([42]))
        #expect(try await runtime.receiveActionCompletion(
            delivery,
            connection: connection,
            outcome   : outcome
        ))
        _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : 
            ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations  : [.endPublication(publicationID)],
                completion  : nil,
                checkpoint  : nil
            ),
            connection: connection,
            sequence  : 2
        )
        #expect(await runtime.snapshot(at: fixture.wall).publications.isEmpty)

        let used = await governor.usage(.retainedStateBytes)
        let fillerOwner = AddonID(rawValue: "com.example.runtime-end-filler")!
        let filler = try await governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - used - 1_024),
            owner: fillerOwner
        )
        #expect(await governor.usage(.retainedStateBytes) == 8 * 1_024 * 1_024)
        #expect(try await runtime.submitAction(request) == .duplicate(.finished(outcome)))
        #expect(await governor.usage(.commands, owner: fixture.owner) == 0)
        #expect(await governor.usage(.jobs, owner: fixture.owner) == 0)
        try await governor.release(
            filler.id,
            owner: fillerOwner
        )
    }
}

func receivePublicationOutput(
    runtime   : AddonRuntime,
    adapter   : RecordingRuntimeAdapter,
    output    : ProviderOutput,
    connection: RuntimeConnection,
    sequence  : UInt64
) async throws -> PublicationAdmission {
    guard let ingress = adapter.stageIngress(
        output,
        incarnation: connection.incarnation
    ) else {
        throw AddonFailure(
            code  : .resourceDenied,
            reason: "The bounded test ingress slot rejected the provider output."
        )
    }
    let result = try await runtime.receivePublicationOutput(
        ingress,
        connection: connection,
        sequence  : sequence
    )
    guard case .committed(let admission) = result else {
        throw AddonFailure(
            code  : .resourceDenied,
            reason: "The service completion is pending canonical broker acceptance."
        )
    }
    return admission
}
