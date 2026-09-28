# Compose the local page and the per-item outgoing drag

ID: 89
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 87, 88

## Question

Run phase C of the [approved local plan](../../../docs/superpowers/plans/2026-09-26-local-file-shelf.md): connect the app facade, host, engine and shared renderer for a persistent four-card +N deck and animated list. Accept regular URLs as input and clearly refuse incoming promises in the first tranche. Outgoing native providers copy per item; remove only after individual success, preserving the originals and the undelivered entries. Convert stays disabled with an explanation, with no simulated capability. Targeted tests and real drags, root review and selective commit.

## Answer

Implemented in `e25e75c` and accepted after the root's review and fixes: app facade, shared renderer, regular URL input, visible refusal for unsupported inputs, persistent state of partial errors and per-item output. The drag completing on its own does not prove a copy: only the successful-write callback of the single promise, even a late one, removes that entry; originals and failed entries remain. Convert is disabled with an explanation. Independent root signed app tests: 6/6 passed with a command-line override of the Apple Development team (`root-local-app-tests-signed.log`); earlier SwiftPM suite 1,416/1,416 passed, renderer not modified afterwards. Final build, restart and Finder QA remain in the delivery ticket; the addon launcher and full conversion are not qualified.
