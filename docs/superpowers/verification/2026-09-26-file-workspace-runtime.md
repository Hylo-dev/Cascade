# Task 1 native-path qualification

## Verdict

**Blocked. A signed real provider cannot currently use the common `CascadeAddonSDK` service client through `CascadeRuntime` in the shipping app.** The typed SDK client and the runtime broker/service path exist, but the production native transport/bootstrap and app composition that join them do not.

This means Task 1 can add and test contracts, `FileWorkspaceClient`, and host-side authorization logic, but it cannot satisfy the brief's signed-provider/native-path qualification or claim production mounting. An in-process adapter would only reproduce the existing test arrangement and would violate the explicit no-bypass requirement.

## Concrete composition found

- `TransportServiceClient` is the real public `AddonServiceClient` conformer. It requires an injected `AddonServiceMessageChannel` (`CascadeKit/Sources/CascadeAddonSDK/Services/TransportServiceClient.swift:6,24,37`). The channel contract explicitly says it is not a native transport (`CascadeKit/Sources/CascadeAddonSDK/Services/AddonServiceMessageChannel.swift:11-20`).
- `AddonRuntime` requires an injected `AddonRuntimeAdapter`; protocol 1.3/1.4 service support activates only when that object also conforms to `AddonRuntimeServiceAdapter` / `AddonRuntimeServiceSubscriptionAdapter` (`CascadeKit/Sources/CascadeRuntime/AddonRuntime.swift:553-615`). The base protocol itself records that it has no production conformer (`CascadeKit/Sources/CascadeRuntime/AddonRuntimeTransport.swift:106-112`).
- The only concrete complete runtime service adapter in the checkout is test code: `InvocationMessageAdapter` conforms to the subscription, storage, and asset adapter protocols (`CascadeKit/Tests/CascadeRuntimeTests/ServiceInvocationMessageIntegrationTests.swift:1146-1149`). The codebase graph likewise finds this as the sole concrete `AddonRuntimeServiceSubscriptionAdapter` implementor; other runtime-adapter classes are test fixtures.
- The only `AddonServiceMessageChannel` conformers are test channels. The most complete one, `SubscriptionRuntimeChannel`, is private test code (`CascadeKit/Tests/CascadeRuntimeTests/ServiceSubscriptionMessageIntegrationTests.swift:711-725`). The test at lines 631-675 composes it with `TransportServiceClient`, `AddonRuntime`, modeled process exit, and the test adapter. It proves the internal byte/receipt path, not OS transport or a signed provider.
- The app target links only the `CascadeKit` product (`Cascade.xcodeproj/project.pbxproj:118-124`). That product depends on `CascadeContracts` and `CascadePresentation`, not `CascadeRuntime` or `CascadeAddonSDK` (`CascadeKit/Package.swift:93-98`). `CascadeApp` imports `CascadeKit` and constructs no `AddonRuntime` (`Cascade/CascadeApp.swift:7-15,30-58`). `AddonRuntime` is also an internal actor in the separate runtime product (`CascadeKit/Sources/CascadeRuntime/AddonRuntime.swift:10-12`).
- The signed native probes are separate fixtures with their own `ProbeBootstrap` / `ProbeChannel` XPC vocabulary and do not import `CascadeAddonSDK` or `CascadeRuntime` (`Prototypes/AddonPlatform/Provider/ProbeProvider.swift:6-35`). They therefore do not supply the missing common-SDK/runtime adapter.

## Existing qualification evidence

- The SDK/runtime delivery record calls the composed path an injected internal message path and says it is not a delivered native transport/bootstrap (`docs/superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md:3-5`). It leaves launcher, authenticated OS transport, physical process death, native parity, and distribution unqualified (`:37`).
- The service documentation states that a production native transport adapter remains separate and that the modeled adapters/exits do not qualify native death (`docs/addons/services.md:18-21,217,239`).
- The generated addon is source-only: no bootstrap, signing, installation, or runtime admission is provided (`CascadeKit/Sources/CascadeAddonTool/ScaffoldCommand.swift:5-6,43`).
- The managed-death/native admission gate is still an unconditional hold with exit 78 (`scripts/test-addon-managed-death.sh:7-12`).

## Smallest feasible next work

Within the file-shelf scope, implement only the public wire models, `FileWorkspaceClient` over `AddonServiceClient`, and host-side `FileWorkspaceService` authorization/revision behavior, with tests through the existing injected/model adapter seam. Record those results as internal/model qualification and leave production mounting blocked.

