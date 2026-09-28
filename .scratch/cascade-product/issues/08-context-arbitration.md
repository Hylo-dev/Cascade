# Decide priority between activities, pages and context

ID: 08
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 02, 07

## Question

When context, notification, hover, drag and manual choice ask for different content, which one wins and for how long? Decide suggestion versus automatic opening, preemption, a possible manual page lock, return to the previous page, timeout and handling of simultaneous events. Stress the scenario of music + timer + headphones connecting during a drag, and of a notification arriving while the user types in the search.

## Frontier after the surfaces: 20 September 2026

Claim taken after the surfaces ticket was resolved. Grilling and domain-modeling consulted from the sources indicated in the guide. The already approved activity contracts protect manual interaction from alerts, pick the most recent alert and discard those received during expansion/lock, without re-proposing them. No new choice on these rules is requested.

What remains to be clarified is the precedence between two manual intentions: an already open surface (page, activity or search) and dragging a file onto the notch. It is already required that the shelf appear during the drag and capture files only on release. The return after the drag and the interruption of the search are not yet defined.

Proposal to put to the user: dragging onto the notch temporarily shows the shelf; at the end the notch returns to the previous content, without letting an alert take over in the meantime. If Spotlight contains a search, keep it instead of closing it automatically; the shelf remains a temporary target in the notch. The feasibility of this native composition is not yet promised: after the choice, verification and a spec are needed before code. No new implementation or change to the launcher requirements.

Decision point presented to the user: a temporary shelf that keeps the search, or replacing the search with the shelf. The first option is recommended, subject to technical verification after the choice. Claim released while awaiting the answer; no new code or contract approved implicitly.

## Scope update: 26 September 2026

The [approved file shelf spec](../../../docs/superpowers/specs/2026-09-26-file-shelf-design.md) sets, for that shelf, the temporary target during the drag, the return to the previous destination if the drag is canceled, and keeping the Spotlight search's text and focus, to be verified natively. That part no longer requires this choice as a prerequisite of the task [Route the shelf as a contextual page and the notch pulse](83-file-workspace-routing.md). The general question between activities, pages, notifications and simultaneous contexts stays open; the general spec of the contextual pages is still under discussion. The technical verification with Spotlight has not been run and no native outcome is implied.
