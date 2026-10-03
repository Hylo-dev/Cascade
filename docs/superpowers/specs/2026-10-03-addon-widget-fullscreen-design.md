# Addon widget detail inside the notch

Date: 3 October 2026.
Status: the in-chat design was approved. This written specification is ready for
review; implementation and performance qualification have not started.

## Intent

An addon widget may opt into a secondary detail page that occupies the standard
expanded notch surface. The compact tile keeps frequent controls, such as a
slider; its separately actionable title or disclosure area opens less frequent
controls, information and settings. The supplied macOS Display screenshots are
interaction references, not a request to implement display controls.

Cascade supplies the page container, transition, Back control and restoration.
Addon authors supply bounded content and declared actions through the same public
SDK used by external addons. Fullscreen means the notch's existing expanded
footprint, with its physical cutout respected.

## Existing seams

- `AddonFeature` declares feature requirements and action identifiers.
- `Publication` and `PresentationSet` carry immutable content descriptions;
  `PresentationSet.expanded` already exists, but there is no shared widget detail
  route. `ContentDocument` bounds content and assets.
- `OperationRequest` currently supports service requests, schedules, lease
  release and publication termination. It has no options operation.
- `AddonRuntime.assignPublication` owns the publication-to-feature binding.
  `ActionAuthorizer` checks canonical owner, feature, current revision, action
  declaration, payload and eligibility.
- `AddonPresentationBridge`, `SnapshotWidget` and their action permits render
  host-owned snapshots without loading provider code.
- `NotchDisplayCoordinator` owns display selection and the underlying ordinary
  or contextual page. `NotchHostView` owns the native settings chrome.

This implements the common capability described by `ADDON-NOTCH-OPTIONS` in
`docs/TODO.md` and needed by the approved Audio specification. It does not execute
the Audio implementation plan or introduce an addon-specific host shortcut.

## Public SDK contract

Add `supportsFullscreen: Bool` to `AddonFeature`, with a default of `false` in
Swift initializers and when decoding an absent field. Encode the field only when
true so an unchanged feature remains compatible with older strict decoders.
Capability belongs to the feature bound by the host to the widget publication;
a provider-supplied feature name is not authority.

Introduce the common `notch.options.v1` capability and the protocol minor needed
to negotiate it, coordinated with the planned cumulative 1.5 contract. Advertise
the capability only when validation, runtime admission and host presentation are
connected. An addon using the flag requires that capability; older features with
the flag absent retain their current behavior. There is no new blanket system
permission: system operations inside the page retain their existing grants.

Extend `OperationRequest` with `presentOptions(AddonOptionsRequest)` and
`dismissOptions(UUID)`. `AddonOptionsRequest` contains the source publication ID,
observed publication revision, originating accepted action request ID, an opaque
options lease ID and a bounded `ContentDocument`. It contains no display ID,
window handle, arbitrary frame or executable view. The lease ID is an idempotency
key until the host accepts and canonically binds it; possession alone grants no
authority.

The compact widget publishes a normal declared action for its title or
disclosure hit area. Handling that accepted user action may return
`presentOptions` in `ProviderOutput.operations`. An SDK convenience constructs
the request from that action's identifiers, avoiding hand-written envelopes.
Authors may reuse a separately published `PresentationSet.expanded` document as
the request content. Native controls remain siblings of the opening hit area,
so dragging a slider does not open the page.

Detail controls use the same content primitives, action declarations, asset
resolution and broker clients as other addon content. New value-input and picker
primitives remain separate shared SDK work; this feature does not implement an
Audio mixer, Display controller or Caffeinate's individual options.

## Authority and data flow

1. The host records the exact source display and underlying page selection when
   accepting the visible widget's user action. That origin remains host-owned
   across asynchronous provider work.
2. The runtime checks the installed feature's flag, negotiated capability,
   canonical publication assignment, current revision, expiry, action admission
   and owner/generation. A publication refresh or startup event cannot open a
   detail page without that accepted user action.
3. The runtime validates and reserves the document and options state before
   retention or handoff. Every publication, imported asset and correlated action
   completion in the same batch must also prepare and validate before any
   presenter mutation; the subsequent canonical commit is nonthrowing and has no
   actor suspension. It issues a display-bound presentation lease containing
   only host-approved values. Revoked, hidden, redacted, stale or over-budget
   origins reject the request.
4. The generic presentation bridge renders the accepted detail. It rechecks the
   lease before installing it after any actor hop. A late response from an
   obsolete action cannot reopen or replace a page.
5. Detail actions are authorized against the current leased document and source
   publication, not only scanned from the compact publication. They retain the
   existing payload bounds, action deadlines and final-delivery revalidation.

Only one options lease is active across the notch presentation system, matching
the existing single expanded owner. The host retains one pending visible widget
action origin: the latest pending click wins and immediately revokes the earlier
origin. If A and then B are clicked before their replies, a delayed A reply is
ignored and only B may open detail. Detail covers the source grid, so a visible
detail has no competing source widget entry surface. Back revokes its origin;
neither delayed reply can reopen it. There is no origin queue or detail stack.
Automatic publications update valid content but never take navigation priority.

