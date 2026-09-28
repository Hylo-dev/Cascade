# Route the shelf as a contextual page and the notch pulse

ID: 83
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 79, 80

## Question

Implement task 7 of the [file shelf plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md) using the page registry and the shared renderer according to the [approved shelf spec](../../../docs/superpowers/specs/2026-09-26-file-shelf-design.md). The general precedence among activities, pages and contexts remains a separate decision; this task applies only the shelf behavior already approved. Acceptance: an occupied shelf as the default, manual choice preserved, a canceled drag restores the page, the last delivered file brings back the ordinary selection, a single open notch, a double impulse once per drag, correct hit testing and focus with Spotlight/display/lock. Routing tests and regressions; native Spotlight test with text present, root review and commit. No keepalive timer or fake infinite deadline.
