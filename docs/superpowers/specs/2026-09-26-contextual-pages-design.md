# Pages, contextual selection and three activities

Date: 26 September 2026.

Status: specification under discussion. The decisions in section 2 come from the
user's explicit requests. The proposals in the following sections complete
the edge cases and do not yet form an approved execution specification.
No application implementation is part of this change.

## 1. Goal

Make personal widgets, Live Activities and the controls of the app in use accessible
through the same notch. The system chooses a primary by priority and
respects the user's selection. The activities stay reachable through bubbles
and horizontal navigation, without suddenly replacing an open page.

## 2. Decisions confirmed by the user

| ID | Decision | Constraint |
| --- | --- | --- |
| D1 | The open page is protected from automatic events. | New activities and priority changes do not abruptly change the content in use. |
| D2 | The notch presents up to three activities. | One primary and up to two bubbles, with the iPhone 18 Pro Dynamic Island as reference. |
| D3 | There is a customizable Page 0. | It is the base of the notch; activities push it into the background without removing it. |
| D4 | Page 0 is reachable by swiping from right to left. | Navigation must keep a predictable access to it. |
| D5 | The primary is chosen by priority or by the user. | If the user selects an activity in the open notch and closes it, the last one viewed becomes the compact primary. |
| D6 | An app's focus can make a contextual activity available. | Examples: Photoshop commands and a player's commands. |
| D7 | Central hover opens the primary. | The relationship between compact body and expanded content is kept. |
| D8 | Clicking a bubble opens the selected activity directly. | This indication replaces the previous proposal of opening the bubble on hover. |
| D9 | Sliding on the bubbles rotates the compact activities. | The incoming bubble visually merges with the notch and becomes primary; the others reposition. |
| D10 | A new recording takes precedence over music chosen manually. | With the notch closed the recording becomes primary and the music moves into a bubble. With the notch open D1 still applies. |

The previous proposal of always returning the primary to the automatic
selection after closing is superseded by D5.

## 3. Verified visual reference

Apple documents three simultaneous Live Activities on iPhone 18 Pro and the swipe to
move between activities. The general HIG documentation consulted still reports
the previous two-activity case; for the requested reference we use the model's
guide and the updated launch material.

