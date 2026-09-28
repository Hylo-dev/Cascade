# Persistent File Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the persistent shelf with animated cards and list, conversion with a central arrow and an outbound drag verified per file.

**Architecture:** A host service keeps references and results; the shelf provider uses the same SDK contracts and the same authorizations as external addons. A shared declarative component describes the file workspace; AppKit handles the transfer and SwiftUI the presentation. FFmpeg runs off the main actor and is supervised independently of the page's visibility.

**Tech Stack:** Swift 6.2, macOS 14+, AppKit, SwiftUI, Foundation, ImageIO, PDFKit, FFmpeg/ffprobe; modules CascadeContracts, CascadePresentation, CascadeAddonSDK and CascadeRuntime.

**Spec:** [Approved specification](../specs/2026-09-26-file-shelf-design.md).

**Local path approved on 26 September 2026:** the [supplementary plan](2026-09-26-local-file-shelf.md) replaces only the addon gate prerequisite for the first directly integrated shelf. This plan keeps the external addon path and the full conversion, which are not enabled by the local exception.

## Global Constraints

- "The originals stay in their location."
- "The proposed limit is four visible cards, with a +N counter beyond the fourth."
- "The arrow occupies the vertical and horizontal center of the space between the two groups of cards."
- "The initial batch processes one file at a time in the background, without blocking the UI."
- "A hidden page does not cancel the work."
- "The removal of the entry is persisted first; only afterwards can the file be cleaned up".
- "It does not depend on a user-installed Homebrew."
- "The persistent page is coordinated with the contextual pages specification, which is still under discussion".
- Follow CODE_STYLE.md: macOS 14, no force unwrap, protocols at service boundaries, IO off the main actor, no idle polling.
- No privileged internal widget; files, processes and memory go through the common policy. Do not implicitly raise the ResourcePolicy quotas.
- Convert is included. Share and Create ZIP stay for later; no implementation of the general three-activity navigation is implied.
- Keep the many pre-existing changes in the checkout. During execution use a checkout that includes them: a worktree from HEAD alone does not represent this base.

## Review Focus

1. Crash between writing the copy and saving the removal: the item may remain, but the result must not be lost (tasks 2 and 3).
2. Renamed file, replaced symlink, disconnected volume or non-materialized cloud file: no conversion of a different target and no silent removal (tasks 2 and 6).
3. Media input that refers to other files or URLs, names with dashes and shell characters: no access beyond the authorized files and no shell interpolation (tasks 5 and 6).
4. Drag during Spotlight, a display change or a list transition: no loss of focus, duplicated delivery or card that can no longer be reached (tasks 3 and 7).
5. Late receipt after relaunch/revocation, exhausted quota and a process still alive after cancellation: do not reactivate work, do not release files or resources prematurely (tasks 1, 2 and 6).

## Verified base and order

The `cascade-task6` graph locates the symbols, but some positions do not follow the
current changes: verify the checkout's source before editing it.

- MouseEventMonitor already observes local/global drags; it does not yet recognize files.
- NotchDisplayCoordinator has the `.drag` trigger and hold and guarantees a single open notch.
- NotchPanel does not become key/main and uses hit testing through `ignoresMouseEvents`.
- ContentNode has no file workspace, selector or drag source; ContentDocument supports schemas 1 and 2.
- AddonPresentationBridge renders admitted documents; it must not acquire URLs, run FFmpeg or become the database.
- ServiceBroker has finite operations (maximum deadline 30 seconds) and separate sources/events: starting a conversion returns a job ID, it does not wait for the whole conversion.
- The AddonRuntimeAdapter boundary is still documented without a qualified production conformer. A fixture does not prove the distribution path.
- ResourcePolicy currently sets 10 MiB of disk state and 20 MiB of cache per owner, 30 MiB in total; persistent results cannot be hidden in the cache or excluded from the count. Large videos may be refused: a revision of the policy is a separate intervention from this plan.

Order: 1 → 2 → 3 → 4 → 7 produces the shelf; 5 → 6 → 8 adds conversion;
9 verifies the composition. Tasks 4 and 5 are technically independent, but
execution can stay sequential. The outcome of task 1 is a prerequisite for
distribution, not a statement that the runtime is already ready.

