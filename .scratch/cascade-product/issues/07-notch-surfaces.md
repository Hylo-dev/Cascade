# Design the notch states and surfaces

ID: 07
Parent: cascade-product
Type: prototype
Labels: wayfinder:prototype
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 03, 04

## Question

Which presentations and transitions define the notch at rest, compact on the sides, expanded activity, widget page, notification, search and settings? Produce a cheap prototype to agree on black and glass, physical alignment, protrusion on displays without a notch and haptic feedback after opening. Make the reference to the Dynamic Island precise: simultaneous activities, occupied sides and the passage from compact to expanded. The prototype is a decision aid, not production code.

## Survey and remaining choice: 20 September 2026

The public policy is resolved. The [comparison of the surfaces and the search](../../../docs/wayfinder/context/2026-09-20-notch-surfaces-checkpoint.md) separates the already approved contracts from the visible choice still needed: accept in the first tranche the original Spotlight field with its own dimensions, or require right away a redesigned field inside the notch. The native first tranche is recommended, consistent with the preference already expressed for the real Spotlight. The API policy is not requested again.

The survey also corrects the reading of the historical haptic requirement: the approved spec of 4 September places it at the start of hover. Black/glass, compact activities and alerts already have implemented contracts and must not be redesigned from scratch. No new prototype or live use of Spotlight is declared; the document is a preparation for the decision, and the ticket stays open.

## User decision: 20 September 2026

"Yes, exactly": the search with the original Spotlight field and its native dimensions is approved for the first tranche. The choice about the visible result is resolved. What follows is the join and restore prototype already proposed, keeping the system input and results; no new private API approved. The local verification and the remaining surfaces keep this ticket open.

## Code realignment and pause

The survey following the confirmation found the Spotlight integration already implemented and documented in the [9 September plan](../../../docs/superpowers/plans/2026-09-09-spotlight-droplet.md): the previous description "local test only" was incomplete and must not be used to duplicate the coordinator. The handoff/shortcut/AX cancellation checks and the 6 droplet behaviors were reconfirmed today. No change to the app code.

The [restore review](../../codex-addon/20260920-spotlight-native/restore-review.md) identifies a loss of the original state when stop does not find a window or the move fails; the frequency and the real effect require a native test, not passed today. The proposal to move the restore earlier, into clearTarget, has yet to be evaluated by the root against the uses of clearTarget during the decision after Escape: it is not an approved fix.

[Outcomes and limit of the UI tool](../../codex-addon/20260920-spotlight-native/checks.json). No new prototype, app build or restart performed in this continuation; the existing local process was verified at PID 34140. After the ambiguous message "sett", further UI actions are suspended pending clarification. Agent closed, claim released, ticket open.

## Resumption after the typo

The user clarifies "a typo, go on". Verification of the existing integration resumed. The build pointed to by Applications was found removed from the filesystem (the old process still exists); recompilation through the official script is in progress before the UI test. The deletion of the build is not attributed to a specific cause without evidence. No new Spotlight code written yet.

## Delivery impediment: 20 September 2026

The resumption hits an input that is not available locally: Config/Cascade-Info.plist (378 bytes, SF_DATALESS) times out on read. The download through the public Foundation API was requested successfully, but the content did not arrive. Xcode was waiting on the coordinated read; the build process was stopped by the root with SIGTERM (exit 143), without modifying iCloud services. No compilation error is inferred from the wait.

A temporary copy of the local sources with identical hashes was prepared; only the plist is missing, and the empty copy produced by the timeout was removed. [Checkpoint and resumption instructions](../../codex-addon/20260920-spotlight-native/checkpoint.json). Materialize the original file before running the build; do not synthesize it or replace the checkout. The previous build in DerivedData was removed by an undetermined cause: /Applications/Cascade.app remains a link to a missing target. No restart performed: the already active process is kept.

The [root evaluation](../../codex-addon/20260920-spotlight-native/root-restore-review.md) does not adopt the generalized restore in clearTarget; the qualification of the native cycle stays open. The pre-existing checks pass, no new app code and no active agent. Claim released while waiting for the file.

## Resumption after the file became available

