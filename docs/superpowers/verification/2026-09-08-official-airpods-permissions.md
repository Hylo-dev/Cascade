# Apple assets and identity of the volume control

## Implementation outcome

Completely replaced the generated models with the official local resources:

- `/System/Library/PrivateFrameworks/CoreBluetoothUI.framework/Versions/A/Resources/AssetPaths*.plist`
- `/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources/Banner-PID-*-mov/`

The twelve verified PIDs are `2002`, `200F`, `200E`, `2013`, `2014`, `2024`,
`2019`, `201B`, `2027`, `200A`, `201F`, `202D`: AirPods 1/2/3/4, ANC variants,
Pro and Max. The aliases correspond to identical images in the Apple catalog;
a model is not arbitrarily attributed to a device without an identity.
`productID` and `colorID` go through monitor, reducer and view. Future PIDs
recognized by the catalog can resolve without new assets in the bundle.

Removed the two procedural atlases and the procedural generator. No Apple file is
copied into the product or into persistent caches. Decode in the background, at most
48 frames of 96 px, a single three-second loop, with fallback to the
official image and then to the appropriate symbol. Transparency verified in the nine base
movies. The full test measured 0.179 seconds for the decoding.

## Volume: evidence and fix

Before the change, Cascade PID 65994 was ad hoc signed with a requirement
based on cdhash. The copy registered by Xcode was also ad hoc, with a different hash.
The process received `false` for Accessibility and had no volume tap
registered, while the settings panel showed Cascade as on.
The last path present in the selector of the panel was
`/private/tmp/cascade-notch-derived/Build/Products/Debug/`, an old build.
The TCC database was not read or modified directly.

With keychain access outside the sandbox, a valid Apple Development certificate
was found. The previous check inside the sandbox did not make it
visible: it was not proof of its absence from the Mac. The app Debug target now
uses the team of the available certificate; `scripts/build-development.sh`
compiles and verifies the signature without resorting to an ad hoc identity. The external
check confirms the Apple chain and the stable requirement.

The second problem was the refresh tied to `onAppear` of MenuBarExtra or
to the activation of the app: an accessory app may not activate when the menu
opens. `VolumeAccessibilityObserver` observes the change signal of the
permission and the return from Settings. The requests are coalesced with
a single delay per event, without polling. The worker rechecks the authorization
even for an active tap and removes it if revoked. An explicit command
to recheck the permission is also available in the menu.

## Verification

- Debug build with Apple Development signature and full verification succeeded:
  `/private/tmp/cascade-official-assets-build.log`.
- Final bundle free of the two procedural atlases (removal verified in the log).
- 42 volume checks: `/private/tmp/cascade-permission-volume-tests.log`.
  The test with the menu not mounted fails when the permission observer is disabled,
  then passes with the fix (`cascade-permission-observer-red.log`).
- Bluetooth metadata harness and 13 policy checks passed:
  `/private/tmp/cascade-official-metadata-tests.log`.
- Full graphics test passed: `/private/tmp/cascade-official-presentation-tests.log`.
- Gallery of the twelve PIDs and real factories:
  `/private/tmp/cascade-bluetooth-presentation/official-airpods-library.png`,
  `/private/tmp/cascade-bluetooth-presentation/notices.png`.

The process of the first Apple Development build (66929) still received
Accessibility denied. The reassociation of the consent to the exact build
`/private/tmp/cascade-development-derived/Build/Products/Debug/Cascade.app`
was completed after the explicit approval of the user, as reported
below. FineTune remains open and its settings were not modified.

Primary references:
[Apple on signing requirements](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html),
[Apple DTS on ad hoc identity and permissions](https://developer.apple.com/forums/thread/819406),
[FineTune: Accessibility observation](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Coordination/AccessibilityPermissionService.swift).

## Conclusive diagnosis of the stale consent

The direct comparison identified the exact requirement saved by TCC:
`cdhash H"a780b3101d2122207ece5987bda5a75df753a19b"`. It corresponds to the signature of the
old `/private/tmp/cascade-notch-derived/Build/Products/Debug/Cascade.app`.
The TCC log explicitly reports `Failed to match existing code requirement`
for `hylo.Cascade` and `kTCCServiceAccessibility`, comparing that cdhash with
the Apple Development requirement of the current build. Evidence saved in
`/private/tmp/cascade-stale-permission-proof.log`.

The mere enabled entry in the panel did not correct the stale binary
requirement. The first request for a targeted reset had been rejected by the automatic
review for lack of a specific authorization; consent was therefore
requested from the user, who replied "ok".

After that approval, `tccutil reset Accessibility hylo.Cascade` succeeded
(`Successfully reset Accessibility approval status for hylo.Cascade`). Through
the system panel the signed bundle was added from the exact path.
No direct change to the TCC database or to the permissions of the other applications.

At 11:42:02 on 2026-09-08 the already running process, PID 68672,
logged `Volume routing status: active`, without recompilation or relaunch.
`CGGetEventTapList` confirmed its enabled HID tap (`location=0`,
`options=0`, `mask=16384`), before the taps of FineTune (PID 1411), which is also
still running. This verifies the recognition of the new consent and
the activation of the real filter, including the automatic refresh of the permission.

A physical press of F11 and F12 with the compact notch was requested from the user.
The user replied "si", confirming that only the Cascade notice
appears, with FineTune still open. The manual test of the hardware keys
therefore also confirms the effective override of the volume notice; this evidence
comes from the user and completes the automatic checks and those of the active tap.
