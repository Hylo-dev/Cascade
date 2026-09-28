//
//  VolumeReadOnlyProbe.swift
//  Cascade
//

#if VOLUME_READ_ONLY_PROBE
import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// VolumeReadOnlyProbe checks SDK/runtime plumbing without posting events,
/// changing audio, showing permission prompts or running an input filter.
@main
nonisolated private enum VolumeReadOnlyProbe {

    static func main() {
        print("Accessibility already authorized: \(AXIsProcessTrusted())")

        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            let tap = CGEvent.tapCreate(
                tap             : location,
                place           : .headInsertEventTap,
                options         : .defaultTap,
                eventsOfInterest: CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue,
                callback        : { _, _, event, _ in Unmanaged.passUnretained(event) },
                userInfo        : nil
            )
            print("Tap location \(location.rawValue) can be created: \(tap != nil)")
            if let tap { CFMachPortInvalidate(tap) }
        }

        let queue = DispatchQueue(label: "Cascade.Volume.ReadOnlyProbe")
        queue.sync {
            let audio = CoreAudioSystemVolume(queue: queue)
            audio.refreshOutput()

            let snapshot = audio.snapshot()
            print("Default output has a readable, controllable snapshot: \(snapshot != nil)")
            print("Default output supports replacement: \(audio.supportsVolume)")
            audio.stop()
        }
    }
}

#endif