The user confirms the download of the plist, now readable and valid. The previous temporary copy is no longer available: it was recreated from 451 verified inputs of the checkout, without code changes.

Official build completed with exit 0 from the verified local copy; valid Apple Development signature and Applications link updated. Normal restart through the UI verified: PID 3835→3923, new process still active at the next check. The 451 inputs remained identical to the checkout. [Updated delivery](../../codex-addon/20260920-spotlight-native/delivery-resumed.json).

The Terra survey and the [root evaluation](../../codex-addon/20260920-spotlight-native/root-surface-review.md) confirm that the settings exist in addition to the Spotlight integration; the context that asked for duplicate prototypes was corrected. No new change to the app code. The UI check, recovered after startup errors, exposes for Field the Siri conversations window and not the Spotlight field; the settings shortcut does not change the accessibility tree. This is not a negative proof of the features, but it prevents qualifying them through that path. The user was asked for permission to use CLI/AppleScript as an alternative method, as imposed by the UI tool's instructions; no change to permissions or preferences.

Claim released while awaiting the answer on the alternative method. No agent or build running. 27 tickets resolved out of 44; no new closure. Observed weekly usage 5%, 20% cap.

The user authorizes CLI and AppleScript to complete the tests. Claim resumed; persistent authorization for these checks, without changing preferences or permissions.

## CLI and AppleScript test

Verified the settings window `cascade.settings`: 760×570 at (355, 152), sidebar and controls visible, focus on the `settings.size` control. The native Spotlight field was located with identity `SpotlightSearchField`, 520×87 at (475, 65). The `spotlightEnabled` preference read from the app's domain is 0: the "Spotlight from the notch" toggle exists, while the distinct "Open Spotlight from the notch" command does not appear with the integration disabled. No preference modified. The calculation test is not qualified: the bounded attempts did not keep the field observable and did not enter queries.

[Partial evidence](../../codex-addon/20260920-spotlight-native/native-qualification-partial.json). Temporary activation of the toggle was requested to verify the join and the restore, with a return to the initial state; the answer is still pending. The user's follow-up asks to clarify the ticket's purpose: it is design/qualification of the surfaces, not a new tranche of the addon engine. No global closure inferred from the settings verification.

Final normal restart verified PID 7661→8144, valid signature and 5 s stability: [evidence](../../codex-addon/20260920-spotlight-native/restart-evidence.json). No active agent or modified app code. Claim released during the clarification.

The user confirms "ok, go on" after the clarification. The temporary toggle test resumed with a restore of the initial state, again observed as disabled. Claim resumed; launcher unchanged.

## Answer

The first-tranche surfaces are defined by the already approved contracts: rest and chrome, hover with haptics on entry, compact primary activity and the second one in the circle, extended opening and widget page, alerts on the wings, black/glass and Reduce Motion. The [consolidated reference](../../../docs/wayfinder/context/2026-09-20-notch-surfaces-checkpoint.md) links the sources. The remaining search choice is resolved by the user's confirmation: real Spotlight, original field and results with native dimensions; no new private API. The settings keep the requested macOS language and position under the notch. The feature inventories remain in their own tickets.

The [local verification](../../../docs/superpowers/verification/2026-09-20-spotlight-native-continuation.md) observes the 520×87 field with focus, native calculation 2+2=4 via AX, restore of the position both with the field open and after closing/disabling/reopening, as well as the geometry and focus of the settings. The hypothesized user defect was not reproduced; no change to the app code is justified. Toggle restored to disabled and restart verified at PID 10620.

Terra review evaluated by the root: [report](../../codex-addon/20260920-spotlight-native/ticket-closure-review.md). The closure is accepted as a decision/prototype on the basis of the approvals, not of the mere existence of the code. Keyboard/IME, VoiceOver, continuous drag, display/OS matrices and performance remain distinct qualifications, kept in the verification report and in the search/interaction tickets; this closure does not declare their PASS. Launcher unchanged.

The reviewer's proposal to reopen the alert queue/timeout is not adopted: the current contracts discard alerts received during expansion/lock, without re-proposing them. The next decision concerns arbitration between manual intentions and contextual screens.
