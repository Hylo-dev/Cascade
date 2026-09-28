import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

/// Fixed records replace only the external libproc/clock boundary. Assertions exercise
/// the real reader and reducer; expected interval values are independently derived.
@Suite struct ProcessMetricsTests {
    private let executableUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    private let token = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let domain = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    private func binding(
        pid: Int32 = 42,
        birth: UInt64 = 100,
        uuid: UUID? = nil,
        token: UUID? = nil,
        domain: UUID? = nil
    ) -> ProcessMetricBinding {
        ProcessMetricBinding(
            pid: pid,
            birthAbsoluteTicks: birth,
            executableUUID: uuid ?? executableUUID,
            token: token ?? self.token,
            clockDomain: domain ?? self.domain
        )
    }

    private func record(
        birth: UInt64 = 100,
        uuid: UUID? = nil,
        user: UInt64 = 10,
        system: UInt64 = 20,
        footprint: UInt64 = 4_096,
        exit: UInt64 = 0
    ) -> ProcessMetricRecord {
        ProcessMetricRecord(
            birthAbsoluteTicks: birth,
            executableUUID: uuid ?? executableUUID,
            userTicks: user,
            systemTicks: system,
            footprintBytes: footprint,
            exitAbsoluteTicks: exit
        )
    }

    private func observation(
        binding: ProcessMetricBinding? = nil,
        user: UInt64 = 10,
        system: UInt64 = 20,
        footprint: UInt64 = 4_096,
        start: UInt64 = 200,
        end: UInt64 = 201,
        numer: UInt32 = 1,
        denom: UInt32 = 1
    ) -> ProcessMetricObservation {
        ProcessMetricObservation(
            binding: binding ?? self.binding(),
            userTicks: user,
            systemTicks: system,
            footprintBytes: footprint,
            window: ProcessMetricWindow(startTicks: start, endTicks: end),
            timebase: ProcessMetricTimebase(numer: numer, denom: denom)
        )
    }

    /// This spy verifies acquisition count, supplied PID, and dependency ordering.
    /// Captured errno is represented as a value, so later clock reads cannot alter it.
    private final class Acquisition {
        var calls: [String] = []
        var raw: RawProcessMetricRead
        var ticks: [UInt64]
        var timebase: RawProcessMetricTimebase

        init(
            raw: RawProcessMetricRead,
            ticks: [UInt64] = [200, 201],
            timebase: RawProcessMetricTimebase = .success(ProcessMetricTimebase(numer: 1, denom: 1))
        ) {
            self.raw = raw
            self.ticks = ticks
            self.timebase = timebase
        }

        func reader() -> ProcessMetricsReader {
            ProcessMetricsReader(
                readRaw: { pid in
                    self.calls.append("read:\(pid)")
                    return self.raw
                },
                absoluteTicks: {
                    self.calls.append("clock")
                    return self.ticks.removeFirst()
                },
                readTimebase: {
                    self.calls.append("timebase")
                    return self.timebase
                }
            )
        }
    }

    // Catches repeated acquisition, wrong PID/order wiring, or lost fields.
    @Test func readerAcquiresExactlyOnceAndCarriesTheFencedRecord() throws {
        let source = Acquisition(raw: .success(record(user: 123, system: 456, footprint: UInt64.max)))
        let result = source.reader().read(binding())
        guard case .sample(let sample) = result else {
            Issue.record("Expected a fenced sample, got \(result)")
            return
        }
        #expect(source.calls.filter { $0.hasPrefix("read:") } == ["read:42"])
        #expect(Array(source.calls.prefix(3)) == ["clock", "read:42", "clock"])
        #expect(sample.binding == binding())
        #expect(sample.userTicks == 123)
        #expect(sample.systemTicks == 456)
        #expect(sample.footprintBytes == UInt64.max)
        #expect(sample.window == ProcessMetricWindow(startTicks: 200, endTicks: 201))
        #expect(sample.timebase == ProcessMetricTimebase(numer: 1, denom: 1))
    }