## File map

The new model files contain values; the system implementations live
on the host side. The paths given in the tasks are relative to the project root.

| Area | Responsibility |
| --- | --- |
| CascadeContracts/FileWorkspace/ | Paginated snapshots, opaque identifiers, commands and conversion states. |
| CascadeRuntime/FileWorkspace/ | Authority over files, persistence, receipts and supervised jobs. |
| CascadeAddonSDK/FileWorkspace/ | Service client and provider through public contracts. |
| CascadePresentation/FileWorkspace/ | Common component, layout and animations without access to paths. |
| CascadeKit/Core/Interaction/ and Core/Engine/ | AppKit adapters, drag routing and contextual page. |
| Cascade/Integrations/FileWorkspace/ | Service composition and signed app resources. |
| Config/FFmpeg/ and scripts/ | Version, provenance, compilation and verification of the binaries. |

Each task adds tests to the corresponding module's target. SwiftPM automatically
includes the files under Sources/Tests; linking the app target and
the binaries instead requires Cascade.xcodeproj/project.pbxproj.

### Task 1: Public contract and verification of the authorized path

**Files:** Create in `CascadeKit/Sources/CascadeContracts/FileWorkspace/`: `FileWorkspaceSnapshot.swift`, `FileWorkspaceCommand.swift`, `FileWorkspaceEntry.swift`, `FileWorkspaceError.swift`, `FileConversionFormat.swift`, `FileConversionJobSnapshot.swift`; create `CascadeKit/Sources/CascadeAddonSDK/FileWorkspace/FileWorkspaceClient.swift`; create `CascadeKit/Sources/CascadeRuntime/FileWorkspace/FileWorkspaceService.swift`; test `CascadeKit/Tests/CascadeContractsTests/FileWorkspaceContractTests.swift`, `CascadeKit/Tests/CascadeRuntimeTests/FileWorkspaceAuthorityTests.swift`; consult `CascadeKit/Sources/CascadeRuntime/AddonRuntimeTransport.swift` and `CascadeKit/Sources/CascadeRuntime/Services/ServiceBroker.swift`.

**Interfaces:**
- `FileWorkspaceEntry`: `id: UUID`, `name: String`, `typeIdentifier: String`, `availability: FileAvailability`, `ownership: FileOwnership`, `thumbnailAssetID: String?`; no URL/bookmark on the wire.
- `FileWorkspaceSnapshot`: `revision: UInt64`, `entries: [FileWorkspaceEntry]`, `totalCount: Int`, `nextCursor: String?`, `jobs: [FileConversionJobSnapshot]`. At most 32 entries per page, payload within 64 KiB; the page limit does not limit the shelf.
- `FileWorkspaceCommand`: `.list(cursor: String?)`, `.remove(ids: [UUID], revision: UInt64)`, `.relink(id: UUID)`, `.convert(ids: [UUID], formatID: String, revision: UInt64)`, `.cancel(jobID: UUID)`.
- `FileWorkspaceClient.send(_ command: FileWorkspaceCommand) async throws -> FileWorkspaceSnapshot` uses AddonServiceClient; service `files.workspace`, feature `workspace`, operation `command`. Events use the same authorized source; no SDK client reads files.
- `FileWorkspaceService` admits commands only after validating the canonical ServiceWork. IDs are references, never permissions.
- `FileWorkspaceError`: codes `unavailable`, `permissionDenied`, `unsupported`, `quotaExceeded`, `staleRevision`, `interrupted`, `ioFailure`; user text localized by the renderer. `FileConversionFormat`: `id`, `label`, `outputTypeIdentifier`; `FileConversionJobSnapshot` has the fields fixed in task 6. These values are defined here to keep the client compilable before the engine.

