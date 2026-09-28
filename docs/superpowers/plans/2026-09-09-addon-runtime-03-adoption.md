# P3: Integration and team widgets

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the Cascade widgets onto the public path, proving autonomous content, shared services and remote SwiftUI scenes in the real app.

**Architecture:** The app composition registers packages in the catalog. Providers publish values through the SDK; a generic bridge connects the runtime to the notch. The macOS integrations become broker services.

**Tech Stack:** Swift products from P1/P2, SwiftUI, launcher and remote scenes verified in P0, signed addon targets and existing regression scripts.

**Spec:** [architecture](../specs/2026-09-09-addon-runtime-design.md); [main plan](2026-09-09-addon-runtime.md).

## Global Constraints

All the constraints of the main plan apply. Prerequisites: P1/P2 verified; for remote scenes also 00.3. No team widget has special quotas or an in-process production executor. Preserve existing behavior, privacy, accessibility and interactions. Every task that changes the app ends with a build, an update of the link in /Applications, a verified relaunch and a report.

## Task 03.1: App composition and Clock on the public path

**Files:** create Cascade/Addons/BundledAddonCatalog.swift, Cascade/AddonRuntimeComposition.swift; Addons/Clock/Manifest.json, ClockProvider.swift, Info.plist and the signing files required by the format chosen in P0; CascadeKit/Tests/CascadeRuntimeIntegrationTests/BundledClockTests.swift; scripts/check-addon-boundaries.sh. Change Cascade/CascadeServices.swift, Cascade.xcodeproj/project.pbxproj and the P1 bridge. Migrate and then remove Cascade/Features/ClockWidget.swift once it has no more users.

**Interfaces:** `BundledAddonCatalog.entries() throws -> [InstalledAddon]` returns metadata of verified packages, not widget factories. AddonRuntimeComposition connects catalog, services, runtime and AddonPresentationBridge. ClockProvider implements AddonProvider and produces a Publication with a clock time component; no IPC tick.

- [ ] Write BundledClockTests: enable Clock, receive a publication, wait for the provider's normal exit and verify that the clock stays valid; disabling it must also remove actions and state. Check that the provider's PID differs from the host's.
- [ ] Link the package products and create the addon target according to P0. Its bundled origin changes discovery, not authenticated identity, handshake, permissions or ResourcePolicy. Future Clock updates also go through the normal catalog.
- [ ] Replace the direct registration `notch.register(ClockWidget())` with enabling the Clock package. The bridge does not know ClockProvider and does not choose views through a switch on AddonID.
- [ ] Create check-addon-boundaries.sh to verify the package dependency graph and the imports of the addon targets: CascadeKit, CascadeRuntime, notch APIs and private integrations are forbidden. Temporarily list only the existing legacy files still to be migrated in later tasks; a new exception must fail the check.
- [ ] Verify clock, calendar/locale, time zone change, sleep/wake and return after the notch has been closed for a long time. The time presentation updates in the host when needed; no queue of backlogged ticks and no addon loop while it is hidden.
- [ ] Run BundledClockTests, the AddonPresentationTests introduced in P1 and check-addon-boundaries.sh; run build/relaunch and record a visual and consumption comparison with the previous Clock; commit limited to the task.

## Task 03.2: Autonomous timer and first external project

**Files:** create Addons/FocusTimer/Manifest.json, FocusTimerProvider.swift, FocusCore/FocusSession.swift; Examples/StandaloneFocus/Package.swift, README.md, Sources/StandaloneFocusProvider/ and the signed project/container required by P0; CascadeKit/Tests/CascadeRuntimeIntegrationTests/StandaloneFocusTests.swift; scripts/test-addon-standalone.sh.

**Interfaces:** FocusSession is a value library independent of the source app: ID, state, deadline and revision. The provider uses start/pause/resume/end actions identified by stable strings and publishes the SDK countdown. The example package includes the functions it uses; it does not look for libraries in the source app.

- [ ] Write a session test start → provider exit → advance of the controlled clock → pause with a new provider → resume → expiry. Verify revisions and a single final event, with no process alive for each second of the timer.
- [ ] Share FocusCore between the source app example and the addon through a build dependency. Build the autonomous container in a temporary directory using only the public SDK products; the example does not import repository sources through hidden relative paths.
- [ ] The timer must work with the source app closed and with the source app never installed. The optional action to open it declares appInstalled and stays unavailable when it is missing; it does not block start/pause/end and does not open/install anything automatically.
- [ ] Register the deadline in the runtime with a scheduled event: distinguish the visual countdown update from running the function at expiry. After a sleep past the deadline deliver an expired event only once; no catch-up burst.
- [ ] Prove permission refusal, disabling, host closed, corrupted state file and expiry while the process is absent. If the host was closed, apply the restore policy without promising work performed in its absence or repeating a past notice.
- [ ] Run StandaloneFocusTests and `/bin/zsh scripts/test-addon-standalone.sh`; save PID, signature, absence of the source app and the action log in the report. Build/relaunch of the app when changed; commit.

## Task 03.3: System notices and Bluetooth through the shared services

**Files:** create Addons/SystemNotices/Manifest.json, ChargingProvider.swift, VolumeProvider.swift, BluetoothProvider.swift and related resources; Cascade/Addons/SystemServiceRegistration.swift; CascadeKit/Tests/CascadeRuntimeIntegrationTests/SystemNoticeAddonTests.swift, SharedSystemServiceTests.swift. Change Cascade/Integrations/Power/, Volume/, Bluetooth/, CascadeServices.swift and migrate Cascade/Features/ChargingNotice.swift, VolumeChangeNotice.swift, BluetoothConnectionActivity.swift and related helpers/resources.

