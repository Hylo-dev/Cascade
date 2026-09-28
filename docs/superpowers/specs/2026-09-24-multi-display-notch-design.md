# Notch on multiple displays: specification for the plan

Date: 24 September 2026. Status: requirements received on 24 September; implementation of the plan authorized on 25 September. The proposed choices stay identified as reversible initial settings.

## Required result

Cascade keeps a compact presence on the top edge of every connected display. Focus decides where to show the Live Activities only when the user chooses that mode; it does not decide where the notch exists. Only one surface can be open at a time.

Explicit user requirements:

- On displays without a hardware notch, **Notch** and **Dynamic Island** are available.
- At rest both are a small bump from the top edge.
- Without a Live Activity, Dynamic Island expands as a droplet.
- During a Live Activity the same elements and interactions as the hardware notch are kept, with a smaller central space.
- The "shadow", that is the closed silhouette, stays on all screens regardless of focus.
- The notch can be open on only one screen at a time.
- Live Activities can be repeated on all displays, follow focus or always appear only on one chosen display.
- **Confirmed clarification:** focus of the active window; pointer only as a fallback.

## Surface behavior

| Display/state | At rest without activity | Compact activity | Expansion |
| --- | --- | --- | --- |
| With hardware notch | Silhouette aligned to the cut-out and to the existing calibration | Current layout, central space tied to the cut-out | Current behavior |
| Without hardware, Notch | Small bump anchored to the edge | Current layout with a reduced central separation | Panel connected to the edge |
| Without hardware, Dynamic Island | Small bump anchored to the edge | Same elements and reduced separation as the software Notch | Without a Live Activity: rounded body below the edge, connected through a droplet neck; with a Live Activity: the activity expansion already provided by the renderer |

"Always" refers to the desktop displays while Cascade is running in the unlocked session. The current exclusion from the lock screen is kept. Fullscreen and Space changes must not remove the silhouettes; Mission Control can close the expanded surface without removing the compact presence.

The resting geometry, the footprint of the compact content and the reserve for the hardware cut-out become distinct measurements. A low bump must not make the activities' icons and text unreadable. `hardwareNotchWidth` must no longer receive a software width on a display without a cut-out.

## Live Activity routing

| Mode | Compact destinations | If focus changes |
| --- | --- | --- |
| All screens | All connected displays | No move |
| Follow focus | Display of the active window; pointer fallback, then the main display | Only the activity content changes; the silhouettes stay |
| Specific screen | Only the display chosen through a persistent identity | No move |

Replicated content has the same identity, revision, priority, expiry and privacy state. The views can adapt to the local dimensions, but they do not become independent activities. Closing/dismissing the activity with its command acts on all the copies; closing the panel again does not end the activity.

An activity expanded on one display does not remove the compact copies from the other destination displays. Two activities keep the current arrangement: the primary and the secondary's satellite; the satellite stays compact if the other surface is open.

## Opening and moving between displays

- Hover, click and accessible action request opening on the display that received them, even if application focus is elsewhere.
- The request on B makes A close and opens B only when A has reached the closed state. No frame with two expanded surfaces. With Reduce Motion the move is immediate.
- During the move the silhouettes of both screens stay visible. Further requests update the destination: the last one that is still valid wins.
- A mere change of active window does not transfer an open panel, settings, popovers or a drag in progress.
- An interaction in progress with a control, a popover, the settings or Spotlight holds the opening owner; a concurrent request stays pending only while its trigger is valid.
- If the open display is disconnected, the panel, views and interactions of that display are removed immediately. The others stay compact; no automatic opening elsewhere.

## Proposed choices, distinct from the confirmed requirements

These choices make the plan executable and can be changed during review:

