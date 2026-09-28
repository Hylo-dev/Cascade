# AirPods audio handoff and essential notice

## Problem reproduced from the data

The reported case is the AirPods automatically returning from the iPhone to the
Mac, not necessarily a new ACL connection. The previous monitor correctly
deduplicated the connection already present, but lost the new audio routing.
The local ControlCenter logs confirm `SmartRoutingSystemBannerContent` with
event `connected`, presented through `MBSystemBannerAssertion` and MenuBarAgent.
The user could not trigger the popup again during the investigation.

## Change

A CoreAudio listener on the default output detects handoffs to a Bluetooth
device identified by its real UID. The Darwin notification
`com.apple.BluetoothServices.AudioRoutingChanged` is only an additional signal
to reread that output: on its own it generates no notice. No polling, discovery,
continuous log reading or change to the audio output.

The sequence AirPods → built-in output → AirPods emits a new notice even if
the ACL connection persists. Startup and resume create silent baselines.
Temporary HAL errors preserve the baseline; only a confirmed absence of output
resets it. The first audio change within two seconds of a new physical
connection is merged into its notice; after that, later returns are standalone
events. The metadata keeps identity/revision and the meaning of the audio
change, discarding results that belong to earlier events.

The baseline change also replaces the audio task and stream, so elements
queued before the wake do not take on the identity of the new session.
A new route keeps the model, but waits for fresh battery measurements:
individual earbud values belonging to the previous route cannot
overwrite a new aggregate percentage.

Explicit limit: if the automatic handoff leaves the UID of the default audio
output unchanged, the Darwin hint alone does not generate an event. The monitor
requires a verifiable transition of the output; it does not assume a new route.

The Bluetooth presentation contains only model/symbol and ring: no visible
name, state or number. The remaining track is green at 28% opacity with a
thickness equal to 60% of the charged arc; the preferred wings go from 116 to
40 points. The accessibility and help texts use an EN/IT catalog that follows
the language the system selected for the app, with an English fallback.

## Native notice

The recognition includes the SystemBannerUI schema with the exact identifiers
`smart-routing-system-banner` and `com.apple.controlcenter.dismiss`. The
identifiers come from the implementations in the installed Apple framework.
On macOS 27 the additional host is `com.apple.MenuBarAgent` (case significant).
Dismissal stays selective, conditional on a recent event, the exact name and the
connection text supplied by the system resources; pairing, the reverse handoff
to the iPhone and interactive controls stay excluded. The shared MenuBarAgent
window is not closed.

This AX path acts after the presentation: it does not guarantee the absence of
a first frame of the popup. Behavior on the real popup remains to be verified
when it becomes reproducible again. Do not equate active observation with
confirmed suppression.

Private APIs protected by Apple entitlements were ruled out: the
AASystemStateMonitor/AADeviceManager probe receives `kMissingEntitlementErr`;
the SystemBanner listener explicitly checks its own entitlement. The legacy
preference `srConnectionAlert` showed no use in the presentation of the banner
in this version. None of these authorizations or preferences was
altered.

## Checks

- Regression on the audio return with the link already present: failure observed
  before the fix in `/private/tmp/cascade-smart-route-integration-red.log`.
- Bluetooth reducer/metadata/lifecycle suite and AX policy:
  `/private/tmp/cascade-smart-route-bluetooth-tests.log`.
- CoreAudio/route harness: `scripts/test-bluetooth-audio-route.sh`.
- Graphics harness: twelve Apple PIDs, battery semantics and animation
  lifecycle; preview in `/private/tmp/cascade-bluetooth-presentation/notices.png`.
- Earlier battery regression: failure observed in
  `/private/tmp/cascade-route-battery-red.log`, then the Bluetooth suite passed.
- Debug build and stable signature check succeeded:
  `/private/tmp/cascade-smart-route-build.log`. EN/IT resources compiled into the bundle.
- 42 volume checks passed: `/private/tmp/cascade-smart-route-volume-tests.log`.
- `git diff --check` passed.
- Relaunch completed after the unlock, on 2026-09-08 at 12:42:39: PID 74601,
  path `/private/tmp/cascade-development-derived/Build/Products/Debug/Cascade.app`.
  At 12:42:40 the volume control is `active` again, with no new
  permission request. Dismissal of the Smart Routing popup remains to be verified.