**Interfaces:** Register explicit versions of the system.power, system.volume and system.bluetooth services. Service events are bounded values; change and read actions have distinct scopes. One adapter per source is shared by all consumers with compatible grants. The providers publish notice/activity families of the common contract.

- [ ] Before the migration run and record the available regressions for power, volume, Bluetooth, presentation and Bluetooth audio routing. Save the expectations for privacy, duration, priority, revision and accessible labels; the migration is not a visual redesign.
- [ ] Write SharedSystemServiceTests: two addons request the same monitor, a single real source is started; revoking one consumer does not interrupt the other; the last release stops the source. No second subscription created in CascadeServices after the broker is adopted.
- [ ] Separate the host-managed interest subscription from the connection to the provider: a connection closed for inactivity does not prevent the broker from waking the addon on an admitted event. Disabling and revocation also remove the interest. The monitor stays active only while an authorized demand exists, and it is accounted for.
- [ ] Migrate the three providers and keep per-feature enabling. A missing Bluetooth dependency blocks Bluetooth without making the power and volume notices unavailable. Resources/localizations are included in the package, not fetched from a private host path.
- [ ] If the ordinary components do not represent an existing behavior, extend the public schema with a bounded and tested component or use the remote scene from 03.4. Do not introduce a private factory. For the existing image sequences, evaluate a public imageSequence component: already decoded assets, at most 48 frames at 96×96, duration 3 s, one playback, stop when hidden or with Reduce Motion; all buffers count toward the quotas. Update schema, SDK, renderer and tests together before use.
- [ ] Run SystemNoticeAddonTests, SharedSystemServiceTests, LiveActivityHostTests and NotchActivityLifetimeTests. Run `/bin/zsh scripts/test-power.sh`, test-volume.sh, test-bluetooth.sh, test-bluetooth-presentation.sh and test-bluetooth-audio-route.sh from the same scripts folder with their full path. Verify AirPods/other hardware only if present and record the missing cases.
- [ ] Remove the direct registrations and the legacy adapters no longer used; narrow the 03.1 allowlist. Build/relaunch, visual/accessibility comparison and commit.

## Task 03.4: Media and remote SwiftUI UI with a controlled lifetime

**Files:** create Addons/Media/Manifest.json, MediaProvider.swift, MediaExpandedScene.swift; CascadeKit/Sources/CascadeContracts/Presentation/RemoteSceneDescriptor.swift; Sources/CascadeRuntime/Presentation/RemoteSceneCoordinator.swift and Tests/CascadeRuntimeIntegrationTests/RemoteSceneLifecycleTests.swift, MediaAddonTests.swift under CascadeKit; CascadeKit/Sources/CascadeKit/Core/AddonPresentation/RemoteSceneContainer.swift; scripts/test-addon-scenes.sh. Change Cascade/Integrations/Media/, Audio/, CascadeServices.swift; migrate Cascade/Features/MediaLiveActivity.swift, MusicArtworkDecoder.swift, MusicPlaybackPresentation.swift, MusicProgressSlider.swift, AudioOutputPicker.swift and related helpers when the scene needs them.

**Interfaces:** RemoteSceneDescriptor declares sceneID, PublicationID, compatible version and an ordinary fallback document. `RemoteSceneCoordinator.open(_ descriptor: RemoteSceneDescriptor) async throws -> SceneSession`; `close(_ sessionID: UUID) async`. SceneSession contains a verified identity and a presentation lease; the bridge hosts only an authenticated controller returned by the P0 adapter. The opening message includes a single-use token bound to owner, publication and generation, not an arbitrary endpoint supplied by the UI.

- [ ] Write RemoteSceneLifecycleTests: fast open/close, revocation during mount, scene crash, slow process, response from a previous generation, resize, display change and focus. At most one remote scene; when it is hidden the lease ends, any purely visual resources are released and the valid ordinary content stays.
- [ ] Bring the adapter demonstrated in 00.3 into production, with isolation by macOS API availability and a fallback. The advanced interface really uses SwiftUI in the extension process; no AnyView crosses the channel. If the transport requires a remote view distinct from the provider, both processes count toward the addon's total budget.
- [ ] Register the public services media.metadata, media.playbackControl and audio.spectrum with distinct scopes. Do not expose AppleScript controllers, private events or audio capture objects directly: the service offers specific authorized operations. The macOS APIs used keep the platform's compatibility/TCC constraints.
- [ ] Migrate compact content, artwork, progress and controls to the SDK model; playback time represented with a time base/revision, with no per-frame messages. The renderer uses public components for the ordinary state; the advanced SwiftUI scene handles the interactions that need it, keeping a useful fallback.
- [ ] Tie the audio analysis to an explicit lease of the visible surface. Two compatible consumers share the capture; hiding the last surface stops analysis and sample delivery. Reading the media events that are still needed stays a separate demand: do not tie all resources to a single visible boolean.
- [ ] Use the continuous profile initially only in qualification tests, until 04.3 establishes its measured limits. Sample/UI rate and buffers have maximums already checked in the tests; no exemption for the team's media player. Metadata, artwork and account keep scope and protection on the lock screen.
- [ ] Run RemoteSceneLifecycleTests, MediaAddonTests, `/bin/zsh scripts/test-addon-scenes.sh` and the regressions scripts/test-now-playing.sh, test-audio-spectrum.sh, test-music-artwork.sh, test-music-progress.sh. Verify manually VoiceOver, keyboard, menu, progress dragging, output change and Reduce Motion; report missing hardware/permissions.
- [ ] Remove the bypasses of the migrated widgets and the remaining entries of the related allowlist. Run check-addon-boundaries.sh, build/relaunch, the P3 report and commit. If a pre-existing function still requires a private privileged path, P3 is not finished: extend the common contract and verify it.
