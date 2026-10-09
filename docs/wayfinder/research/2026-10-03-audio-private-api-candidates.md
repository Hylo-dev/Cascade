# Audio mixer: public and private system-control candidates

Research date: 3 October 2026. Status: static source investigation, not an audio
effect test. The user authorized private API investigation; this note does not
qualify a private backend for production.

## Recommendation and evidence boundary

Keep the public process-tap backend as the implementation baseline while testing
whether a system control can replace part of its work. The inspected sources
identify a public mute for the **calling process**, a private **device** ducking
function with a verified declaration, and private media-session/routing symbols
whose ABI and applicability to another application's audio remain unknown. No
verified arbitrary-process gain or output-routing setter was found in this
investigation. This is a scoped negative finding, not proof that none exists.

All control must pass through Cascade's implemented addon provider/context/service
broker and its grants. A private backend changes the host implementation behind
that contract; it gives the addon no direct system access and does not relax the
managed-launcher gate. Qualification must separate these six facts:

1. A symbol is advertised by an SDK export stub.
2. The running system resolves the symbol or reports a property exists.
3. Its calling convention, payload, ownership and object scope are known.
4. The actual caller has permission and a change is accepted.
5. The intended target's rendered audio changes, without changing other targets.
6. That effect remains enforced through sleep, device loss and audio-service reset.

Neither `dlsym` success nor `noErr` establishes the later facts. Apple's setter
contract specifically says property changes may be asynchronous and are not
considered changed until HAL listeners are called.
[SDK setter contract, line 302](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:302>).

## Provenance and availability

The inspected host reports macOS **27.0, build 26A5425a**. The Xcode-beta **27.0**
SDK reports `macosx27.0`, with SDK system version **27.0, build 26A5419a**. These
are different artifacts. SDK exports are not a runtime capability test, and this
beta inspection supplies no compatibility evidence for previous macOS releases.

The public property functions are declared from macOS 10.4. Process-tap creation
and destruction are declared `API_AVAILABLE(macos(14.2))` in this SDK. Individual
process/property capabilities still need runtime checks; missing introduction
annotations are not evidence of historical availability.
[Property functions, line 211](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:211>),
[tap availability, line 43](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardwareTapping.h:43>).

## Candidates and limits

| Candidate | Verified interface or evidence | Scope and remaining uncertainty |
| --- | --- | --- |
| `kAudioDevicePropertyProcessMute` (`'appm'`) | Public HAL property; `UInt32`, nonzero requests system zeroing. | Explicitly the **current process**, on physical devices only; excludes aggregate devices. It is not a declared API to mute an arbitrary PID. Discover existence and settability for the helper's physical output before any own-process experiment. |
| `kAudioHardwarePropertyProcessIsAudible` (`'pmut'`) | Public system-object property; `UInt32`, zero describes inaudible process audio. | The documented process context has no target-PID qualifier. Read-only discovery here cannot establish usable external-app control. Do not reinterpret it as a property on a Process object. |
| `kAudioHardwarePropertyProcessInputMute` (`'pmin'`) | Public system-object property; `UInt32`. | Incoming data for the process is silenced across devices. This is input mute, not per-app playback gain. |
| Process class (`'clnt'`) | Public PID, bundle ID, input/output device list and running-state properties. | Supports discovery and verification. The inspected Process-property list declares no gain control or routing command; a list of used devices is not an instruction to reroute audio. |
| `AudioDeviceDuck` | Private exported CoreAudio symbol; declaration verified in pinned Chromium source. | Four arguments describe a device, level, start timestamp and ramp duration; there is no PID. It is not a per-app mixer control. Calling it could change shared device ducking, so exclude it from the silent probe. |
| `FigRoutingContext…` / `FigVolumeController…` | Private MediaExperience exports and named client-PID/context-volume keys. | Promising catalog leads only. No primary C signature, ownership contract, privilege requirements or arbitrary-process effect was recovered. Do not call through a guessed typedef. |
| `MXSession…` | Private MediaExperience creation/property exports and mute/volume/client-PID keys. | Names suggest session controls but do not prove that a third party can attach to another application's session or control general HAL clients. No verified C ABI was recovered. |
| Audio Server Plug-in per-client processing | Public driver interface identifies client PID/bundle ID and passes client ID to an output-processing callback. | Can process clients of **its own device**. It does not intercept every physical output automatically. A virtual-device backend would add routing, installation and audio-server realtime responsibilities. |