Unblocking the native requirement is a separate prerequisite, not a small File Workspace patch. It needs, at minimum:

1. a production authenticated bootstrap/launcher admitted by the existing native gate;
2. a production runtime adapter conforming to the cumulative service protocols;
3. a production `AddonServiceMessageChannel` for the SDK side;
4. app wiring that owns `AddonRuntime` and connects both sides;
5. a signed provider using `CascadeAddonSDK`, with observed authorization, revocation, and physical exit on that exact path.

No code, tests, build, app restart, or native fixture execution was performed for this read-only qualification.

## Feature implementation checkpoint

- Isolated checkout `codex/file-shelf`, baseline snapshot `5f8f45c`; the snapshot contains pre-existing work and is not part of the file-shelf implementation diff.
- Public bounded wire values are implemented in commit `eb18b8e`; seven focused contract tests pass. Root reviewed spec compliance and code quality.
- SDK client and internal canonical service boundary are implemented in commit `f402d8c`. Root reviewed the production code and tests and requested two corrections: preserve stable domain errors and sanitize host error text. Both corrections are covered by regression tests.
- No file acquisition, persistent shelf, UI mounting, or FFmpeg conversion is delivered by this checkpoint. Task 1 production qualification remains blocked; tasks 2–9 are not completed.
- The managed launcher hold remains unchanged. This verification record does not qualify native transport, process exit, or production availability.

## Final checkpoint verification

- Root ran `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter FileWorkspace` after the final code commit: exit 0, 21 tests passed (7 contracts, 4 client, 10 authority).
- Implementer ran the existing `ServiceBrokerTests`: 22 passed. The full package run reproduced the baseline failure in `controlDragKeepsExpandedContentAliveUntilMouseUp` at `NotchControllerTests.swift:1385`; its focused rerun passed. The full suite is therefore not claimed green.
- Root ran `scripts/build-development.sh` with `CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf`: exit 0, SDK boundary checks and codesign verification passed. `/Applications/Cascade.app` points to that build.
- Cascade was quit, relaunched, and verified at PID 68339 with its executable under the same DerivedData directory.
- Weekly account budget at completion: 2% used, 98% remaining. The requested 80% reserve was preserved.

The worktree remains attached on `codex/file-shelf`. The original checkout was not edited during implementation. The native prerequisite is the blocker for activation; it was not replaced with a privileged in-process path.

## Internal persistence: 26 September 2026

Commit `bbe1144`, implemented by GPT-5.6 Sol and reviewed by the root: atomic POSIX manifest with fsync; handling of commit uncertainty without deleting potentially referenced copies; bookmarks with descriptor and scope; a single writer per host lifetime, explicit close before reopening; managed copies and partial receipts, overlapping pins, real disk/state/memory quotas. Independent root test: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --scratch-path /tmp/cascade-task2-build2 --filter 'FileWorkspace|ResourceGovernorTests'`, exit 0, 39 runtime + 4 SDK + 7 contracts = 50 tests.

Limits: promised input that is already completed, native receiver not implemented; no mounting in the app. Delivery consumers must use the descriptor lease. Device/inode/generation identity is conservative after a remount; filesystems without a meaningful generation do not give the same protection against inode reuse. Unknown data and failed cleanups remain preserved and charged. Build/relaunch for the current tranche will follow the other independent increments.

## Shared component: 26 September 2026

Commit `b8b3756`, implemented by GPT-5.6 Sol and reviewed by the root. Content schema 3 with explicit opt-in; compatibility with 1/2 and glass lights preserved; immutable action descriptors, assets declared and remapped in the archive. Common renderer with a 4/+N fan, paginated list, finite transitions and Reduce Motion, native commands, distinct input/arrow/results, and real progress.

Root verification: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter 'FileWorkspace|ProtocolAdmissionTests|GlassLightTests|ContentValidationTests|ActionAuthorizerTests'`, exit 0, 48 runtime + 17 presentation + 21 contracts = 86 tests. Root inspected the PNGs produced by NSHostingView/NSWindow in `/private/tmp/cascade-file-shelf-preview/`; fixed rows past the edge, overlapping titles, groups above the arrow, previews wrongly attributed to results, and an ambiguous Convert command.

Limits: evidence on settled states, not on production notch animations; VoiceOver not navigated manually. Schema 3 not activated in the app, no privileged widget or bootstrap enabled. Native evidence remains a requirement of the later tickets.