`presentOptions` with the same canonically active lease ID refreshes its document
in place, after owner, feature, generation, current publication revision and
budget checks. This update uses the existing lease authority; it cannot create a
new lease after Back or reopen a closed page. The host retains the original
accepted action binding for the lease lifetime. Repeating an opening command
does not extend its expiry. A source revision change immediately revokes old
detail action permits; the container retains its selection while awaiting a
valid replacement document for that revision, with unavailable controls disabled.
Lease lifetime never exceeds the source publication's currently valid lifetime.

Dismissed lease IDs remain charged replay tombstones until their exact canonical
owner/connection generation is invalidated. The shared runtime retains at most
256 bindings across all live connection generations, at 128 bytes each (32 KiB
total). Back refunds the detail document but retains its binding charge. An
owner/generation invalidation refunds only its matching bindings. At capacity,
new lease IDs fail closed with resource denial; history is never silently evicted.
Long-lived generations therefore permit at most 256 distinct leases collectively
until canonical invalidation refunds capacity.

## Container and navigation

The detail temporarily covers the visible ordinary widget grid within the owning
notch. The grid arrangement and ordinary selection remain unchanged. A dedicated
options overlay preserves an unselected contextual page such as the file shelf;
installing detail must not overwrite the legacy single contextual-page slot.
When the file shelf or an activity is selected, the source widget is hidden and
cannot authorize an opening. A selected-contextual origin and its restoration
are unreachable under this entry policy, rather than pending hardware evidence.
This feature adds no widget entry surface to those pages.

The header reserves the top center for the physical camera/sensor obstruction.
Back is a native `NSButton` with a left-facing filled triangle (`arrowtriangle.left.fill`),
matching the settings control's size, inset, tint, hover and pressed feedback.
It sits in the top-left shoulder at the mirrored position of settings on the
right. Cascade owns both controls; the document occupies the remaining content
area and cannot cover Back. The title comes from the detail's accessible label.

Back and Escape revoke the lease and restore the original ordinary selection on
the original display, with the contextual slot preserved. Closing the notch also
dismisses detail; the next ordinary opening shows
the retained underlying page. Withdrawal, expiry, disable, removal of the source
widget, loss of its grants or display removal revoke detail and visible resources.
If the saved page no longer exists, restore the normal widget page. Repeated
dismissal is harmless, and an old lease cannot dismiss its replacement.

Ordinary provider suspension or completion does not by itself discard a valid
host-owned publication. Connection/generation invalidation revokes dependent
options authority; retained compact content continues under the existing stale
publication policy. Quitting Cascade releases all options state. Detail resources
do not prolong unrelated activity or service subscriptions.

## Motion, accessibility and cost

Use the existing notch morph and native layer transition infrastructure. Lay out
the incoming and outgoing surfaces once, then animate transform and opacity for
a finite 180 ms transition; Back reverses the direction. Release the outgoing
host after completion. Do not drive SwiftUI state, layout, disk I/O or provider
work on each animation frame. Retargeting a rapid Back/open sequence cancels the
obsolete transition and keeps only the current incoming/outgoing hosts.

Reduce Motion uses a finite opacity-only transition. Reduce Transparency and
Increase Contrast follow the existing notch material and control fallbacks.
Back has an accessible label, tooltip and stable accessibility identifier;
keyboard navigation reaches it, and focus returns to the opening control when
that control still exists. Escape is consumed by the active options route before
ordinary page handling. Opening details must not activate another application.

Keep document limits at 128 nodes, depth 8, 64 KiB per document and the existing
aggregate presentation and retained-state budgets. Options documents and asset
references count against the owner's current budget. There is no periodic
options timer, polling source or new animation dependency. Closing, hiding or
revoking detail clears its hosting root and releases visible asset leases.

## Acceptance evidence

Before implementation, add failing checks for missing/false capability, old
manifest round trips, unknown wire fields, oversized documents, undeclared
actions, stale/replayed action requests and forged display or feature claims.
After implementation those checks must pass alongside existing decoding, action
authorization, publication accounting and display presentation suites.

Exercise title click, independent compact controls, Back, Escape, rapid retarget,
notch close/reopen, publication updates, withdrawal, expiry, disable, original-page
removal, competing pending visible clicks and display removal. Verify that late
replies and old controls cannot reopen or operate a revoked page. Cover ordinary
grid restoration on the original display and preservation of an unselected file
shelf slot. Verify that selected contextual and activity pages cannot mint hidden
widget origins.

Drive the real running app through the same scenario before and after: 30 seconds
idle, 20 detail open/Back cycles, 30 seconds with detail visible, then 30 seconds
closed. Report CPU, private resident memory, scheduled wakeups, transition/main
thread timing and retained hosts side by side. Acceptance requires no added
periodic options wakeups while idle or closed, no accumulating hosts/leases and
no main-thread blocking. Measurements remain pending until the app is driven.

Native previews may verify geometry, clipping and accessibility variants, but
they do not substitute for physical mouse/keyboard or multi-display evidence.
The managed addon launcher hold remains intact. A host fixture may qualify the
container and navigation while actual external activation remains separately
conditional; report the two results distinctly.

Finish code work with the canonical successful build, update the application
link, quit/relaunch Cascade and verify the intended executable and process.