Public property evidence:
[device process mute, line 991](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:991>),
[system process properties, line 547](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:547>),
[Process class properties, line 1947](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:1947>).

The verified ducking declaration is:

```c
OSStatus AudioDeviceDuck(
    AudioDeviceID inDevice,
    Float32 inDuckedLevel,
    const AudioTimeStamp* inStartTime,
    Float32 inRampDuration
);
```

Chromium declares it with `weak_import` and uses it to undo device ducking. That
consumer declaration corroborates the ABI, not its supported lifecycle contract.
[Chromium source pinned to 01632a64, declaration near line 36](https://chromium.googlesource.com/chromium/src/+/01632a64d65f275b5bae32afa5da908b08a88b97/media/audio/mac/audio_low_latency_input_mac.cc#36),
[local CoreAudio export, line 11](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/CoreAudio.tbd:11>).

The public driver alternative has a known per-client seam:
`AudioServerPlugInClientInfo` provides `mClientID`, `mProcessID` and `mBundleID`;
`DoIOOperation` receives `inClientID`, while
`kAudioServerPlugInIOOperationProcessOutput` processes output before the full-mix
stage. This may support gain inside an audio-server device implementation. It
requires clients to use that device, and does not solve routing from arbitrary
physical devices by itself.
[Client information, line 179](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioServerPlugIn.h:179>),
[output operation, line 319](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioServerPlugIn.h:319>),
[callback signature, line 1115](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioServerPlugIn.h:1115>).

## Private symbol inventory for an address-only probe

Use the following exact names with `dlsym`; the leading underscore in a Mach-O
SDK stub is not part of the `dlsym` name. Resolving an address does not authorize
dereferencing a data symbol or calling a function with an inferred signature.

| Family | Function names to inventory | Associated exported names, also address-only |
| --- | --- | --- |
| Routing contexts | `FigRoutingContextCopyAllAudioContexts`, `FigRoutingContextCopyContextForUUID`, `FigRoutingContextCopySystemAudioContext`, `FigRoutingContextCreateAudioContext`, `FigRoutingContextGetTypeID` | `kFigRoutingContextCreateOption_ClientPID`, `kFigRoutingContextCreateOption_ContextUUID` |
| Volume controller | `FigVolumeControllerCopySharedControllerRemote`, `FigVolumeControllerGetTypeID` | `kFigVolumeControllerMasterVolumeKey_CanSetMasterVolume`, `kFigVolumeControllerMasterVolumeKey_RoutingContextUUID`, `kFigVolumeControllerMasterVolumeKey_Volume` |
| Media sessions | `MXSessionCreate`, `MXSessionCreateWithOptions`, `MXSessionCopyProperty`, `MXSessionSetProperty` | `kMXSessionProperty_ClientPID`, `kMXSessionProperty_IsOutputMuted`, `kMXSessionProperty_UserVolume`, `kMXSessionProperty_UserMuted` |

These names occur in the local `MediaExperience.tbd`:
[functions, line 32](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/MediaExperience.framework/Versions/A/MediaExperience.tbd:32>),
[client options, line 247](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/MediaExperience.framework/Versions/A/MediaExperience.tbd:247>),
[volume keys, line 321](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/MediaExperience.framework/Versions/A/MediaExperience.tbd:321>),
[session PID, line 475](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/MediaExperience.framework/Versions/A/MediaExperience.tbd:475>),
[mute, line 524](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/MediaExperience.framework/Versions/A/MediaExperience.tbd:524>),
[user volume, line 598](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/MediaExperience.framework/Versions/A/MediaExperience.tbd:598>).

Do not use `AvoidAuthPrompt`, inherited PID or host-bundle options as a permission
bypass. Their names provide no entitlement contract. Private Objective-C method
metadata may help recover signatures, but iOS class dumps and guessed macOS
selectors are not suitable ABI evidence.

## Minimal experiments and qualification gates

Run discovery in a short-lived native helper, off Cascade's main thread. Record
OS build, architecture, executable identity and framework load errors. Loading a
framework may execute initializers; address discovery belongs in that isolated
helper, not a render callback or startup hot path.

For HAL properties, use the declared `AudioObjectHasProperty`,
`AudioObjectIsPropertySettable`, size and read functions. Record selector, object,
scope, element, qualifier, `OSStatus`, returned size and value separately. For
`TranslatePIDToProcessObject`, the qualifier is exactly a `pid_t`; success may
return `kAudioObjectUnknown`. Accept fixed-size values only at the expected size;
cap list allocation, check divisibility, and tolerate an object disappearing
between the size query and read. There is no need to scan invented four-character
selectors.
[HAL functions, line 211](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:211>),
[PID translation contract, line 589](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:589>).

The parent's silent AudioQueue helper can test existence, settability, listener
delivery and readback of `appm` for its **own** physical output. Save and restore
its original value, bound waits, and clean up on failure. Silence makes this a
safe plumbing experiment; it cannot prove acoustic attenuation, signal integrity,
control of another process, or sleep persistence. Keep `pmut` discovery read-only
and private symbols address-only until their ABI is verified.

A later effect experiment needs a controlled source and a measured output, plus
an unaffected second source. Test gain accuracy, exact mute, route isolation,
sample formats, latency, and sleep/wake before presenting a backend as equivalent
to a system feature. Repeat on every supported macOS/architecture combination.
No audio capture, hardware setting mutation, service reset or private function
invocation was performed for this research note.

## Recovery and energy requirements remain

A HAL service reset requires clients to recreate cached state and listeners;
Apple documents this explicitly for `kAudioHardwarePropertyServiceRestarted`
(`'srst'`). A private controller is not evidence that this responsibility goes
away. Persist desired gain/mute/output identity separately from transient PIDs,
object IDs and controller handles; restore intent before accepting a replacement
render generation as ready.
[Service reset contract, line 573](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:573>).

If a tap disappears, desired mute and native playback may diverge. A system setter
would improve that boundary only after tests establish independent enforcement
on the intended external process. Do not label a return to native unity gain as
successful recovery or claim guaranteed quiet after losing the only enforcement
mechanism. See the separate
[lifecycle note](</Users/c4v4h/Library/Mobile Documents/com~apple~CloudDocs/Projects/XcodeProjects/Cascade/docs/wayfinder/research/2026-10-03-audio-lifecycle.md>).

The approved single 1 Hz watchdog remains conditional on controlled I/O being
expected and observes callback sequence, not amplitude. App discovery remains
event driven. A system-control backend might remove copies/render work, but its
energy benefit is unmeasured; session creation or route discovery might also add
work. Measure real CPU, wakeups, memory and latency against the tap baseline,
including notch-closed playback, mute, idle, device change and wake. Do no private
symbol scanning, route discovery or per-app timer work in steady state.

## Reproducibility fingerprints

The exact inspected SDK artifacts have these SHA-256 values:

| Artifact | SHA-256 |
| --- | --- |
| `CoreAudio.framework/Headers/AudioHardware.h` | `a699437248e079d9ebe47078ef3861492d8253fef1a6007e476031031d3535ca` |
| `CoreAudio.framework/Headers/AudioHardwareTapping.h` | `aa337054d41d0a2293b91fa7a2ec2e1819d66ab7722c60ff9a482821a4ccd92e` |
| `CoreAudio.framework/CoreAudio.tbd` | `69a6b71947749c30008730d8d2d42b3d0f16af546ed7caf88ad3feb815a8d720` |
| `MediaExperience.framework/MediaExperience.tbd` | `7cb603e928f74fbc5701443baae2e3292ce863783b5081ee943f70d87203bd5b` |