## FFmpeg bundle and tranche delivery: 26 September 2026

Commit `c1c8d51` and fix `30ba37f`, GPT-5.6 Sol with preliminary research by GPT-6 Sol and a personal root review. FFmpeg/ffprobe 9.0.2 authenticated before compilation with SHA-256, fingerprint and official signature. Thin arm64 helpers, macOS 14 target, no Homebrew dependency in the bundle; H.264 VideoToolbox/AAC/FLAC/PCM available, MP3 excluded. Build sources, manifest, licenses and reproducible instructions in `docs/third-party/ffmpeg.md`; generated binaries excluded from Git. No Intel qualification.

In review, root fixed unsafe output-folder replacements, path quoting and the verifier policy. Final shell suite exit 0: ten expected rejections, real fixtures on ordinary paths, paths with spaces, and under the sandbox. The first Xcode build detected the sandbox limit on literal outputs; the fix moves the scratch into the target's already authorized TEMP_DIR and keeps the sandbox enabled. Log `root-ffmpeg-tests.log` in the SDD ledger.

The full Swift suite has 1,374 tests: 861 runtime, 121 presentation, 273 appkit, 102 contracts, 17 SDK. It reproduced a single pre-existing intermittent failure, `controlDragKeepsExpandedContentAliveUntilMouseUp` in `NotchControllerTests.swift:1385`; the isolated rerun passed. The new tests pass, but the full suite is not declared green. Logs `root-full-suite.log` and `root-known-drag-rerun.log` in the SDD ledger. No Swift change after this run.

Final root build `CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf /bin/zsh scripts/build-development.sh`: exit 0, SDK boundary check and full signing succeeded. Verifier also run on `Cascade.app/Contents/Helpers/FFmpeg --require-signature`: H.264/AAC conversion readable by ffprobe. App and two helpers signed with the same TeamIdentifier; licenses in `Contents/Resources/ThirdParty/FFmpeg`, no duplicate copy. `/Applications/Cascade.app` updated to the verified build. Previous process 68339 closed, new process 27461 launched and verified with its executable in the CascadeFileShelf directory.

Wayfinder: tickets 78/80/81 resolved. 77/79/82/83/84/85 remain open, dependent on native qualification 19/22; no privileged path or launcher enabled. The shared UI was verified in preview, not mounted in the app. The complete shelf and the conversion jobs are therefore not yet usable in production. Final weekly quota 7% used/93% remaining, above the requested 80% reserve. Worktree kept, original checkout not modified.


## Formats and progress: continuation of 26 September 2026

Commit `5c53ae5`, GPT-5.6 Sol, personal root review for compliance and quality. The internal component performs no I/O and launches no processes: it turns telemetry and ffprobe metadata into observations and closed presets. Maximum line 4096 bytes, document 64 KiB, 32 tracks and 32 inputs; no growing history. Cover art and an absent video disposition do not qualify MP4. Duration excludes unselected tracks; the final marker does not represent job success. The fixes are included in the 15 focused tests.

