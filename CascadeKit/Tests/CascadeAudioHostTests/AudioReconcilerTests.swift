//
//  AudioReconcilerTests.swift
//  CascadeKit
//

import CascadeAudioHost
import CascadeContracts
import Foundation
import Testing

@Suite
struct AudioReconcilerTests {

    private static let builtIn = "built-in"
    private static let usb     = "usb"

    private let chrome: AudioAppIdentity

    init() throws {
        chrome = try AudioAppIdentity(bundleID: "com.google.Chrome")
    }

    // MARK: - Fixtures

    private func intent(
        gain    : Double   = 0.25,
        muted   : Bool     = false,
        outputs : [String] = []
    ) throws -> AudioAppIntent {
        try AudioAppIntent(gain: gain, isMuted: muted, outputUIDs: outputs)
    }

    private func configuration(
        _ objectIDs : [UInt32],
        _ outputs   : [String],
        streamTap   : Bool? = nil
    ) -> AudioPipelineConfiguration {
        AudioPipelineConfiguration(
            processObjectIDs : objectIDs,
            outputUIDs       : outputs,
            streamTap        : streamTap ?? (outputs.count == 1)
        )
    }

    private func processes(_ objectIDs: [UInt32], running: Bool = true) -> [AudioProcessRecord] {
        objectIDs.map { objectID in
            AudioProcessRecord(
                objectID        : objectID,
                pid             : Int32(objectID),
                bundleID        : "com.google.Chrome",
                executablePath  : nil,
                isRunningOutput : running
            )
        }
    }

    private func reconcile(
        _ reconciler : inout AudioReconciler,
        intent       : AudioAppIntent,
        objectIDs    : [UInt32]    = [10],
        outputs      : Set<String> = [AudioReconcilerTests.builtIn, AudioReconcilerTests.usb],
        system       : String?     = AudioReconcilerTests.builtIn,
        now          : Duration    = .zero
    ) -> [AudioReconcileAction] {
        reconciler.reconcile(
            intents         : [chrome: intent],
            apps            : objectIDs.isEmpty ? [:] : [chrome: processes(objectIDs)],
            outputs         : outputs,
            systemOutputUID : system,
            now             : now
        )
    }

    /// Builds the pipeline for `intent` and reports success, leaving `reconciler` running token 1.
    private func runningReconciler(
        intent    : AudioAppIntent,
        objectIDs : [UInt32] = [10]
    ) -> AudioReconciler {
        var reconciler = AudioReconciler()
        _ = reconcile(&reconciler, intent: intent, objectIDs: objectIDs)
        _ = reconciler.built(chrome, token: 1, succeeded: true, now: .zero)
        return reconciler
    }

    // MARK: - Brief

    @Test
    func neutralFollowingSystemNeedsNoPipeline() throws {
        var reconciler = AudioReconciler()

        #expect(reconcile(&reconciler, intent: .neutral) == [])
        #expect(reconciler.state(of: chrome) == .none)
        #expect(reconciler.enforcement(of: chrome, now: .zero) == .native)

        var running = runningReconciler(intent: try intent())

        #expect(reconcile(&running, intent: .neutral) == [.teardown(chrome, token: 1)])
        #expect(running.state(of: chrome) == .none)
        #expect(running.enforcement(of: chrome, now: .zero) == .native)
    }

    @Test
    func quarterGainBuildsOnePipeline() throws {
        var reconciler = AudioReconciler()
        let quarter    = try intent()

        let actions = reconcile(&reconciler, intent: quarter)

        let expected = configuration([10], [Self.builtIn])

        #expect(actions == [.build(chrome, token: 1, expected, quarter)])
        #expect(reconciler.state(of: chrome) == .building(token: 1, expected))
        #expect(reconcile(&reconciler, intent: quarter) == [])
    }

    @Test
    func gainChangeOnRunningPipelineUpdatesCommandOnly() throws {
        var reconciler = runningReconciler(intent: try intent())
        let louder     = try intent(gain: 0.5)

        #expect(reconcile(&reconciler, intent: louder) == [.updateCommand(chrome, token: 1, louder)])
        #expect(reconciler.state(of: chrome) == .running(token: 1, configuration([10], [Self.builtIn])))
        #expect(reconcile(&reconciler, intent: louder) == [])
    }