    // Catches adopting an arbitrary PID occupant or using zero identity as a wildcard.
    @Test func invalidExpectationNeverTouchesTheAcquisitionBoundary() {
        for invalid in [binding(pid: 0), binding(pid: -1), binding(birth: 0), binding(uuid: zeroUUID)] {
            let source = Acquisition(raw: .success(record()))
            #expect(source.reader().read(invalid) == .unavailable(.invalidExpectation))
            #expect(source.calls.isEmpty)
        }
    }

    // Catches accepting counters/footprint from another birth or executable image.
    @Test func identityMismatchRejectsTheSameReturnedRecord() {
        let otherUUID = UUID(uuidString: "99999999-2222-3333-4444-555555555555")!
        for raw in [record(birth: 101), record(uuid: otherUUID)] {
            let source = Acquisition(raw: .success(raw))
            #expect(source.reader().read(binding()) == .unavailable(.identityMismatch))
            #expect(source.calls.filter { $0.hasPrefix("read:") }.count == 1)
        }
    }

    @Test func unavailableReturnedIdentityIsDistinctFromMismatch() {
        for raw in [record(birth: 0), record(uuid: zeroUUID)] {
            let source = Acquisition(raw: .success(raw))
            #expect(source.reader().read(binding()) == .unavailable(.identityUnavailable))
        }
    }

    // Identity must win over exit/malformed counters; no rejected footprint escapes.
    @Test func identityFencePrecedesExitAndClockValidation() {
        let source = Acquisition(raw: .success(record(birth: 101, footprint: UInt64.max, exit: 500)), ticks: [201, 200])
        #expect(source.reader().read(binding()) == .unavailable(.identityMismatch))
    }

    @Test func exitedRecordIsNeverALiveSample() {
        let source = Acquisition(raw: .success(record(exit: 500)))
        #expect(source.reader().read(binding()) == .unavailable(.exited))
    }

    // Catches zero-on-error, collapsing errno, and retries hidden in the reader.
    @Test(arguments: [Int32(ESRCH), Int32(EPERM), Int32(EACCES), Int32(EIO), Int32(EINTR)])
    func acquisitionFailureKeepsItsCapturedErrno(error: Int32) {
        let source = Acquisition(raw: .failure(error))
        #expect(source.reader().read(binding()) == .unavailable(.readFailed(error)))
        #expect(source.calls.filter { $0.hasPrefix("read:") } == ["read:42"])
    }

    @Test func readerRejectsReversedOrPreBirthAcquisitionBounds() {
        for ticks: [UInt64] in [[201, 200], [99, 201]] {
            let source = Acquisition(raw: .success(record()), ticks: ticks)
            #expect(source.reader().read(binding()) == .unavailable(.invalidAcquisition))
        }
    }

    @Test func readerRejectsMissingOrInvalidTimebase() {
        let failed = Acquisition(raw: .success(record()), timebase: .failure(5))
        #expect(failed.reader().read(binding()) == .unavailable(.timebaseFailed(5)))
        for value in [ProcessMetricTimebase(numer: 0, denom: 1), ProcessMetricTimebase(numer: 1, denom: 0)] {
            let source = Acquisition(raw: .success(record()), timebase: .success(value))
            #expect(source.reader().read(binding()) == .unavailable(.invalidTimebase))
        }
    }

    // Catches treating the initial cumulative counters as an interval from zero.
    @Test func firstSampleProvidesFootprintWithoutCPU() {
        var reducer = ProcessMetricsReducer(binding: binding())
        let result = reducer.consume(.sample(observation(user: UInt64.max, system: UInt64.max, footprint: 0)))
        #expect(result.status == .baseline)
        #expect(result.footprintBytes == 0)
        #expect(result.interval == nil)
    }