Independent root verification: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter 'FileWorkspace|FFmpegProgressTests|FFmpegMediaPlanningTests'`, exit 0, 64 tests passed (44 runtime, 9 presentation/SDK, 11 contracts). Log `root-task6a-tests.log` in the ledger. The full suite was not rerun for this contained increment; the earlier intermittent drag failure is not declared resolved.

Build `scripts/build-development.sh` with DerivedData CascadeFileShelf succeeded, SDK boundary check and full signing passed, helpers verified by the Xcode phase. Log `task6a-app-build.log`. Applications link updated, old process 27461 closed and new process 34695 verified on the same build. No change to the launcher, the gate, the transport or the production composition. The complete-jobs ticket remains open with a native dependency; no shelf conversion is qualified.

During the Git checkpoint, a pack in the original checkout on iCloud returned a timeout; the subsequent object read and `git verify-pack` succeeded. No repair/repack performed. Worktree kept and clean after the commits. Observed weekly quota 7% used/93% remaining, 80% reserve respected.

## First local increment: final verification

The [approved exception](../specs/2026-09-26-file-shelf-design.md#9-integration-into-cascade) allows a shelf page integrated directly into the app; it qualifies neither the external addon launcher nor the complete conversion. This section records evidence only when observed by the root.

| Check | Status and evidence |
| --- | --- |
| Local host, per-entry delivery | **Accepted**: commit `a0508ef`, root review with fixes; 73 independent tests passed (53 runtime, 9 presentation, 11 contracts), SDD log `root-task87-tests.log`. No app delivery from this commit alone. |
| Root review of the page and of the incoming drag (ticket 88) | **Accepted**: commit `ec14e70`, root review and 71/71 focused tests passed (`root-task88-tests.log`). Combined filter 139/140 with one pre-existing intermittent drag test; no final native qualification from this test. |
| Root review of the composition and of the outgoing drag (ticket 89) | **Accepted**: commit `e25e75c`, including the fixes for persistent partial failure and visible rejection. `drag-ended` alone is not a receipt; the successful-copy callback for a single promise can arrive later and removes only that entry. |
| Full suite after the composition | **Passed on the final build**: independent root verification `swift test --package-path CascadeKit --no-parallel`, exit 0, 1,443/1,443 (885 runtime, 122 presentation/SDK, 317 CascadeKit, 102 contracts, 17 CLI), SDD log `root-receiver-persistent-tests.log`. |
| Signed app tests | **Passed on the final build**: 7/7 independent root tests, SDD log `root-shelf-clear-app-tests.log`. |
| Signed build and SDK/signature checks | **Passed**: final build exit 0 (`root-receiver-persistent-build.log`), SDK boundary and signature checks passed. |
| Ticket 91 drag fix | **Root source review passed** in commit `5718621` after fixes to hold, hit testing, expanded area, opt-in registration, stale exit and cleanup. Agent focused tests 26/26. The manual test on the build at PID 59537 still failed on intake and Mission Control; the user reports that the enlarged area improves use. Public Quartz guard: the shelf's horizontal band, inset vertically by 2 points from the top edge, after validated regular URLs; if permissions are missing, it fails open without a prompt. No macOS 27 guarantee without evidence. |
| Drag fix build | **Passed**: `BUILD SUCCEEDED`, exit 0 (`root-drag-regression-build.log`); SDK boundary check, signature and Applications link verified. |
| Early panel admission | **Source reviewed, user test failed** in `c43b7af`: candidate panel on a recognized file gesture, but only native `NSDraggingInfo` admits files. A stable global hint of 1–32 regular URLs used only for UI/guard, not for reading or copying; hover fallback during opening and physical `mouseUp` against late arming. Candidacy over the whole top strip during a file drag can cover other menu bar drops; ordinary mouse unchanged. |
| Early admission build | **Passed**: `BUILD SUCCEEDED`, exit 0 (`root-early-intake-build.log`); SDK boundaries, codesign and Applications symlink verified. |
| Native panel registration | **Review and tests passed, manual test failed**: commit `43e83eb`, `NSPanel` registration and forwarding limited to the same host; guard diagnostics, without claiming a Mission Control fix. Agent 18/18 focused tests; root 1,436/1,436 full tests. Signed build `BUILD SUCCEEDED`, exit 0 (`root-window-destination-build.log`), SDK boundaries, codesign and Applications link verified. |
| Final receiver and occupied page | **Code reviewed and compiled, user QA pending**: commit `5d852e7`, visual pin kept and receiver in the active Space with forwarding to the same host; root review of 12 files and fixes for asynchronous ownership, page cache, preview, exit and coordinates. Signed build exit 0 (`root-receiver-persistent-build.log`), SDK boundaries/codesign/link verified. No qualification of the drag or of Mission Control on the final solution without new evidence. |
| `/Applications/Cascade.app` link to the current build | **Verified**: symlink to `/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf/Build/Products/Debug/Cascade.app`. |
| Quit, relaunch and PID/executable path check | **Verified on the final build**: old PID 69502 closed and absent; relaunch from `/Applications/Cascade.app` at PID 74874 on 26 September 2026 at 23:12:31, executable `CascadeFileShelf/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade`. Receiver readiness at 23:12:32.100: `registered=3`, `activeSpace=true`, `visible=true`. |
| Finder: intake and drag-out, readable copies and originals preserved | **Intake failed on build `43e83eb`/PID 68100**: user test 22:49:13–14 with no native callbacks, first drag with 23 drag events and 0 clamps, closing at `mouseUp`. In the earlier tests the underlying Finder offered "Replace". CUA temporarily observed `/private/tmp/cascade-native-drop-qa/Cascade-drop-check.txt` in Finder, then ScreenCaptureKit `-3812`; Dock `getApp` timed out after 261 seconds. The later A/B received the drop and the user saw files in the shelf; drag-out and originals in Finder not verified. |
| Window pin A/B | **Native routing verified only in the A/B**: temporarily omitting only `windowPinner.pin(panel)` in PID 69502 made `entered`/`updated`/`hover` arrive from 22:56:49, `mouseUp` with `nativeHoverHeld=true` at 22:56:54.397 and drop `accepted=true` for one entry at 22:56:54.403. `accepted` indicates intake, not persistence. The user confirms the files appeared; authoritative manifest `entries=1`, `revision=3`. The managed-file count excludes external originals, so zero does not indicate an empty shelf. The final solution, which keeps the visual pin and uses a separate receiver, still has no QA. Mission Control not qualified. |
| Native intake diagnostics | **Manual test received, intake still failed**: PID 61289 ready (`enabled=true`, `registered=3`, `windowAttached=true`). At 21:56:24.969 `begin` with `panelReady`, `ignored=true`, pointer outside the panel and `intake=false`; at 21:56:25.579 `intakeWindowReady` with `ignoredPreviously=true`, `intake=true`; at `mouseUp` 21:56:27.859 `nativeHoverHeld=false`. Second test 21:56:29–30 identical; no `nativeEntered`/`rawUpdated` and no delivery. Late activation is a candidate, to be confirmed with the new test. `.notice` log in the unified log, first capture `/private/tmp/cascade-file-drop-diagnostic.log`. |
| Cancelled drag, rejecting destination and partial delivery | **Pending**: not verified in Finder. The individual promise callback remains the removal criterion, not `drag-ended`. |
| Shelf persistent after relaunch | **Manifest verified, UI pending**: `entries=1`, `revision=3` survives the final relaunch; the CUA screenshot shows the transparent receiving window, not the open shelf. |
| Occupied default page and manual navigation preserved | **Pending**: the user request for a primary shelf, Clear and simplified cards is implemented in `5d852e7` and tested, but not observed in the real notch; response to the manual test pending. |
| VoiceOver/accessibility and Reduce Motion in the real notch | **Pending**: Reduce Motion unit tests passed, no manual test in the open notch. |

Local tickets 91, 92 and 90 remain open: final solution reviewed, tested, compiled and relaunched; the user test of the new drop and of the shelf UI has not arrived yet. The screenshot of the transparent receiving window does not qualify the UI. Incoming file promises and Convert are not available. External addon tickets 77/79/82/83/84/85 remain open. Observed remaining weekly reserve: 89%.

## Review of 27 September: build `48e682c`

Implementation with three GPT-5.6 Sol subagents, independent review and fixes by the root. The shelf bound uses `NotchConfiguration.expandedHeight`: current configuration 440×144 pt outer, content 400×124 pt. The context exposes the central obstruction in SwiftUI coordinates; the receiver admits an already validated native drop even before expansion. Shelf priority and permanent opening are now separate.

The renderer uses Finder icons without backgrounds, an entrance center→left→fan, a horizontal row with back navigation, selection, pagination and context menus. Convert/Clear are only in the deck view. Glow on the native `notchGlassLights` path, a central drop icon with Magic Replace and a fallback; reduced motion and reduced transparency respected. Root fixed the central geometry, the fan direction, cancellation/completion of the sequence, monotonic tokens, and removed the old vertical list.

Independent checks: final SwiftPM suite exit 0, 1,447/1,447 (885 runtime, 124 presentation, 319 CascadeKit, 102 contracts, 17 CLI), `root-final-tests.log`; signed app tests exit 0, 9/9, `root-final-app-tests.log`; signed build exit 0 with `BUILD SUCCEEDED`, SDK boundaries/codesign/Applications link verified, `root-build.log`. Logs in `.superpowers/sdd/2026-09-27-shelf-design/`. Native PNG previews of 1/4/5 files and of the horizontal row examined by the root at 400×124 pt; these are renderer checks, not a capture of the physical notch.

After Quit, no Cascade process remained (`pgrep` exit 1). Relaunch verified at PID 97319, 27 September 2026 15:26:52, from the bundle `CascadeFileShelf/Build/Products/Debug/Cascade.app`; `/Applications/Cascade.app` points to the same build. Receiver ready with three types, active Space and visible window. CUA keeps selecting the transparent receiving window: the real test of fast drag, gesture and rendering in the notch is still required from the user. No new Mission Control qualification. Observed quota 13% used, 87% remaining.

## Fan refinement and SwiftUI preview: 27 September 2026

Work delegated to GPT-6 Sol for layout/preview and GPT-5.6 Sol for the gesture; root review and fixes. The icon step goes from 34 to 16 pt, with tilts of +4/−4/−8/−12°. Back navigation calls `perform(closeList)` and clears the selection, returning pagination to the start. After opening with a click, conventional back navigation uses a positive X delta; after opening with a scroll, it uses the inverse of the initial direction. On the horizontal axis, navigation activates only at the starting edge, keeping row browsing. Momentum and orphaned updates after the view is rebuilt do not navigate.

The preview `Cascade/Features/FileShelf/FileShelfDesignPreview.swift` uses the real `CascadeFileWorkspace` and AppKit wrapper, Finder icons and in-memory DTOs, no user file or conversion. Open the worktree's project in Xcode, that file, then the "Shelf" Canvas. External controls for 0/1/4/8 files, replaying the entrance and Reduce Motion; frame 440×144, content 400×124 and central obstruction 184×28. The root fixed content contrast, an overly complex SwiftUI expression, compatibility of the old scroll hook and isolation of the pure types.

Final verification (`.superpowers/sdd/2026-09-27-shelf-preview/`):

- `renderer-tests.log`: 8/8 tests passed; `previews/deck-4.png` examined for overlap, rotation and name.
- `app-tests-final.log`: 12/12 tests passed, exit 0. Covers inverse direction, double-navigation prevention, list edge, momentum and selection/page reset through the gesture path.
- `build.log`: signed build, codesign verification and `/Applications/Cascade.app` update, exit 0. The updated path is `~/Library/Developer/Xcode/DerivedData/CascadeFileShelf/Build/Products/Debug/Cascade.app`.
- Relaunch through CUA: PID 97319 exited, process absence confirmed, new PID **5063** at **17:48:21 CEST**. Receiver ready and visible at 17:48:22.

Limits: the Canvas was not started because Xcode shows "Install Required" for the initial components. Compilation of the preview macro is verified; interaction in the Canvas and the gesture on the physical trackpad remain to be tested. Capturing the notch through CUA keeps the limit already recorded. The tests do not qualify Mission Control or new Finder drops. Remaining weekly quota measured: **87%**, above the user's 80% threshold.

## Selection, actions and renaming the original: 27 September 2026

Implementation delegated to GPT-5.6 Sol for the renderer and interactions, GPT-6 Sol for the preview; root implements the runtime rename and reviews/fixes the integration. No original user file was renamed during the tests: the tests use temporary fixtures. The user's explicit preference enables renaming the original when they use the button.

The renderer keeps the 400×124 pt size and the top shoulder clear at the center: compact icons 68 pt, list 60 pt; front rotation 1.75°, names only in the list, overflow below. Colored 19 pt text and 24 pt icons share the transition. System accentColor focus, distinct selection; removal briefly keeps entries already removed from the model to show their fade-out, without faking a failed removal. The last frame's priority is released at the end of the effect.

Precise scrolling is consumed and moves focus by one file per gesture; the back gesture at the first file closes again. Click toggles, Shift selects a range, arrows/Shift and Cmd+A on the page; Delete on the selected/focused files. The `NotchPanel` can become key only if the responder conforms to the explicit marker; the stable keyboard container acquires focus after click/scroll and releases it when unmounted. The glow stays outside the new NSHostingView to propagate the native preferences; theme and sizes are kept inside.

The deck prepares all pages; the list resolves the selection at drag time. The pre-existing runtime keeps the originals and removes each reference only after a successful copy. Rename uses native coordination and an exclusive rename, updates bookmark/metadata and invalidates earlier PreparedFile instances; collisions, invalid names, stale revisions and persistence failure are verified.

Evidence in `.superpowers/sdd/2026-09-27-shelf-selection/`:

- `full-tests.log`: 1,452 SwiftPM tests passed (888 runtime, 125 presentation, 320 core, 102 contracts, 17 CLI), exit 0. Covers rename/persistence/rollback, metadata update and pagination without a revision change, and explicit access to the panel's focus.
- `app-tests-final.log`: 17 tests passed, exit 0; covers selection, Delete on page 2, a drag of 25 files against the selection, the stable responder container and the fade-out of the last file.
- `previews/deck-5.png` and `list-40.png` examined by the root; fixed mask clipping before the card transform. The interactive SwiftUI preview was updated and compiles with the app.

The Canvas still requires the initial Xcode setup. Verification of the physical gestures and of the drop in Finder remains pending; no new Mission Control qualification. Final weekly reserve measured: **85%**, above the 80% constraint.
