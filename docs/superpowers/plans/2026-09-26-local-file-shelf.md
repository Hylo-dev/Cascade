# Local file shelf: first increment

**Authorization:** [approved specification, §9](../specs/2026-09-26-file-shelf-design.md#9-integration-into-cascade). For the local mounting of the shelf only, this plan replaces the addon gate prerequisite in the [original plan](2026-09-26-file-shelf.md). The external launcher, its native tickets and the quotas/grants stay unchanged. Conversion and its engine stay deferred until supervision, cancellation and recovery are ready; Convert must not appear available.

**Order:** [Local host](../../../.scratch/cascade-product/issues/87-file-shelf-local-host.md) → [page and drop](../../../.scratch/cascade-product/issues/88-file-shelf-local-routing.md) → [composition and output](../../../.scratch/cascade-product/issues/89-file-shelf-local-composition.md) → [verification and delivery](../../../.scratch/cascade-product/issues/90-file-shelf-local-delivery.md). Every increment requires focused tests and a root review; the last one runs the full suite, a signed build and a real relaunch.

## A. Local host and verified delivery

A single `FileWorkspaceHost` owns the persistent store and the admission discipline. It exposes paginated snapshots (12 entries by default, wire maximum 32), add of original URLs, remove and relink preserving the IDs. For output it prepares, for each entry, an opaque and immutable capability bound to the current generation; preparation neither opens nor retains the file. When the provider writes, it resolves and verifies the identity again, opens the controlled descriptor, copies with exclusive creation without overwrite and `fsync`, then records the receipt and removes the entry only after the copy has completed. Failure, refusal, cancellation and late receipts keep the entry. The original is never deleted.

## B. Contextual page and AppKit input

The engine offers a slot dedicated to the shelf, without simulating a Live Activity or falling back to the Music page. While it contains files, it is selected by default on opening; a manual choice stays until the next opening and is not overwritten by updates. `NSDraggingDestination` recognizes current files, produces a single heartbeat at the start of the drag and shows the target/deck; text, a cancelled drag and a stale pasteboard acquire nothing. Closing, a display change and the notch owner keep a single coherent state. Reduce Motion removes superfluous motion without losing the state feedback.

## C. App composition and outbound drag

The app facade connects host, engine and the already verified shared renderer: four cards +N, animated list and persistence visible after relaunch. The outbound drag uses native providers for the verified copy of each single item. Input accepts regular URLs; incoming file promises, not supported in the first increment, receive a clear refusal. Each successful delivery removes only its own entry; a partial drop leaves the others. The originals stay in their initial location. The UI explains why Convert is disabled until the supervised engine is complete.

## D. Final verification

The root reviews every commit and verifies focused tests and the full suite, real drags (Finder, a refusing destination, cancellation, partial batch), persistence/relaunch, occupied page and manual navigation, VoiceOver and Reduce Motion. It records the limits of the URL drag and of promises. After a successful signed build it updates `/Applications/Cascade.app`, quits and reopens Cascade and tests the updated process. The evidence qualifies neither the addon launcher nor the deferred conversion.