1. **Style for displays without hardware**, remembered through the UUID. Default: Notch. It also applies to a built-in display without a cut-out, not only to external ones. If the UUID is not available, the choice stays usable for the current connection through the runtime ID, without persistent saving; it is cleared on disconnection or when Cascade stops, and the row explains this exception.
2. **Live Activities default: Follow focus.** The setting is global for activities, not different for each provider.
3. **Fixed display absent:** no copy on other screens; keep the choice and resume on the display when it reconnects. The silhouettes and the widgets stay available everywhere. This is the literal interpretation of "always and only".
4. **Opening on a display excluded from routing:** shows the widgets, without bringing the Live Activity there. In Follow focus mode an activity that is already open stays viewable until it closes, even if the compact copy moves to the new active display. In fixed mode this exception is not granted on other displays. An explicit preference change that excludes the open display closes the activity first.
5. **Transient notices:** they keep their semantics and appear only on the active display; they are not replicated by the Live Activities setting. Suppress notices during any expansion and screen lock as today, without replaying them afterwards. A notice that is already visible can follow focus while keeping its original expiry.
6. **Initial measurements to verify visually:** software bump 96 × 8 pt; compact activity height 32 pt; software central space 24 pt; wings with the current measurements/insets. The resting bump and the active body have independent dimensions. No new slider in this tranche.
7. **Droplet:** the body stays connected to the bump through a neck while opening; it is not a permanently floating capsule. Initial profile: neck 12 pt and body 8 pt below the bump, expanded content dimensions already limited by the renderer. Calibrate these values in the visual verification without altering the contract.

## Focus and display identity

Observe the focused window of the frontmost app, including window changes and moving the same window between displays. Use the display with the largest intersection area with the window. On a tie keep the previous one if it is still a candidate, then use a stable ordering of the displays.

Normalize Accessibility and AppKit coordinates explicitly, also for displays to the left of or above the main one. If the window is not available, Accessibility permissions are missing or the app does not respond, use the pointer; if that does not identify a display either, use the main one. An error does not leave the old focus valid. Read again on a real change of the inputs, with no polling or AX calls in the mouse/animation path.

Use snapshots and notifications. AX reads happen on a worker with timeouts and generations, following the model already present in the Spotlight integration. Late callbacks from previous apps/windows are discarded. No new Screen Recording permission is needed; the fallback stays operational without Accessibility.

The nonactivating panel must not become a source of focus. Cascade's settings and auxiliary surfaces keep the anchor of the display on which they were opened.

Persistent identity: reuse the UUID resolution already used by `NotchSizePreferences`. The numeric CoreGraphics ID stays a key of the current session. An unavailable UUID must not be invented or replaced with the monitor's name: that display works in the session but is not offered as a persistent destination. Mirrored displays produce a single surface per logical desktop, already repeated by the system on the physical screens.

## Chosen architecture

Approaches considered:

- **Recommended: one coordinator, one surface per display, one shared activity host.** It reuses panel, view, springs and controller, making the controller local to a display. It requires separating content selection from its visibility.
- A full engine per display: fewer initial changes, but it duplicates expiries, activations, contexts and notices. Incompatible with the current provider lifecycle.
- Passive silhouettes on all displays and a single moving panel: enough for the resting state, but replicating activities would still force a second rendering and interaction path.

`NotchEngine` stays the public facade. A `NotchDisplayCoordinator` owns inventory, focus, preferences, activity host, widget host and exclusive opening. Each `NotchController` owns only the panel, view, geometry, animation and interaction state of its display. No local controller decides to stop shared providers.

`LiveActivityHost` keeps a single collection and a single expiry. It publishes the compact live selection, the notice and the activity chosen for expansion separately. The coordinator determines which views are actually visible and hands the host the union of the visible identities: `activate` once at the first presentation, `suspend` once after the last. The factories produce distinct views for each surface.

Keep the SDKs and the provider protocols; no addon runtime per monitor. Explicitly verify `SnapshotActivity` and `MediaLiveActivity`, which today hold a single activation context.

## Constraints and acceptance

- macOS 14 minimum; Swift 6; AppKit/Core Animation for panels and morph, SwiftUI for content.
- No new dependency or private API for this feature.
- A single global mouse monitor; no polling of focus or displays.
- The display links stop at stable geometry. Focus updates do not recreate panels.
- Privacy and accessibility applied to every copy before the sensitive factories.
- Existing hardware calibrations preserved; old software calibrations must not prevent the new small bump. With the fixed software measurements of this tranche, the calibration command is available only for a display with a hardware notch; the previous data stays preserved.
- Verify multiple displays, different scales, negative coordinates, mirroring, connection/disconnection, lid closing, lock/unlock and Reduce Motion.
- End of implementation: relevant tests, build with `scripts/build-development.sh`, update of the `/Applications/Cascade.app` link, relaunch and verification of the process.

Associated plan: [multi-display implementation](../plans/2026-09-24-multi-display-notch.md).
