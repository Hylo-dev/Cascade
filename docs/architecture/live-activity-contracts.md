# Contracts for notch activities and notices

Design reference: [Apple HIG: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities), consulted on 8 September 2026.

The relevant guidelines are consistent compact/minimal/expanded presentations,
legibility, essential content, privacy, direct interactions, discreet
updates and task completion. Cascade applies these principles to its own
macOS overlay. The native Live Activities that Apple describes on Mac come
from iPhone; these protocols do not conform to ActivityKit.

## Plugins and these contracts

Cascade's notices and activities are moving to the [plugin engine](../superpowers/specs/2026-09-29-plugin-engine-design.md). The protocols below remain CascadeKit's internal host seams; plugins never conform to them. A plugin publishes a notice as data, its three regions plus `PluginNoticeAttributes` (duration, rim tint, compact width, accessibility sentence, show or update), and `PluginNotice` adapts each publication to `NotchTransientNotice`, so it follows every rule on this page.

The Bluetooth, charging and volume notices are already plugins. Music's activity is still the native `MediaLiveActivity` until the services and Music sub-project moves it, and plugin activities are not shown until that sub-project routes them. The file shelf's unsupported-file notice stays native, as part of a system surface. The visual, timing, privacy and accessibility rules described here hold for every path.

## Cascade contract choices

| Contract | Responsibility |
| --- | --- |
| `NotchActivity` | Session/source identity, revision, accessible label, privacy, destination, preferred sizes and compact/minimal factories. |
| `NotchLiveActivity` | Ongoing task, finite `lifetime`, relative relevance and an expanded factory reserved for activities. Published with `present(_:)`, ended with `endActivity(id:)`. |
| `NotchTransientNotice` | A single state change; explicit duration and publication with `showNotice(_:)`. It cannot become persistent because of a forgotten parameter. |
| `NotchActivityViewContext` | Chosen family, usable space in Mac points, indication of content that is not up to date. |
| `LiveActivityContext` | Invalidation of the visible presentation only. The provider stays independent of the view. |

Live Activities implement every factory, including `makeMinimalView`.
Notices do not expose `makeExpandedView`: the protocol reserves this factory
for ongoing activities. A notice uses both compact wings, temporarily
in place of the Live Activities, and the most recent one takes precedence.
`sourceID` groups what belongs to the same integration. With two distinct sources and no
notice, the primary one keeps the left compact content and closes the right wing.
The second one uses its own `makeCompactLeadingView` factory in a separate circle
on the right, with a diameter equal to the notch height and symmetric insets. Hover opens
the primary one; a click on the circle opens the second one with a droplet attachment to the
outline. Accessible activation uses the same path as the click. The minimal
factory remains part of the contract for the other presentations.

A revision changes only with the displayed data. The coordinator filters out
republications of the same instance/revision. Metadata and deadlines changed
while the view is suspended must still be republished through the engine.
Invalidations coming from an old context become inert.

The maximum duration of a session is eight hours and that of a notice ten seconds:
these are local Cascade policies. The Bluetooth notice uses four seconds.
The session limit is anchored to the first admission/start, whichever is earlier:
updating `startedAt` or the estimated end does not move the limit. A new task must be
published as a new session; an expired task is not renewed automatically.
The session can become stale before its expiry through `staleDate`; the
renderer signals it. A single cancellable deadline handles the whole collection.
A completed task disappears immediately even if expanded. A notice disappears when
hover begins: opening shows an available Live Activity or the widgets.
Notices received during expansion or while the screen is locked are
discarded and are not offered again on close or unlock.

Closing a panel releases its expanded views and reaches exactly
the base outline; on its own it does not suspend the shared provider. `LiveActivityHost`
activates each instance before the local factories and keeps it active as long as
at least one valid presentation exists, including the roots retained during a
transition. Suspension happens after the last presentation; completion,
expiry or revocation also invalidate the outgoing roots, without resurrecting the session.
On the first crossing of the base size, the next frame starts the compact
wings. The springs slightly overshoot the final size when opening; the fixed
canvas reserves space for the bounce. The display link stops after the transition.
A new hover can interrupt a normal close.

Replacing the primary or secondary identity always goes through the base outline
before building the new views. Events and hover during the close
update the destination of the next opening without bringing it forward. Revisions
of the same session do not repeat this sequence. Reduced motion
goes straight to the final state and also releases the droplet view.

