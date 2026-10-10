//
//  CoreAudioHostHALSmokeTests.swift
//  CascadeKit
//

@testable import CascadeAudioHost
import Foundation
import Testing

/// CoreAudioHostHALSmokeTests reads the real HAL, and only reads it: no tap, no aggregate
/// device, no listener, so it never prompts for permission or changes what anyone hears.
///
/// It stays off by default because a CI machine may have no audio hardware at all. Set
/// `CASCADE_AUDIO_HAL_SMOKE=1` to run it on a Mac you are sitting at.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CASCADE_AUDIO_HAL_SMOKE"] == "1"))
struct CoreAudioHostHALSmokeTests {

    @Test
    func theReadOnlyQueriesAnswerCoherently() {
        let queue = DispatchQueue(label: "cascade.audio.hal.smoke")
        let hal   = CoreAudioHostHAL(queue: queue)

        queue.sync {
            let outputs   = hal.outputUIDs()
            let systemUID = hal.systemOutputUID()
            let processes = hal.processes()

            print("HAL smoke: \(outputs.count) outputs, system output \(systemUID ?? "none"), \(processes.count) audio processes")

            if let systemUID {
                #expect(outputs.contains(systemUID))
                #expect(hal.streamFormat(ofOutput: systemUID) != nil)
            }

            for process in processes {
                #expect(process.objectID != 0)
                #expect(process.pid > 0)
            }
        }
    }
}