- [ ] Write `FileWorkspaceContractTests` for the 32 limit, unknown fields, duplicate IDs, stale revisions and wire size; `FileWorkspaceAuthorityTests` for a different owner, a revoked grant, a duplicated command and the same builtin/external behavior. Assertion: `#expect(snapshot.entries.count == 32)` and refusal of entry 33 in the same payload.
- [ ] Run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter FileWorkspace`; expected failure because the contract is missing.
- [ ] Implement the contracts and the adaptation to the broker, keeping the 30-second limit for the start command. Connect a small signed provider to the current native path and verify authorization, revocation and observed exit. Do not create an in-process bypass to get around the missing transport.
- [ ] Repeat the tests; run `zsh scripts/check-addon-boundaries.sh --root "$PWD"`. Record the real path used in `docs/superpowers/verification/2026-09-26-file-workspace-runtime.md`. If the native runtime cannot be qualified, mounting in production stays blocked; models and renderer can advance, but the feature is not declared delivered.
- [ ] Selective commit: `feat: add authorized file workspace contracts`.

### Task 2: Persistent shelf and file retention

**Files:** Create in `CascadeKit/Sources/CascadeRuntime/FileWorkspace/`: `FileWorkspaceStore.swift`, `FileWorkspacePersisting.swift`, `FileReferenceResolving.swift`; test `CascadeKit/Tests/CascadeRuntimeTests/FileWorkspaceStoreTests.swift`.

**Interfaces:**
- `FileWorkspaceStore.init(directory: URL, persistence: any FileWorkspacePersisting, references: any FileReferenceResolving)`; actor with a single writer.
- `restore() async throws`, `addOriginals(_ urls: [URL]) async throws -> [UUID]`, `importPromisedFile(_ url: URL) async throws -> UUID`, `snapshot(cursor: String?) async throws -> FileWorkspaceSnapshot`.
- `beginDelivery(ids: [UUID]) async throws -> UUID`; `finishDelivery(_ deliveryID: UUID, itemID: UUID, result: Result<Void, FileWorkspaceError>) async throws`.
- `FileWorkspacePersisting.load() async throws -> Data?`, `save(_ data: Data) async throws`; Foundation implementation with atomic replacement of a versioned record. `FileReferenceResolving.resolve(_ bookmark: Data) async throws -> URL` refreshes stale bookmarks after verifying the identity.
- States `available`, `unavailable`, `receiving`; ownership `externalReference`, `managed`. Incomplete files and metadata stay separate from complete results.

- [ ] Write tests with real temporary directories: reopening the store keeps order and IDs; the same original is not duplicated; same-name files stay distinct; a missing volume/original stays visible; corruption/a future version is not overwritten; a failed save keeps the previous state. Verify `#expect(restoredIDs == originalIDs)`.
- [ ] Run the `FileWorkspaceStoreTests` filter with the Swift command from task 1: expected FAIL.
- [ ] Implement persistent references and results under the owner's Application Support, charged to the existing quotas before acquisition. No preemptive copy of the originals. For promised files: admit space before writing, check the growth, no available entry before completion.
- [ ] Add crash proofs at the boundaries: a completed copy without a persisted confirmation keeps the entry; a removal persisted before cleanup leaves at most one recoverable orphan file. A manual removal of a managed result uses explicit text and a confirmation before deleting the only copy; revocations do not delete originals.
- [ ] Repeat the filter: PASS. Selective commit `feat: persist file shelf entries and delivery receipts`.

### Task 3: Native drag, acquisition and per-item delivery

**Files:** Create `CascadeKit/Sources/CascadeKit/Core/Interaction/FileWorkspaceDragging.swift`; modify under `CascadeKit/Sources/CascadeKit/`: `Core/Events/MouseEventMonitor.swift`, `Core/Events/EventMonitoring.swift`, `Core/Window/NotchPanel.swift`, `Core/Engine/NotchController.swift`; test `CascadeKit/Tests/CascadeKitTests/FileWorkspaceDraggingTests.swift`.