After a click, the dwell area grows and tolerates a brief exit of the pointer.
Controls that open an external menu use `NotchPopoverPresenter`, registering
the interaction before the asynchronous requests and closing it in `dismantleNSView`.
The popover keeps its intrinsic size; the notch, the popover window and a
narrow corridor between the two keep the interaction open. Leaving completely
closes the menu after a short cancellable grace period, even with the pointer at rest.
No polling or global window searches are needed.

`privacy` must be declared explicitly. If it is `.sensitive`, the renderer uses
harmless content before even invoking the factories, unless consent is given in
the preferences. Accessible labels and destinations must respect this
choice too. The provider remains responsible for classifying the data correctly.

`contentURL`, when available, leads to the real details of the session and is
one and the same for both compact sides. The music preview does not invent a
destination to a player. The expanded height derives from the declared content and
is capped by the renderer; views respect `availableSize` and the insets.
The default sizes and the dark background belong to the engine, not to the providers.
The default expanded width is 408 points, with margins relative to the display;
the height includes space for the physical cut-out and the insets, up to 180 points. The engine
applies the dark theme even when macOS uses the light theme.
The curvature of the outline derives from Apple's `RoundedRectangle(.continuous)` path,
normalized and stored once. The same segments govern drawing,
mask and hit testing, with reflection for the upper concave attachments.

`compactPreferredSideWidth` lets a notice request the width of its wings
(116 points for volume and charging, 40 for Bluetooth); the renderer normalizes the request and limits it
to the display. The width is animated in points and the provider's getters are not
called on every frame. Hidden sensitive content does not affect
this dimension either.

## Multi-display presentation

`NotchEngine` exposes the facade of `NotchDisplayCoordinator`: a shared inventory,
event monitor, active-window monitor, `LiveActivityHost`
and `WidgetHost`. Each logical desktop has a stable controller and panel;
a focus change updates the projections without recreating the panels.
The compact outline exists even without activities. Mirroring is normalized
through the CoreGraphics topology, without inferring identity from the name or the frame.

The primary/secondary compact selection is independent of the expanded activity:
opening on A does not remove the compact copies or the satellite on B. The preferences
allow all displays, the active window (default) or a fixed display.
Focus uses the active window, then the pointer and finally the main display;
a window change within the same app is a useful event. AX coordinates are
converted before routing, outside the animation loop. A disconnected fixed
destination is not replaced: when the same UUID returns, only the publication
that is still valid reappears. Without a UUID the display takes part in all/focus,
but does not become a persistent fixed destination.

Only one surface gets the opening. The coordinator waits for the actual completion
of the previous close and verifies generation, trigger and presence of the
display before granting the most recent valid request. The mouse leaving
can cancel a pending hover without cancelling an earlier valid explicit
request. Outside routing, the widgets open. An activity that is already open
stays on its display if only the focus moves; an explicit change of the
preference that excludes that display closes it again.

Notices are brief state changes, not copies of Live Activities: they follow
only the active display, keeping the original expiry. Expansion, lock and
a Spotlight reservation prevent them from being queued for later
replay. Settings and auxiliary surfaces keep the invocation anchor;
a Settings window that is visible but not active does not by itself reserve the opening.
Popovers, dragging and native-surface reservations take part in the
same exclusivity. Locking invalidates pending requests before the application
cleanup; stop releases monitors, panels and shared presentations.

On displays without a physical cut-out, `SoftwareNotchMetrics` separates the resting
protrusion **96 × 8 pt**, the compact height **32 pt** and the central space **24 pt**.
The Notch and Dynamic Island styles can be selected per display; the second one
connects the body to the protrusion with a neck of **12 pt** and an offset of **8 pt**.
The body includes the offset's space without taking it away from the content. The exclusion space
of the hardware cut-out is zero on these displays.
The persistent choice uses the UUID; without a UUID it lasts only until disconnection/stop.
A style change waits for the close. Hardware calibrations stay in use,
while the old software measurements do not enlarge the protrusion; calibration
is available only for a hardware target. Drawing, mask and hit testing
use the same path, including in the Reduce Transparency variant.

The lifecycle counts actual instances and presentations, not one subscription per
monitor. The expiry belongs to the common host: `scheduleExpiration()` picks
the next deadline among stale/expiry and keeps a single cancellable `deadlineTask`.
This is a property of the source code, not a measurement of native scheduling.
The [verification record](../superpowers/verification/2026-09-24-multi-display-notch.md)
distinguishes the tests with synthetic inventories from the physical evidence and from the profiling
that has not been performed yet.

## Rules for module implementers

- Aggregate updates of the same session. Do not generate a new object
  for every frame, tick or identical system callback.
- Keep scans, network requests, decoding and framework callbacks out
  of the factories and the animation path; cross actors explicitly.
