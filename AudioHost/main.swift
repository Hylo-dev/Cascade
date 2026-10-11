//
//  main.swift
//  AudioHost
//

import CascadeAudioHost
import CascadePluginHost
import Foundation

// AudioHost taps, silences and re-renders the audio of other apps, one pipeline per app, in a
// process of its own: a HAL fault or a hung IOProc costs an AudioHost restart, never Cascade.
// It accepts only the app it is bundled in, signed by its own team when it has one. Everything
// the service does happens on one serial control queue; the HAL, the scheduler and the XPC entry
// points only hop onto it.

let controlQueue = DispatchQueue(label: "cascade.audiohost.control", qos: .userInitiated)
let startInstant = ContinuousClock.now
let relay        = AudioHostClientRelay()

let service = AudioHostService(
    hal     : makeCoreAudioHostHAL(queue: controlQueue),
    queue   : controlQueue,
    clock   : { ContinuousClock.now - startInstant },
    schedule: { delay, work in
        let components = delay.components
        let seconds    = Double(components.seconds) + Double(components.attoseconds) / 1e18

        controlQueue.asyncAfter(deadline: .now() + seconds, execute: work)
    },
    publish : { snapshot in relay.publish(snapshot) }
)

let ownIdentifier = Bundle.main.bundleIdentifier ?? ""
let appIdentifier = ownIdentifier.hasSuffix(".AudioHost") ? String(ownIdentifier.dropLast(".AudioHost".count)) : ownIdentifier
let delegate      = AudioHostListener(
    service    : service,
    relay      : relay,
    requirement: PluginHostSigning.requirement(identifier: appIdentifier, team: PluginHostSigning.currentTeam)
)

let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