**Interfaces:**
- `@MainActor protocol FileWorkspaceTransferring` with `receive(_ draggingInfo: any NSDraggingInfo) -> Bool` and `beginDrag(ids: [UUID], event: NSEvent, sourceView: NSView) throws -> NSDraggingSession`.
- The AppKit adapter receives the host store/authority through an async protocol, not through the public renderer. One NSFilePromiseProvider per item; the completion calls `finishDelivery` with the token from task 2.
- The monitor emits `onFileDragChanged: ((Bool) -> Void)?` only on detected changes; the AppKit input validates the types actually offered.

- [ ] Tests: a non-file mouse drag does not activate the shelf; an old pasteboard does not reactivate the heartbeat; a cancelled drop acquires nothing; a batch with one successful and one failed promise removes only the first. `#expect(remainingIDs == [failedID])`.
- [ ] Run the `FileWorkspaceDraggingTests` filter: FAIL before the implementation.
- [ ] Connect the existing local/global monitor and the AppKit target to the animated outline. Allow receiving in the notch area during a drag without intercepting the whole menu bar; use the existing `.drag` trigger/hold.
- [ ] Implement the per-promise copy off the main actor, safe destination names and collisions without overwrite. Managed results only through promises; a URL-only delivery of originals keeps the entry. Do not use the global endedAt outcome to empty the batch.
- [ ] Verify filter PASS plus a real Finder drop, cancellation and a partial drop. Verify that Mail/URL-only apps do not cause unproven removals. Commit `feat: support verified native file shelf transfers`.

### Task 4: Common SDK component and animated list

**Files:** Create `CascadeKit/Sources/CascadeContracts/FileWorkspace/FileWorkspacePresentation.swift`; modify under `CascadeKit/Sources/CascadeContracts/`: `ContentNode.swift`, `ContentNode+Components.swift`, `ContentDocument.swift`, `ProviderMessage.swift`; modify `CascadeKit/Sources/CascadeRuntime/Admission/ProtocolNegotiator.swift` and `PublicationSessionRegistry.swift` in the same directory; create under `CascadeKit/Sources/CascadePresentation/FileWorkspace/`: `CascadeFileWorkspace.swift`, `FileWorkspaceLayout.swift`; modify `CascadeKit/Sources/CascadePresentation/ContentRenderer.swift`; test `CascadeKit/Tests/CascadeContractsTests/FileWorkspaceContentTests.swift`, `CascadeKit/Tests/CascadePresentationTests/FileWorkspacePresentationTests.swift`.

**Interfaces:**
- `FileWorkspacePresentation`: paginated snapshot, `mode: FileWorkspaceMode` (`deck`, `list`, `conversion`), selection `[UUID]`, destinations `[FileConversionFormat]`, selected format and validated action descriptors.
- `CascadeFileWorkspace.init(_ presentation: FileWorkspacePresentation) throws`; a `.fileWorkspace` node in content schema 3, available to builtin and external addons. No URL, provider closure or authority choice in the document.
- `FileWorkspaceLayout.cardTransforms(count: Int, reduceMotion: Bool) -> [FileCardTransform]`; `conversionFrames(in bounds: CGRect) -> FileConversionFrames` produces inputs, arrow, controls and results without overlaps.

- [ ] Tests: schema 1/2 refuses the new node; negotiated schema 3 accepts it; global node/byte/asset limits still applied; duplicate actions refused. Layout: `#expect(cardTransforms.count == min(count, 4))`, correct +N and the arrow's center between the groups.
- [ ] Run the `FileWorkspaceContentTests` and `FileWorkspacePresentationTests` filters: FAIL.
- [ ] Implement the component with thumbnails resolved through the existing asset resolver. Stable identities and matched geometry for cards→rows→cards, short stagger, selection distinct from drag, scrollable and paginated list. The viewport does not load all the thumbnails.
- [ ] Add the optional field `fileWorkspace: FileWorkspacePresentation?` to ContentNode, valid only on the new kind. Extend ContentDocument, ProviderMessage.validateContext and ProtocolNegotiator from sets 1/2 to 1/2/3; the host advertises 3 only with the renderer/adapters installed. PublicationSessionRegistry keeps the negotiated set. Keep the legacy defaults and no fallback that drops fields; also verify documents in future timelines. Schema 3 keeps glassLights like 2.
- [ ] Verify filters PASS and a mounted preview with 1/4/5/40 files, VoiceOver and Reduce Motion. No timer once a transition has finished. Commit `feat: add shared animated file workspace content`.