    // Hand-derived: 1,200,000 * 125 / 3 = 50ms; 240,000,000 ticks = 10s.
    @Test func nonUnitTimebaseConvertsComponentDeltasOnce() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: 50, system: 70, start: 1_000, end: 1_001, numer: 125, denom: 3)))
        let current = observation(user: 900_050, system: 300_070, footprint: 8_192, start: 240_001_000, end: 240_001_001, numer: 125, denom: 3)
        let result = reducer.consume(.sample(current))
        let interval = try #require(result.interval)
        #expect(result.status == .interval)
        #expect(result.footprintBytes == 8_192)
        #expect(interval.cpuNanoseconds == 50_000_000)
        #expect(interval.elapsedNanoseconds == 10_000_000_000)
        #expect(interval.previousWindow == ProcessMetricWindow(startTicks: 1_000, endTicks: 1_001))
        #expect(interval.currentWindow == current.window)
    }

    // Catches separately flooring user/system deltas: floor((1+1)/2)=1, not 0.
    @Test func fractionalCPUIsRoundedOnlyAfterCombiningDeltas() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: 0, system: 0, numer: 1, denom: 2)))
        let result = reducer.consume(.sample(observation(user: 1, system: 1, start: 204, end: 205, numer: 1, denom: 2)))
        let interval = try #require(result.interval)
        #expect(interval.cpuNanoseconds == 1)
        #expect(interval.elapsedNanoseconds == 2)
    }

    @Test func successfulUnchangedCountersProduceARealZeroInterval() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation()))
        let result = reducer.consume(.sample(observation(footprint: 0, start: 300, end: 301)))
        #expect(result.status == .interval)
        #expect(result.footprintBytes == 0)
        #expect(try #require(result.interval).cpuNanoseconds == 0)
        #expect(try #require(result.interval).elapsedNanoseconds == 100)
    }

    @Test func aggregateCPUAboveOneCoreIsNotClamped() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: 0, system: 0)))
        let result = reducer.consume(.sample(observation(user: 150, system: 50, start: 300, end: 301)))
        let interval = try #require(result.interval)
        #expect(interval.cpuNanoseconds == 200)
        #expect(interval.elapsedNanoseconds == 100)
    }

    // Catches summing cumulative counters before subtraction (that sum overflows).
    @Test func overflowingCumulativeTotalsStillPermitSmallDeltas() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: UInt64.max - 10, system: UInt64.max - 20)))
        let result = reducer.consume(.sample(observation(user: UInt64.max - 7, system: UInt64.max - 15, start: 300, end: 301)))
        #expect(try #require(result.interval).cpuNanoseconds == 8)
    }

    @Test func eachRegressingComponentResetsToTheCurrentBaseline() throws {
        for counters: (UInt64, UInt64) in [(9, 100), (100, 19)] {
            var reducer = ProcessMetricsReducer(binding: binding())
            _ = reducer.consume(.sample(observation()))
            let reset = reducer.consume(.sample(observation(user: counters.0, system: counters.1, footprint: 777, start: 300, end: 301)))
            #expect(reset.status == .reset(.counterRegression))
            #expect(reset.footprintBytes == 777)
            #expect(reset.interval == nil)
            let next = reducer.consume(.sample(observation(user: counters.0 + 2, system: counters.1 + 3, start: 400, end: 401)))
            #expect(try #require(next.interval).cpuNanoseconds == 5)
        }
    }

    @Test func missingReadBreaksContinuityInsteadOfReportingZero() {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation()))
        let missing = reducer.consume(.unavailable(.readFailed(ESRCH)))
        #expect(missing.status == .unavailable(.readFailed(ESRCH)))
        #expect(missing.footprintBytes == nil)
        #expect(missing.interval == nil)
        let next = reducer.consume(.sample(observation(user: 500, start: 300, end: 301)))
        #expect(next.status == .baseline)
        #expect(next.interval == nil)
    }

    @Test func allNonTerminalReadErrorsBreakContinuity() {
        let errors: [ProcessMetricFailure] = [.identityUnavailable, .invalidAcquisition, .invalidTimebase, .timebaseFailed(5), .invalidExpectation]
        for error in errors {
            var reducer = ProcessMetricsReducer(binding: binding())
            _ = reducer.consume(.sample(observation()))
            #expect(reducer.consume(.unavailable(error)).interval == nil)
            #expect(reducer.consume(.sample(observation(start: 300, end: 301))).status == .baseline)
        }
    }

    // Catches resurrecting a rejected identity merely because its fields match later.
    @Test func mismatchOrExitInvalidatesBindingEvenAfterExplicitReset() {
        for error: ProcessMetricFailure in [.identityMismatch, .exited] {
            var reducer = ProcessMetricsReducer(binding: binding())
            _ = reducer.consume(.sample(observation()))
            let rejected = reducer.consume(.unavailable(error))
            #expect(rejected.status == .unavailable(error))
            #expect(rejected.footprintBytes == nil)
            reducer.reset()
            let returned = reducer.consume(.sample(observation(start: 300, end: 301)))
            #expect(returned.status == .unavailable(.bindingInvalidated))
            #expect(returned.footprintBytes == nil)
            #expect(returned.interval == nil)
        }
    }

    @Test func anotherBindingCannotPoisonTheExpectedBindingBaseline() throws {
        let alternatives = [
            binding(pid: 43), binding(birth: 101), binding(uuid: UUID()),
            binding(token: UUID()), binding(domain: UUID()),
        ]
        for alternative in alternatives {
            var reducer = ProcessMetricsReducer(binding: binding())
            _ = reducer.consume(.sample(observation()))
            let rejected = reducer.consume(.sample(observation(binding: alternative, footprint: UInt64.max, start: 300, end: 301)))
            #expect(rejected.status == .invalid(.bindingMismatch))
            #expect(rejected.footprintBytes == nil)
            #expect(rejected.interval == nil)
            #expect(reducer.consume(.sample(observation(start: 400, end: 401))).status == .baseline)
        }
    }

    @Test func explicitRepeatedResetRequiresAFreshBaseline() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation()))
        reducer.reset()
        reducer.reset()
        #expect(reducer.consume(.sample(observation(user: 100, start: 300, end: 301))).status == .baseline)
        let next = reducer.consume(.sample(observation(user: 107, system: 21, start: 400, end: 401)))
        #expect(try #require(next.interval).cpuNanoseconds == 8)
    }

    // Reversed/malformed samples cannot even seed a baseline or expose footprint.
    @Test func malformedObservationCannotSeedABaseline() {
        for value in [observation(start: 201, end: 200), observation(start: 99, end: 201), observation(numer: 0), observation(denom: 0)] {
            var reducer = ProcessMetricsReducer(binding: binding())
            let result = reducer.consume(.sample(value))
            #expect(result.interval == nil)
            #expect(result.footprintBytes == nil)
            #expect(result.status != .baseline)
            #expect(reducer.consume(.sample(observation(start: 300, end: 301))).status == .baseline)
        }
    }

    @Test func invalidReducerExpectationCannotAcceptASample() {
        var reducer = ProcessMetricsReducer(binding: binding(pid: 0))
        let result = reducer.consume(.sample(observation(binding: binding(pid: 0))))
        #expect(result.status == .invalid(.invalidExpectation))
        #expect(result.footprintBytes == nil)
        #expect(result.interval == nil)
    }

    // Catches equal/backward/overlapping endpoints being used as CPU denominators.
    @Test func unorderedWindowsBreakTheCPUIntervalAndKeepOnlyValidCurrentFootprint() {
        for window in [(UInt64(200), UInt64(201)), (199, 200), (200, 202)] {
            var reducer = ProcessMetricsReducer(binding: binding())
            _ = reducer.consume(.sample(observation()))
            let result = reducer.consume(.sample(observation(footprint: 999, start: window.0, end: window.1)))
            #expect(result.status == .invalid(.nonIncreasingTime))
            #expect(result.footprintBytes == 999)
            #expect(result.interval == nil)
            #expect(reducer.consume(.sample(observation(start: 300, end: 301))).status == .baseline)
        }
    }

    @Test func touchingWindowsWithStrictlyIncreasingEndAreAccepted() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation()))
        let result = reducer.consume(.sample(observation(user: 11, start: 201, end: 202)))
        #expect(try #require(result.interval).elapsedNanoseconds == 1)
    }

    @Test func changedTimebaseBreaksContinuityAndCannotMixUnits() {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation()))
        let result = reducer.consume(.sample(observation(footprint: 777, start: 300, end: 301, numer: 125, denom: 3)))
        #expect(result.status == .invalid(.timebaseChanged))
        #expect(result.footprintBytes == 777)
        #expect(result.interval == nil)
        #expect(reducer.consume(.sample(observation(start: 400, end: 401, numer: 125, denom: 3))).status == .baseline)
    }

    @Test func roundedZeroElapsedIsUnavailableRatherThanADivisionByZero() {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(numer: 1, denom: 3)))
        let result = reducer.consume(.sample(observation(footprint: 888, start: 201, end: 202, numer: 1, denom: 3)))
        #expect(result.status == .invalid(.zeroElapsed))
        #expect(result.footprintBytes == 888)
        #expect(result.interval == nil)
        #expect(reducer.consume(.sample(observation(start: 300, end: 301, numer: 1, denom: 3))).status == .baseline)
    }

    @Test func componentDeltaSumOverflowNeverWrapsOrSeedsANewBaseline() {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: 0, system: 0)))
        let result = reducer.consume(.sample(observation(user: UInt64.max, system: 1, footprint: UInt64.max, start: 300, end: 301)))
        #expect(result.status == .invalid(.counterOverflow))
        #expect(result.footprintBytes == UInt64.max)
        #expect(result.interval == nil)
        #expect(reducer.consume(.sample(observation(start: 400, end: 401))).status == .baseline)
    }

    // Product overflows UInt64, but (max * 2) / 2 is exactly representable.
    @Test func fullWidthProductWithRepresentableQuotientSucceeds() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: 0, system: 0, numer: 2, denom: 2)))
        let result = reducer.consume(.sample(observation(user: UInt64.max, system: 0, start: 300, end: 301, numer: 2, denom: 2)))
        #expect(try #require(result.interval).cpuNanoseconds == UInt64.max)
        #expect(try #require(result.interval).elapsedNanoseconds == 100)
    }

    @Test func unrepresentableCPUQuotientRejectsWithoutTrapping() {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: 0, system: 0, numer: 2)))
        let result = reducer.consume(.sample(observation(user: UInt64.max, system: 0, footprint: 777, start: 300, end: 301, numer: 2)))
        #expect(result.status == .invalid(.conversionOverflow))
        #expect(result.footprintBytes == 777)
        #expect(result.interval == nil)
        #expect(reducer.consume(.sample(observation(start: 400, end: 401, numer: 2))).status == .baseline)
    }

    @Test func unrepresentableElapsedQuotientRejectsWithoutTrapping() {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: 0, system: 0, numer: 2)))
        let result = reducer.consume(.sample(observation(user: 1, system: 0, footprint: 777, start: UInt64.max - 1, end: UInt64.max, numer: 2)))
        #expect(result.status == .invalid(.conversionOverflow))
        #expect(result.footprintBytes == 777)
        #expect(result.interval == nil)
    }

    @Test func largestTimebaseUsesFullWidthMathWithoutIntermediateOverflow() throws {
        var reducer = ProcessMetricsReducer(binding: binding())
        _ = reducer.consume(.sample(observation(user: 0, system: 0, numer: UInt32.max, denom: UInt32.max)))
        let result = reducer.consume(.sample(observation(user: UInt64.max, system: 0, start: 300, end: 301, numer: UInt32.max, denom: UInt32.max)))
        #expect(try #require(result.interval).cpuNanoseconds == UInt64.max)
    }

    /// Reads only this already-existing test process. The independent first v0 read
    /// supplies an explicit expectation; this verifies buffer ABI, not authentication,
    /// permissions across peers, CPU units, or macOS 14 runtime qualification.
    @Test func nativeReaderObservesOnlyItsOwnExistingProcessABI() throws {
        var raw = rusage_info_v0()
        let pid = getpid()
        let (code, capturedErrno) = withUnsafeMutablePointer(to: &raw) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { buffer in
                let code = proc_pid_rusage(pid, RUSAGE_INFO_V0, buffer)
                return (code, errno)
            }
        }
        try #require(code == 0, "Self v0 bootstrap failed: errno \(capturedErrno)")
        let expected = binding(pid: pid, birth: raw.ri_proc_start_abstime, uuid: UUID(uuid: raw.ri_uuid))
        let result = ProcessMetricsReader().read(expected)
        guard case .sample(let sample) = result else {
            Issue.record("Native self ABI read failed: \(result)")
            return
        }
        #expect(sample.binding == expected)
        #expect(sample.window.startTicks >= raw.ri_proc_start_abstime)
        #expect(sample.window.endTicks >= sample.window.startTicks)
        #expect(sample.timebase.numer > 0)
        #expect(sample.timebase.denom > 0)
    }
}