    @Test
    func outputChangeCrossfades() throws {
        var reconciler = runningReconciler(intent: try intent(outputs: [Self.builtIn]))
        let toUSB      = try intent(outputs: [Self.usb])

        let actions = reconcile(&reconciler, intent: toUSB)

        let target = configuration([10], [Self.usb])

        #expect(actions == [.crossfade(chrome, from: 1, to: 2, target, toUSB)])
        #expect(reconciler.state(of: chrome) == .crossfading(from: 1, to: 2, target))

        // The caller tears the old pipeline down itself once the new one runs.
        #expect(reconciler.built(chrome, token: 2, succeeded: true, now: .zero) == [])
        #expect(reconciler.state(of: chrome) == .running(token: 2, target))
        #expect(reconcile(&reconciler, intent: toUSB) == [])
    }

    @Test
    func outputGoneSwitchesDirectly() throws {
        let preferred  = try intent(outputs: [Self.usb, Self.builtIn])
        var reconciler = runningReconciler(intent: preferred)

        #expect(reconciler.state(of: chrome) == .running(token: 1, configuration([10], [Self.usb, Self.builtIn])))

        let actions = reconcile(&reconciler, intent: preferred, outputs: [Self.builtIn])

        #expect(actions == [
            .teardown(chrome, token: 1),
            .build(chrome, token: 2, configuration([10], [Self.builtIn]), preferred),
        ])
    }

    @Test
    func obsoleteBuildIsDiscarded() throws {
        var reconciler = AudioReconciler()
        let first      = try intent(outputs: [Self.builtIn])
        let second     = try intent(outputs: [Self.usb])

        _ = reconcile(&reconciler, intent: first)

        let actions = reconcile(&reconciler, intent: second)

        let target = configuration([10], [Self.usb])

        #expect(actions == [
            .teardown(chrome, token: 1),
            .build(chrome, token: 2, target, second),
        ])
        #expect(reconciler.built(chrome, token: 1, succeeded: true, now: .zero) == [])
        #expect(reconciler.state(of: chrome) == .building(token: 2, target))
    }

    @Test
    func missingPreferredOutputFallsBackToSystemAndKeepsPreference() throws {
        var reconciler = AudioReconciler()
        let preferred  = try intent(outputs: [Self.usb])

        let actions = reconcile(&reconciler, intent: preferred, outputs: [Self.builtIn])

        #expect(actions == [.build(chrome, token: 1, configuration([10], [Self.builtIn]), preferred)])

        _ = reconciler.built(chrome, token: 1, succeeded: true, now: .zero)

        // The device comes back: the unchanged intent is honoured again, with a crossfade.
        let returned = reconcile(&reconciler, intent: preferred)

        #expect(returned == [
            .crossfade(chrome, from: 1, to: 2, configuration([10], [Self.usb]), preferred),
        ])
    }

    @Test
    func wakeRebuildsEvenWithIdenticalIDs() throws {
        let quarter    = try intent()
        var reconciler = runningReconciler(intent: quarter)

        let actions = reconciler.environmentInvalidated(now: .seconds(5))

        #expect(actions == [
            .teardown(chrome, token: 1),
            .build(chrome, token: 2, configuration([10], [Self.builtIn]), quarter),
        ])
        #expect(reconcile(&reconciler, intent: quarter, now: .seconds(5)) == [])
        #expect(reconciler.built(chrome, token: 2, succeeded: true, now: .seconds(5)) == [])
        #expect(reconciler.enforcement(of: chrome, now: .seconds(5)) == .applied)
    }

    @Test
    func retriesAtZeroHundredThreeHundredThousand() throws {
        var reconciler = AudioReconciler()
        let quarter    = try intent()
        let expected   = configuration([10], [Self.builtIn])

        _ = reconcile(&reconciler, intent: quarter)

        let delays: [Duration] = [.zero, .milliseconds(100), .milliseconds(300), .seconds(1)]
        var now: Duration      = .zero

        for (index, delay) in delays.enumerated() {
            let token = UInt64(index + 1)

            #expect(reconciler.built(chrome, token: token, succeeded: false, now: now) == [
                .scheduleRetry(chrome, after: delay),
            ])

            if delay > .zero {
                #expect(reconcile(&reconciler, intent: quarter, now: now + delay - .milliseconds(1)) == [])
            }

            now += delay

            #expect(reconcile(&reconciler, intent: quarter, now: now) == [
                .build(chrome, token: token + 1, expected, quarter),
            ])
        }

        // The fifth build fails too: the ladder is spent, nothing more is scheduled.
        #expect(reconciler.built(chrome, token: 5, succeeded: false, now: now) == [])
        #expect(reconcile(&reconciler, intent: quarter, now: now + .seconds(10)) == [])
    }

    @Test
    func notAppliedAfterThreeSeconds() throws {
        var reconciler = AudioReconciler()

        _ = reconcile(&reconciler, intent: try intent(), now: .seconds(10))

        #expect(reconciler.enforcement(of: chrome, now: .seconds(10)) == .recovering)

        _ = reconciler.built(chrome, token: 1, succeeded: false, now: .seconds(11))

        #expect(reconciler.enforcement(of: chrome, now: .seconds(11)) == .recovering)
        #expect(reconciler.enforcement(of: chrome, now: .seconds(11) + .milliseconds(2999)) == .recovering)
        #expect(reconciler.enforcement(of: chrome, now: .seconds(14)) == .notApplied)
    }

    @Test
    func secondFailureEpisodeGoesNative() throws {
        var reconciler = AudioReconciler()
        let quarter    = try intent()
        let expected   = configuration([10], [Self.builtIn])

        _ = reconcile(&reconciler, intent: quarter)

        // Episode one: a failed build, then a success that ends it.
        _ = reconciler.built(chrome, token: 1, succeeded: false, now: .zero)
        _ = reconcile(&reconciler, intent: quarter, now: .zero)
        _ = reconciler.built(chrome, token: 2, succeeded: true, now: .milliseconds(5))

        // Episode two: the identical configuration fails again, and Cascade stops trying.
        _ = reconciler.environmentInvalidated(now: .seconds(60))

        #expect(reconciler.built(chrome, token: 3, succeeded: false, now: .seconds(60)) == [])
        #expect(reconciler.state(of: chrome) == .native(expected))
        #expect(reconciler.enforcement(of: chrome, now: .seconds(60)) == .notApplied)
        #expect(reconcile(&reconciler, intent: quarter, now: .seconds(90)) == [])

        // A different intent lifts the verdict.
        let louder = try intent(gain: 0.5)

        #expect(reconcile(&reconciler, intent: louder, now: .seconds(91)) == [
            .build(chrome, token: 4, expected, louder),
        ])
    }

    @Test
    func appLeavingTearsDownItsPipeline() throws {
        let quarter    = try intent()
        var reconciler = runningReconciler(intent: quarter)

        let actions = reconcile(&reconciler, intent: quarter, objectIDs: [])

        #expect(actions == [.teardown(chrome, token: 1)])
        #expect(reconciler.state(of: chrome) == .none)
        #expect(reconciler.enforcement(of: chrome, now: .zero) == .native)
    }

    @Test
    func lateHelperChangesConfigurationAndRebuilds() throws {
        let quarter    = try intent()
        var reconciler = runningReconciler(intent: quarter, objectIDs: [10])

        let actions = reconcile(&reconciler, intent: quarter, objectIDs: [11, 10])

        #expect(actions == [
            .teardown(chrome, token: 1),
            .build(chrome, token: 2, configuration([10, 11], [Self.builtIn]), quarter),
        ])
    }

    // MARK: - Controller decisions

    @Test
    func onlyRunningProcessesCountAndAppWithNoneRunningIsAbsent() throws {
        var reconciler = AudioReconciler()
        let quarter    = try intent()

        let mixed = reconciler.reconcile(
            intents         : [chrome: quarter],
            apps            : [chrome: processes([30, 10], running: true) + processes([20], running: false)],
            outputs         : [Self.builtIn],
            systemOutputUID : Self.builtIn,
            now             : .zero
        )

        #expect(mixed == [.build(chrome, token: 1, configuration([10, 30], [Self.builtIn]), quarter)])

        let silent = reconciler.reconcile(
            intents         : [chrome: quarter],
            apps            : [chrome: processes([10, 30], running: false)],
            outputs         : [Self.builtIn],
            systemOutputUID : Self.builtIn,
            now             : .zero
        )

        #expect(silent == [.teardown(chrome, token: 1)])
        #expect(reconciler.enforcement(of: chrome, now: .zero) == .native)
    }

    @Test
    func streamTapIsTrueOnlyForASingleDevice() throws {
        var reconciler = AudioReconciler()
        let both       = try intent(outputs: [Self.usb, Self.builtIn])

        let actions = reconcile(&reconciler, intent: both)

        #expect(actions == [
            .build(chrome, token: 1, configuration([10], [Self.usb, Self.builtIn], streamTap: false), both),
        ])
    }

    @Test
    func noSystemOutputMeansNoPipelineAndNotApplied() throws {
        var reconciler = AudioReconciler()
        let quarter    = try intent()

        #expect(reconcile(&reconciler, intent: quarter, outputs: [], system: nil) == [])
        #expect(reconciler.enforcement(of: chrome, now: .zero) == .notApplied)

        var running = runningReconciler(intent: quarter)

        #expect(reconcile(&running, intent: quarter, outputs: [], system: nil) == [.teardown(chrome, token: 1)])
        #expect(running.enforcement(of: chrome, now: .zero) == .notApplied)
    }

    @Test
    func crossfadeFailureFallsBackToTheOldPipelineAndRetries() throws {
        var reconciler = runningReconciler(intent: try intent(outputs: [Self.builtIn]))
        let toUSB      = try intent(outputs: [Self.usb])
        let target     = configuration([10], [Self.usb])

        _ = reconcile(&reconciler, intent: toUSB)

        #expect(reconciler.built(chrome, token: 2, succeeded: false, now: .zero) == [
            .scheduleRetry(chrome, after: .zero),
        ])
        #expect(reconciler.state(of: chrome) == .running(token: 1, configuration([10], [Self.builtIn])))
        #expect(reconciler.enforcement(of: chrome, now: .zero) == .applied)

        #expect(reconcile(&reconciler, intent: toUSB, now: .zero) == [
            .crossfade(chrome, from: 1, to: 3, target, toUSB),
        ])
        #expect(reconciler.built(chrome, token: 3, succeeded: true, now: .milliseconds(20)) == [])
        #expect(reconciler.state(of: chrome) == .running(token: 3, target))
    }

    @Test
    func environmentInvalidationDuringACrossfadeRestartsTheTarget() throws {
        var reconciler = runningReconciler(intent: try intent(outputs: [Self.builtIn]))
        let toUSB      = try intent(outputs: [Self.usb])

        _ = reconcile(&reconciler, intent: toUSB)

        #expect(reconciler.environmentInvalidated(now: .zero) == [
            .teardown(chrome, token: 1),
            .teardown(chrome, token: 2),
            .build(chrome, token: 3, configuration([10], [Self.usb]), toUSB),
        ])
    }

    @Test
    func intentChangedWhileBuildingIsCommandedOnceItRuns() throws {
        var reconciler = AudioReconciler()
        let quarter    = try intent()
        let louder     = try intent(gain: 0.5)

        _ = reconcile(&reconciler, intent: quarter)

        #expect(reconcile(&reconciler, intent: louder) == [])
        #expect(reconciler.built(chrome, token: 1, succeeded: true, now: .zero) == [
            .updateCommand(chrome, token: 1, louder),
        ])
    }

    @Test
    func enforcementFollowsThePipelineLifecycle() throws {
        var reconciler = AudioReconciler()

        _ = reconcile(&reconciler, intent: try intent())

        #expect(reconciler.enforcement(of: chrome, now: .zero) == .recovering)

        _ = reconciler.built(chrome, token: 1, succeeded: true, now: .zero)

        #expect(reconciler.enforcement(of: chrome, now: .zero) == .applied)
    }

    @Test
    func retryBuildingStillReportsTheFailureClock() throws {
        var reconciler = AudioReconciler()
        let quarter    = try intent()

        _ = reconcile(&reconciler, intent: quarter)
        _ = reconciler.built(chrome, token: 1, succeeded: false, now: .zero)
        _ = reconcile(&reconciler, intent: quarter, now: .zero)

        #expect(reconciler.enforcement(of: chrome, now: .seconds(1)) == .recovering)
        #expect(reconciler.enforcement(of: chrome, now: .seconds(4)) == .notApplied)
    }
}