### Task 5: Reproducible FFmpeg in the bundle

**Files:** Create `Config/FFmpeg/manifest.json`, `scripts/build-ffmpeg.sh`, `scripts/verify-ffmpeg.sh`, `docs/third-party/ffmpeg.md`; modify `Cascade.xcodeproj/project.pbxproj`, `scripts/build-development.sh`; create `Cascade/Resources/ThirdParty/FFmpeg/` for staged executables and notices.

**Interfaces:**
- `build-ffmpeg.sh --output <directory> --arch arm64|x86_64` produces ffmpeg and ffprobe for macOS 14; the manifest records version, URL, verified hash, flags and dependencies.
- `verify-ffmpeg.sh <directory>` checks architecture, deployment target, non-system libraries, version, encoders and the result of a fixture conversion.
- Source baseline: FFmpeg release 9.0.2 from the official page consulted on 26 September 2026; verify the signature and record the SHA-256 before the build. No invented hash in the plan.

- [ ] Write the verification that fails on missing binaries, a wrong architecture, a dependency on /opt/homebrew or a version different from the manifest.
- [ ] Run `zsh scripts/verify-ffmpeg.sh Cascade/Resources/ThirdParty/FFmpeg`: expected FAIL before preparing the artifacts.
- [ ] Compile from the verified source with the ffmpeg/ffprobe programs, without ffplay, GPL or nonfree. Use VideoToolbox for H.264 when available, native AAC/PCM/FLAC encoders; MP3 appears only if the redistributable encoder is included and verified. Do not introduce libx264 implicitly. Record the licenses and the corresponding sources/configuration.
- [ ] Copy and sign the helpers into the bundle with the app's development identity; the normal build consumes already verified artifacts without downloading dependencies from the network. Verify the architecture actually delivered, without attributing Intel proofs to an ARM-only run.
- [ ] Repeat the verification: PASS and a converted fixture readable by ffprobe. Commit `build: bundle verified ffmpeg conversion tools`.

### Task 6: Actual conversions and recoverable jobs

Checkpoint: the pure part covering formats, presets and the progress parser is implemented in the subtask [Prepare conversion formats and progress](../../../.scratch/cascade-product/issues/86-file-workspace-conversion-planning.md), commit `5c53ae5`. It does not complete the task: coordinator, job persistence, native engines and supervised processes remain to be implemented/qualified.

**Files:** Create under `CascadeKit/Sources/CascadeRuntime/FileWorkspace/`: `FileConversionCoordinator.swift`, `FileConverting.swift`, `FFmpegConverter.swift`, `NativeDocumentConverter.swift`, `FFmpegProgressParser.swift`, `FileConversionRequest.swift`; test under `CascadeKit/Tests/CascadeRuntimeTests/`: `FileConversionTests.swift`, `FFmpegProgressTests.swift`.

**Interfaces:**
- `FileConverting.formats(for inputs: [URL]) async throws -> [FileConversionFormat]`; `convert(_ request: FileConversionRequest, progress: @Sendable (Double?) -> Void) async throws -> [URL]`.
- `FileConversionRequest`: job/item ID, input URL authorized by the host, managed temporary directory and closed format ID; no CLI option supplied by the widget.
- `FileConversionCoordinator.start(ids: [UUID], formatID: String, revision: UInt64) async throws -> UUID`, `cancel(jobID: UUID) async throws`; updates through the source from task 1, same store as task 2.
- `FileConversionJobSnapshot`: ID, state `queued/running/completed/failed/cancelled/interrupted`, optional progress and completed results. The start command returns after admission, not when the job ends.

