# Define the notch's monitors, focus and interactions

ID: 14
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 04, 07

## Question

On multiple displays, does Cascade follow the pointer, stay on a chosen display or show several notches? Agree on per-display profiles and on the behavior with scaling, resolution, menu bar, fullscreen, Spaces, Mission Control, lock, sleep and reconnection. Also define the transition between the focusless overlay, clickable widgets, drag and typeable search/settings: hit testing, outside clicks, Esc and restoring the previous focus.

## Answer

Decisions gathered in the conversation of 24–25 September: a permanent compact silhouette on every display, a single opening, Notch/Dynamic Island on displays without the hardware, the same Live Activity with a reduced software central space; distribution all/focus/fixed display. Focus of the active window, pointer only as a fallback, explicitly confirmed. The request of 25 September authorizes the map, the tickets and the execution of the plan.

The [spec](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md) records edge cases and reversible initial settings; the [plan](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) lays out implementation and verification. This closure records the decision; it does not declare the implementation or the multi-monitor qualification already complete. The existing keyboard, drag, Spaces and auxiliary focus behaviors are preserved and rechecked in the integration tests.