- Release the view's resources in `suspend()`. The visual music progress
  may update only while its expanded view is visible and playing.
- Expose a command to disable the integration. Removal by `sourceID`
  must delete both the active presentation and the pending items.
- Reserve the expanded controls for essential actions. Music exposes play/pause;
  the provider contract keeps the additional commands for other surfaces.
- Use legible symbols and text, accessible labels and information consistent
  across families. Bluetooth shows model/name on the left and status with a circular charge on the right,
  with truncation of the name and complete accessible text. An unknown charge stays
  unavailable; the minimum of the two earbuds is not replaced by the case.
- Do not add sounds or haptics to ordinary revisions, and do not duplicate the event
  through a second application notification.

## Adaptation boundaries

The local notch does not implement Lock Screen, StandBy, CarPlay, Apple Watch,
iPhone Mirroring or ActivityKit push. With the screen locked, the overlay hides.
The second activity can occupy a circle separate from the outline, with the same
mask and the same interaction limits as the renderer. Interactions use
hover, click, accessible activation and explicit macOS links. The aesthetic conformance of future content still requires
visual review; no protocol can by itself prevent promotional text or an
incorrect classification of the data.

The Bluetooth banner override remains a separate, selective service. These
contracts do not demonstrate its compatibility with the system Accessibility tree.
The return of the audio output to AirPods is distinct from a new ACL
connection: the CoreAudio listener generates a notice even if the link stayed connected,
with a silent baseline at launch and after wake. Bluetooth notices
show only model/symbol and ring, while name and status remain available
through accessibility and localized help. The remaining part of the ring is a dimmed
green with a thinner stroke than the charged arc.

Volume uses a 1.8-second notice: icon and text on the left, level indicator
and percentage on the right. The bar is an indicator, as in the reference
HUD, not a draggable control. CoreAudio observes the default output
without polling; a selective event tap replaces the volume keys only when it can
handle them. Missing Accessibility or fixed-level devices keep the
native behavior. The other macOS HUDs are not disabled globally.


Asynchronous updates of a notice already presented use `updateNotice`,
with the same identity/source and a strictly increasing revision. They keep
expiry and priority; they do not reinsert content after hover, expiry or close.
`showNotice` stays reserved for a new real event (for example another volume
step). Bluetooth also verifies the identity of the individual connection event
before updating, and arms the native override only once.

AirPods notices use the original videos of the Apple banners installed in macOS.
The CoreBluetoothUI catalog maps PID and color to the images and aliases;
BluetoothUIService provides the corresponding movie. Cascade reads the resources
at runtime, without copying them into the bundle. A worker decodes at most 48 images
of 96 pixels for a three-second loop. Reduced motion uses a static
frame; no player or timer remains after the view closes.
Metadata is read off the main actor on connection, with a single
retry, and results that were cancelled or belong to earlier connections are discarded.

The volume filter is recreated on wake and when the session returns. A tap
disabled by the system can attempt only one restore every five seconds,
only on an event and with valid Accessibility. Mute repeats are absorbed without
new writes or feedback. Returning to the app/menu retries a permission that was just
granted; neither FineTune's settings nor the macOS permissions are modified.

Accessibility changes are observed even with the menu closed; the
system signal is coalesced and followed by a real check of the permission.
Returning from Settings is an additional path, without polling.
The Debug build uses Apple Development: an ad hoc signature that differs on every build
offers no stable identity to which macOS can bind the consent.

Charging uses a four-second notice when switching from battery to the
power adapter. IOKit observes only the internal battery; percentage and Low Power
Mode update the existing notice without extending it. Launch and
wake establish a silent baseline. Unplugging closes the notice.
The text and the rounded full battery follow the reference: green in normal
mode, yellow with Low Power Mode, including the gradient under the edge.
The gradient is turned off with Reduce Transparency. Paused and completed charging
have distinct labels; an unknown percentage does not become a zero.
The menu lets you disable the integration and see both previews.

Compact mode uses SF in the macOS Callout style (12 pt, regular), as
defined in the [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography).
The [HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
call for margins concentric with the outline, without fixing a universal numeric padding
for a custom macOS notch. Cascade adapts them to its own
geometry: 12 pt toward the outer edge, 8 pt toward the cut-out and 6 pt vertically.
Minimal presentations use 12 pt on both sides. The engine subtracts the
insets before passing the space to the providers; icons and images also respect
the remaining width. The battery uses a height of 12 pt, symbols 14 pt and
Bluetooth rings at most 18 pt. Typography does not change with the notch height,
and any text reduction does not go below 10 pt.
