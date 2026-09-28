# Make the shelf the main page and simplify its cards

ID: 92
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 89

## Question

Explicit revision of 27 September: treat the shelf as a live activity. While occupied it is the main page, but it **does not force the notch open**. Dimensions within the standard notch and the Music reference; use the upper side space while leaving the physical center free. Impeccable and Taste guide the native design, with restrained glows and the notch color.

The drop shows a large central icon and a centered title below it. After a successful addition the first file appears in the center, slides to the left and opens the fan of at most four icons with no background. A click or a two-finger scroll spreads the deck into a **horizontal** list: the Convert/Clear buttons disappear and an arrow leads back to the deck view. Convert and Clear stay overlaid in the deck view; the originals are not deleted.

Acceptance: no permanent opening on restore; reopening on the shelf while occupied; ordinary return only on clearing. Layout within the standard size, excluding the cut-out, a name under each icon, interrupted/canceled transitions handled safely and a Reduce Motion alternative. Keep the outgoing drag and accessible controls. Tests, root review, signed build and restart; distinguish rendered previews from a real Finder test. The fix for the fast drag before the animation is tracked in ticket 91. No early activation of Convert and no change to the launcher.

This request replaces the earlier permanent opening and the buttons in the list. The following verifications describe the earlier build; they do not qualify the new design.

## Progress: implementation verified, manual test pending

The app/renderer part was reviewed by the root: seven app tests and one renderer test passed. The final integration is in `5d852e7`; the root review of the twelve code files and the fixes for asynchronous ownership, the page cache and the preview are concluded. Independent signed app tests 7/7 (`root-shelf-clear-app-tests.log`), SwiftPM suite 1,443/1,443 (`root-receiver-persistent-tests.log`) and signed build exit 0 (`root-receiver-persistent-build.log`). The tests verify that Clear preserves the originals; the manifest keeps one entry after the restart at PID 74874. The CUA screenshot of the transparent receiving window does not prove the shelf's rendering: main page, Clear, cards and animations await the user's manual confirmation on the final build. Ticket open/unassigned for native QA, separate from the [incoming drag regression](91-file-shelf-native-drop-regression.md).

## Redesign: 27 September

Implemented in `48e682c`, with the root's review and fixes. Standard size 440×144 pt, content 400×124 pt; a priority page that can still be closed, native glow, centered drop, two-phase entry and a horizontal row with a back arrow. Renderer previews examined, including overflow and Reduce Motion; final tests 1,447/1,447 and app 9/9, signed build and restart at PID 97319 verified. [Verification details and limits](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md). Permanent rules in PRODUCT.md. The test in the physical notch remains pending because of the CUA limit and the ticket stays open/unassigned.

## Fan and preview refinement: 27 September

Overlapping Finder icons with a 16 pt step and rotations of +4/−4/−8/−12°. The opening gesture stores the inverse direction; the return performs the same action as the arrow. Horizontal scrolling pages back to the beginning before closing again; momentum and the tail of the previous gesture do not navigate. Native preview `FileShelfDesignPreview.swift`, "Shelf" Canvas, in-memory data only and controls for 0/1/4/8 files, entry and Reduce Motion.

Root review and fixes completed: shared routing, Swift isolation of the pure types, compilation of the preview body and contrast on the dark background. Renderer tests 8/8 and app 12/12; signed build succeeded and restart verified at PID 5063. The preview compiles, but the Canvas was not run: Xcode requires the initial installation of the system components. Physical trackpad test pending; ticket open for native QA. [Detailed verification](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).

## Interactions and colored actions: 27 September

New request implemented: first file at 1.75°, larger native icons (68 pt in the deck, 60 pt in the list), no name in the deck and +N below. The texts "convert", "rename", "clear" on the right in blue/orange/red with glows; in the list they gather as icons in the upper right shoulder, replacing the earlier decision to hide them. The notch stays within the standard sizes.

Horizontal scroll in focus steps; click to toggle and Shift for ranges, arrows/Shift+arrows and Cmd+A in the visible page. Delete removes the selected files or the focused file, preserving the originals; a fragment dissolve, including the last file, with a Reduce Motion alternative. Keyboard focus is acquired only by interacting with the files and is kept by a stable container until leaving the shelf.

Drag from the deck: all files, even beyond the first twelve entries. From the list: the selected ones; dragging an unselected entry selects it before the drag. No removal on a mere start/cancellation of the drag: the runtime receipts remove only the files copied successfully. The user's explicit answer authorizes "rename" on the Finder original too: single rename, collisions without overwriting, bookmark and name updated, rollback before the commit if the save fails.

Root review with fixes for clipping, native focus, selection updated on drag, pagination, metadata with an unchanged ID and the duration of the final dissolve. SwiftPM suite 1,452/1,452 and app tests 17/17 passed; previews updated and verified. Final build/restart and limits in the [runtime verification](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md). The ticket stays open for physical QA in the notch.