- [ ] Parser tests with split lines, missing duration, progress=end with a nonzero exit; coordinator tests for two sequential files, mixed selection, cancellation and relaunch. `#expect(maximumConcurrentConversions == 1)`; partial output does not appear among the results.
- [ ] Run the `FileConversionTests|FFmpegProgressTests` filters: expected FAIL.
- [ ] Implement Process with separate arguments, `-nostdin`, progress on a pipe and stderr drained with a bounded buffer. Identify content with ffprobe; apply a protocol whitelist, refuse playlists/external references and confine the process to the authorized files. No shell and no downloads from the media.
- [ ] Before starting, reserve job/process/memory/space according to the common policy; charge the output's growth and stop the job before it exceeds the quota. Do not use the input size alone as a guarantee of the converted size. Stop/timeout waits for the observed exit before releasing resources and deleting temporary files.
- [ ] Implement ImageIO and PDFKit behind FileConverting: JPEG/PNG/TIFF/HEIC available, images→PDF, PDF→one image per page. Explicit policies: orientation applied, color preserved where supported, JPEG without alpha uses a white background, no false preservation of selectable text from the PDF. Process pages sequentially with a memory limit.
- [ ] Verify small, locally generated real media: video→MP4, audio→WAV/FLAC/M4A and MP3 if included, image with alpha/orientation, multipage PDF; insufficient quota, shell names, replaced file, corrupted input and external references refused. Filters PASS, originals unchanged and outputs verified before publication. Commit `feat: run recoverable file conversion jobs`.

### Task 7: Shelf as the main page and the notch heartbeat

**Files:** Create `CascadeKit/Sources/CascadeKit/Core/Widgets/ContextualPageRegistry.swift`; modify under `CascadeKit/Sources/CascadeKit/`: `Core/AddonPresentation/AddonPresentationBridge.swift`, `Core/Engine/NotchEngine.swift`, `Core/Engine/NotchDisplayCoordinator.swift`, `Core/Engine/NotchController.swift`, `Components/NotchHostView.swift`; test `CascadeKit/Tests/CascadeKitTests/FileWorkspaceRoutingTests.swift`.

**Interfaces:**
- `ContextualPageRegistry.setFileWorkspace(publicationID: PublicationID, occupied: Bool)` receives only identities validated by the host, never directly from the untrusted document; `remove(publicationID:)` withdraws the registration.
- The provider keeps publishing `.widget` through the SDK; registering the page role is a common host decision for authorized addons, not a new Live Activity kind or a gigantic priority number.
- The navigation state distinguishes the open destination, the destination before the drag and the default page. Occupancy is derived from the persistent service, not from the expiry of a single publication.

- [ ] Tests: an occupied shelf becomes the default; a manual choice stays until closing; a cancelled drag restores the page; the last delivered file restores the ordinary selection; a removed display does not duplicate the acquisition. `#expect(openDisplayCount == 1)`.
- [ ] Run the `FileWorkspaceRoutingTests` filter: FAIL.
- [ ] Connect registry, host and bridge reusing SnapshotWidget and the shared renderer. Hidden provider suspended; state and conversions in the service. Finite publications are renewed on opening/a real event, with no infinite deadline and no keepalive polling; show a loading state instead of expired commands.
- [ ] Connect the double pulse once per drag and the hold during receiving/delivery; animate through the existing spring path without moving the physical cut-out. Restore target and hit testing after cancellation, drag end, lock or a display change.
- [ ] Verify filters PASS and the NotchControllerTests/NotchDisplayCoordinatorTests regressions. Native Spotlight proof with text present: a cancelled drag keeps the search and focus; if the composition is not supported, record the blocker instead of silently closing Spotlight. Commit `feat: route the persistent file shelf through the notch`.

### Task 8: Shelf provider and conversion interface

**Files:** Create `CascadeKit/Sources/CascadeAddonSDK/FileWorkspace/FileWorkspaceProvider.swift`; create `Cascade/Integrations/FileWorkspace/FileWorkspaceComposition.swift`; modify `Cascade/CascadeServices.swift`; test `CascadeKit/Tests/CascadePresentationTests/FileWorkspaceProviderTests.swift`; add strings under `Cascade/Resources/FileWorkspace.xcstrings` and SDK localization resources where used.