- [Apple: Dynamic Island guide](https://support.apple.com/en-by/guide/iphone/iph28f50d10d/ios).
- [Apple: iPhone 18 Pro presentation, Dynamic Island section](https://www.apple.com/newsroom/2026/09/apple-debuts-iphone-18-pro-and-iphone-18-pro-max/).
- [Visual reference published by MacRumors](https://www.macrumors.com/2026/09/09/iphone-18-pro-features-smaller-dynamic-island/).
- [Image of the three activities observed in the browser](https://images.macrumors.com/t/15I1H8_5to6Md7Sle3RpeKoL3Qs%3D/400x0/article-new/2026/09/three-live-activities.jpg?lossy=).

The image shows a primary capsule with one bubble on the left and one on the right,
aligned horizontally. For Cascade we adapt this arrangement to the Mac's hardware
cut-out. The hardware stays fixed: the drawn surfaces and their
content move. The merging during rotation is a user requirement;
the static image does not show its curve or duration on iPhone.

Proposal for the compact states:

- No activity: resting outline; hover opens Page 0.
- One activity: primary around the notch, with content on the two usable sides.
- Two activities: primary and right bubble, keeping the current arrangement.
- Three activities: left bubble, primary, right bubble.

## 4. Pages and navigation: proposal

Page 0 keeps identity, arrangement and preferences across openings. Each activity
has an expanded destination identified by the session, independent of its
current position among primary and bubbles. Addons contribute widgets and
activities through the common contract.

To make the requested access to Page 0 literal, the proposal places the other
activities to the left of the primary and Page 0 immediately to the right:

    [altre attività] [principale all'apertura] [Pagina 0] [altre pagine personali]

From the primary, a right-to-left scroll of the content reveals
Page 0; the opposite gesture leads to the other activities. The page labels
stay stable even if the primary changes. The sequence is fixed
on opening, so it does not reorder under the pointer while the user is browsing.
Accessible controls to change page are also available.

A new activity updates the available set; the new arrangement is
applied on close/reopen. The end of the displayed session
immediately makes its commands inert. A brief
"Activity ended" surface is proposed, kept until navigation or closing, avoiding an
automatic page change while the pointer is about to press a command.

Proposed interpretation of D2: three is the number of activities visible in the compact state.
Any further valid sessions stay reachable among the pages;
the runtime's admission limit is not implicitly reduced to three.

Visiting Page 0 does not turn it into a Live Activity and does not end the activities
in progress. It is proposed that closing from Page 0 keeps the last activity
explicitly viewed in that opening, if still valid; if there is none,
it keeps the previous primary. Example: primary A, visit to B,
visit to Page 0, close: the new primary is B.

## 5. Automatic and manual selection

The selection keeps separate:

- the compact primary;
- the open destination;
- any activity explicitly chosen by the user;
- the activities ordered by priority;
- the navigation sequence of the current browsing.

A mere hover over the primary does not constitute a new manual preference.
A click on the bubble or an explicit navigation selects the destination; on
closing, the last activity viewed becomes primary. A completed slide
in the compact state sets the new primary right away without requiring an opening.

The manual reference concerns the session: ending, revocation or permanent
removal invalidate it. A content revision keeps the identity and does not
cancel the choice. It is proposed that forced closings due to screen lock, stop or
display disconnection do not turn an automatic opening into a preference.

### Decision: new recording after a manual choice

Scenario: the user chooses Music, closes the notch and then starts a recording.

The user chose precedence for the new event: the recording becomes
primary and Music moves into the side bubble. The alternative that
kept Music primary until the end of its session is discarded.

The proposed general rule is: a new session with a higher priority overrides
the previous manual choice when the notch is closed. Ordinary updates,
track changes and republications of the same session are not new events.
The user can select Music again after the recording arrives:
the choice holds until the next event that satisfies the rule.

If the recording starts with the notch open, D1 protects the current page.
To complete the behavior, it is proposed to apply the precedence
on closing, unless a new manual selection is made after the activity
arrives. Merely staying on the page does not count as a new choice.

The initial automatic order stays a proposal: recording/sharing,
call, commands of the focused app, media and other activities. The precedence between
simultaneous recording and call is still to be agreed. On equal priority
the previous order is kept to avoid oscillation. Addons declare
their own context; the host assigns the final precedence.

## 6. Click, slide and animation: proposal

It is proposed to support both horizontal dragging of the bubble with the
pointer and horizontal trackpad scrolling over the compact area.
Both go through the same gesture recognition; the thresholds are tuned
on the interaction prototype, without intercepting scrolling outside the notch.

The click is recognized on release if the movement does not exceed the gesture
threshold. A recognized slide cancels the click and the opening hover for the whole
rotation, including the pointer passing over the central zone.

The selected bubble approaches the body, creates a brief liquid bridge and
flows into it. The outgoing primary becomes a bubble; the third activity completes
the rotation. The opposite gesture reverses the direction. The logical position is
confirmed when the gesture completes; a cancelled gesture returns to the previous
arrangement. After the gesture a new entry into the central zone is required to
open, so the slide does not cause an unintended opening.

A session revoked during the movement cannot become active again when the
animation completes. Reduce Motion keeps the result with a minimal transition.
Geometry, mask and clickable zones follow the same position. No animation
timer stays active once the transition has finished.

In the open notch, page scrolling must leave to the inner controls
the gestures started on sliders and other interactive surfaces. The compact rotation
and the expanded navigation share the identities, but have distinct gestures.

## 7. Contextual app activities: proposal

Focus makes a surface declared by the integration eligible:
Photoshop can offer quick tools, a player the commands for the content in use.
The mere presence of an installed app, or of one open in the background, does not activate it.

The contextual surfaces take part in the same selection and, as a proposal,
in the same limit of three compact positions. They do not constitute a fourth bubble.
Their eligibility depends on the context, while a call or recording
keeps existing even if the app loses focus.

During browsing the surface keeps its own source app.
The notch must not steal its focus. If the target changes or disappears, the commands
are not redirected to the new app: they stay valid only if the integration
can address them to and verify them on the original target; otherwise they are disabled.
The next context applies to the next browsing.

Detection and control capabilities stay separate verifications for
system recording, Meet, FaceTime, Discord and each new integration.
Microphone/camera use, call identity and mute state are not equivalent.

## 8. Integration into the current structure

- `LiveActivityHost` keeps sessions, expiries and lifecycle. The current selection
  exposes primary/secondary and an expanded destination; three
  compact positions and a manual choice independent of priority will be needed.
  Today only one activity per `sourceID` is admitted into the compact state: handling
  two distinct sessions of the same app remains to be defined, without confusing it
  with the limit of three visible positions.
- `WidgetHost` and `NotchScreen` already contain the widgets' arrangement and identity.
  Real navigation is needed, persistence of Page 0 and suspension of only the
  views that leave the page, without duplicating the instances.
- `NotchDisplayCoordinator` keeps a single open notch and distributes the
  same identities across displays according to the existing preferences.
  Currently `reconcilePresentations()` realigns the view opened on hover to the
  current primary: this behavior must give way to the
  destination chosen once on opening and then kept until explicit navigation
  or the end of the session.
- `NotchController`, geometries and renderer handle both bubbles and the
  click/slide recognition. The merging during rotation requires a dedicated
  transition: today identity changes go through the base outline.
- `AddonPresentationBridge` receives context and capabilities validated by the host.
  Internal and external widgets keep using the same contracts.
- The focus monitor already has the external app's PID and bundle ID, but the
  window contract publishes only the rectangle. That path is extended
  to keep the command target, avoiding a second monitor.

The choice is recomputed on the relevant events, outside the animation loop.
Hidden views release resources; a hidden page does not end the session.

## 9. Proposed sequence for the next execution plan

1. Confirm navigation, the interpretation of the visual limit and the settings
   proposal. D10 closes the case of a recording after Music chosen manually.
2. Define and verify selection, page identity and returns on closing.
3. Add the persistent Page 0 and navigation between surfaces.
4. Extend the compact state to three activities, bubble clicks and rotation with merging.
5. Connect the activities of focused apps and verify the real adapters.

Acceptance scenarios: no activity; music; recording plus music;
recording plus call plus music; a fourth activity; a new session during
browsing; manual choice and reopening; visit to Page 0; end of the
selected session; focus change; cancelled slide; revocation during animation;
conflict with the music slider; Reduce Motion; lock, wake and multiple displays.

## 10. Settings: proposal to discuss

### Structure

The current settings use a sidebar with `Appearance`, `Dev` and
`Widget`, grouped SwiftUI forms and cross-cutting search. A single
new destination and a reorganization of the existing content are proposed:

| Page | Content |
| --- | --- |
| Appearance | Geometry, style and screens, haptics and privacy that already exist. |
| Pages and widgets | Replaces Widget: Page 0, other personal pages and the widget arrangement. |
| Activities | Priority, visible activities, integrations and commands tied to the focused app. |
| Dev | Existing technical previews and version. |

The Bluetooth, volume and charging notices stay in a distinct "Notices" group
in the Activities page; they do not enter the Live Activities ranking.
The Spotlight control keeps a "Search" group. Music and the visualizer
move into the Music detail. Each preference has a single location,
also reachable from search.

### Pages and widgets

A list of pages sits beside the preview of the selected page. Page 0 is
always available and cannot be deleted. The user can add, remove,
move and resize their widgets using the supported sizes.
The editor also lets the user create, rename and reorder other personal pages;
the activity surfaces stay managed by their context.

"Add widget…" shows those actually provided by the available
integrations, with name and source app. Editing the grid happens in an
explicit "Customize" mode with a "Done" button; moves and sizes
are also available from the keyboard. Occupied or off-grid positions do not
overwrite other widgets: an invalid drop returns to the initial position.

Empty page: preview with "Add your first widget". A widget whose
addon is temporarily unavailable keeps its place with an indication of the
source, without losing the saved arrangement.

### Activities: behavior and priority

- **Visible activities:** choice of 1, 2 or 3, default 3. It concerns the compact state;
  the excess activities stay viewable in the pages. This option depends
  on the confirmation of the interpretation of the visual limit in section 4.
- **Priority order:** reorderable list of activity types. Initial
  proposal: recording/sharing, calls, app in use, music, other
  activities. The chosen order is used for new automatic selections; the names
  replace numeric scores exposed to the user.
- A stable description explains: "The last chosen activity stays primary
  until one with a higher priority starts. The open page stays unchanged".
- **Restore default priorities:** acts only on the order, without resetting
  pages, integrations or screen preferences.

The default value respects D10. An explicit reordering in the settings is
a customization of the automatic order, not an unintended change
caused by addon updates. The protection of the open page stays
a stable rule, with no switch to disable it.

These proposed customizations have explicit effects: choosing a single
visible activity, the music moves into the pages instead of into a bubble; placing
Music above Recording, a new recording does not override it automatically.
The preview and the text next to the controls must show this. The possibility of
altering the default behavior in this way is part of the settings
proposal and is not attributed to the confirmation of D10.

### App integrations and commands

A list shows each integration with name, switch and relevant state:
disabled, available without a current session, active or permission missing.
The absence of a call does not make the call configuration unavailable.
The detail contains only the source-specific options, the permissions
needed and the actions actually supported.

In the "Apps in use" group the associations are readable rows, for example:

    Photoshop → Comandi rapidi        Attiva
    Player → Controlli riproduzione   Attiva

"Active" is a state of the association, not a second switch. The row opens
the configuration; the activation stays the single one of the integration.

"Add app…" lets the user associate an app with a compatible contextual widget.
The detail lets the user choose and order the commands offered by the integration.
Focus makes the surface eligible; the priority order decides whether it will be
primary or secondary. Choosing an app does not invent an integration: if no
compatible widget exists this is indicated, without showing fake controls.

For the first version a single activation per integration is proposed, without
separate switches for page, bubble and automatic promotion. The priority
order stays common; any per-app exceptions will require a
concrete case before introducing a second level of rules.

### Preview, gestures and applying changes

The Activities page includes a small interactive preview with demo data:
music; recording plus music; three activities; commands of the app in use. It shows
how primary and bubbles change when the priorities are reordered. The
"Simulate new recording" button also verifies the D10 case without starting real
recordings or sending commands to apps.

A legend illustrates central hover, bubble clicks, slide and access to Page 0.
The gestures keep a single mapping; haptics and reduced motion follow the
existing preferences and the system ones. No numeric
spring or speed adjustments are added to the Activities page.

Ordinary settings are saved automatically and update the preview.
Order and arrangement reach the notch at the next compact state, keeping
the protection of the open page. Disabling an integration immediately revokes
its commands and content, according to the handling of an ended session.
Content and priority choices are global; style and calibration stay
per display, and the activity destination uses the existing routing.

Search must also find pages, widgets, apps and detail options, and
open the relevant control. An empty list of integrations or associations
explains how to add available content. A missing permission offers
the specific action next to the affected source.
