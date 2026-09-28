# Define file collection and lifetime on the shelf

ID: 10
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: none

## Question

The shelf appears during the drag and captures files only on the drop onto the notch, as confirmed by the user: which drag events present it, and how does the notch return to the previous screen? Clarify references versus copies, persistence after restart, moved or removed files, promised files, cloud items, duplicates, space limits and removal from the shelf. No move or deletion of the original file must be inferred from the expression "keeps aside" alone.

## Answer

The [approved spec](../../../docs/superpowers/specs/2026-09-26-file-shelf-design.md) records the user's confirmation "exactly, go on" and the choices F1–F11: the file drag presents the notch and captures only on a valid drop; cancellation returns to the previous page; an occupied shelf stays the default page without erasing the manual choice. The originals stay where they are, with persistent references; promises and results are persistent managed copies. Missing files, cloud files not materialized or lost permissions remain visible as unavailable, relinkable or removable. Distinct identities for files with the same name and deduplication of the same original; space limits and quotas that already exist. Delivery is per item: only a verified copy allows removing the entry; a voluntary removal of the only managed copy requires confirmation. The [execution plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md) makes these boundaries verifiable in tasks 2, 3 and 7. The general precedence between contexts and Spotlight stays open in [Decide priority between activities, pages and context](08-context-arbitration.md), which blocks only the contextual routing, not the shelf's retention decision.