**Interfaces:**
- `FileWorkspaceProvider: AddonProvider` implements `handle(_:context:) async throws -> ProviderOutput` with the SDK API only. The selection/format UI state is not the authority over the files.
- `FileWorkspaceComposition.start() async throws`, `stop() async`; registers provider/service and capabilities through the path qualified in task 1. The UI does not build its own processes or stores.
- Closed action IDs: `openList`, `closeList`, `select`, `nextPage`, `convert`, `selectFormat`, `start`, `cancel`, `remove`, `relink`, `preview`, `reveal`. Filesystem actions always go to the authorized host.

- [ ] Tests: a click on the deck produces mode list and a return to deck; a compatible selection offers formats; Start absent without a format; an updated snapshot does not restart a job; indeterminate progress does not show a fake percentage; completion preserves the inputs.
- [ ] Run the `FileWorkspaceProviderTests` filter: FAIL.
- [ ] Compose the components from task 4 and the service from task 6. Arrow centered on the line joining the cards, selector in the central zone above the arrow, Start/Cancel in a distinct space without moving the arrow to the bottom. Result previews are labeled before execution.
- [ ] Connect Preview/Show in Finder and relinking with explicit selection of the file; preserve the authorizations across relaunch. Offer keyboard alternatives to the drag through native commands; focus only on explicit invocation, never during hover or heartbeat.
- [ ] Verify filter PASS and the real screen: readable cards, long text, narrow window, 40 items, keyboard, VoiceOver, Reduce Motion. Commit `feat: connect file shelf actions and conversion presentation`.

### Task 9: Integrated verification, build and delivery

**Files:** Create `docs/superpowers/verification/2026-09-26-file-shelf.md`; update `docs/addons/content.md`, `docs/addons/services.md` with only the contracts actually implemented; no unrelated change.

- [ ] Run all the FileWorkspace/FileConversion/FFmpegProgress filters and the routing tests. If they pass, run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit` once; expected no failed test. Classify any pre-existing errors separately with evidence, without declaring PASS.
- [ ] Run `zsh scripts/check-addon-boundaries.sh --root "$PWD"` and the FFmpeg verification. Demonstrate that the builtin and the external example use the same renderer, client and authorizations; record the version/schema actually negotiated.
- [ ] Run the real matrix: Finder→shelf→relaunch→Finder; five files and animated list; conversion→result→delivery; failed copy; partial drop; relaunch during conversion and delivery; missing original; display change; Spotlight; idle after a transition. Record the runtime, codec, quota and architecture limits actually observed.
- [ ] Run `zsh scripts/build-development.sh`; expected BUILD SUCCEEDED, verified signature and the /Applications/Cascade.app link updated by the script. If it fails, do not launch an old build declaring it updated.
- [ ] Quit Cascade, wait for the exit, open /Applications/Cascade.app and verify the new PID and the executable path; confirm that the shelf files are still present. Record these outcomes before completing the work.
- [ ] Review the final diff, F1–F11 coverage and the declared limits; selective commit `docs: record file shelf integration verification`. No cleanup of pre-existing changes.

## Self-review and handoff

- F1–F4: tasks 2, 3, 4 and 7. F5: tasks 4 and 8. F6–F9: tasks 5, 6 and 8. F10: tasks 2 and 3. F11: tasks 2, 6 and 9.
- The five Review Focus items have proofs in the tasks indicated; the native qualification is not replaced by mocks.
- Schema 3 does not drop support for 1/2; the shelf page does not implicitly introduce three activities or new general policies.
- FFmpeg, native documents and the shelf share receipts and persistence; no additional AVFoundation engine.
- The plan is to be reviewed. Native execution in this chat, sequential, is recommended: the adapters share authority, state and lifecycle; an independent final review precedes delivery.
- Limits to make visible in the delivery: current quotas may refuse large files; MP3 availability depends on the build; production stays subject to the qualification in task 1. Do not raise quotas or bypass isolation to make a demo pass.

External sources for task 5: [official FFmpeg releases](https://ffmpeg.org/download.html), [redistribution](https://ffmpeg.org/legal.html). Version and date were consulted on 26 September 2026, not inferred from the version possibly installed on the Mac.
