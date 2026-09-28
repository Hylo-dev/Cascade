# Cascade: modular product map

ID: cascade-product
Labels: wayfinder:map
Status: open
Updated: 2026-09-27

## Destination

Define Cascade's global application plan, based on the existing code: a modular macOS notch with widgets and Live Activities provided by external apps. The global destination is a coherent set of decisions that makes it possible to write the subsystem specs and order the releases without inventing requirements. For the execution tranches admitted in the Notes, the destination includes implementation, independent evaluation and verified delivery of the authorized addon increments.

## Notes

- Redesign `48e682c` reviewed by the root: shelf within the standard size, closable, centered drop and horizontal row. Suite 1,447/1,447, app tests 9/9 and native previews verified; signed build restarted at PID 97319. The [UI](issues/92-file-shelf-primary-and-clear.md) and [drag](issues/91-file-shelf-native-drop-regression.md) tickets remain open only for the native QA described in the [record](../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md). Weekly reserve 87%.

- UI/UX review of 27 September: [ticket 92](issues/92-file-shelf-primary-and-clear.md) follows the Music reference and the Impeccable/Taste principles recorded in PRODUCT.md. Shelf with priority but closable, standard size, side top band and free center, centered drop, center→left→fan entrance, horizontal list without action buttons and return with an arrow. This decision replaces the permanent opening and the Clear in the list described in the history of 26 September. [Ticket 91](issues/91-file-shelf-native-drop-regression.md) includes verifying the fast drop before the animation.

- New explicit request from the user: [Make the shelf the main page and simplify its cards](issues/92-file-shelf-primary-and-clear.md) while it contains files, with **Clear** under Convert in the deck and the list, originals intact, icon and name only with no background, and animations preserved. Integration `5d852e7` reviewed, 7 signed app tests and suite 1,443/1,443 passed; the rendering in the real notch and Clear await a user test. The [drag regression](issues/91-file-shelf-native-drop-regression.md) remains a separate ticket.

- User test after the partial delivery: builds `c43b7af` and `43e83eb` did not capture; the Finder underneath offered "Replace". In the temporary A/B without the SkyLight pin, PID 69502 received native callbacks and drop `accepted=true`; the user saw files in the shelf and the manifest records `entries=1`, `revision=3`. The [final drag fix](issues/91-file-shelf-native-drop-regression.md) `5d852e7` keeps the visual pin and adds a receiver in the active Space; review, tests, build and restart at PID 74874 verified, the new drop still without a user test. The count of managed files excludes the external originals. The Shelf/Activity selector was removed on request. [The final verification](issues/90-file-shelf-local-delivery.md) remains blocked.

- Partial local delivery of 26 September 2026: the [final shelf verification](issues/90-file-shelf-local-delivery.md) remains open and awaits the fix of the incoming capture. Signed build, updated app and restart at PID 52683 verified; SwiftPM suite 1,416/1,416 and app tests 6/6 passed. QA of Finder and of the open notch not completed because of ScreenCaptureKit error `-3812` and the notch failing to open on AX clicks; do not infer real drag, cards, UI persistence or accessibility from these tests. Conversion and incoming promises still unavailable; external launcher blocked.

- Decision of 26 September 2026: the user authorizes the [directly integrated file shelf](../../docs/superpowers/specs/2026-09-26-file-shelf-design.md#9-integration-into-cascade), like the Music page, while the external addon launcher remains blocked. The [local plan](../../docs/superpowers/plans/2026-09-26-local-file-shelf.md) and its tickets set the first increment: drag-in with a pulse, animated four-card deck +N, animated list, persistence, originals preserved, outgoing copy and removal only on successful delivery. The occupied shelf is the default initial page without preventing manual navigation. Conversion deferred until supervision, cancellation and recovery; no UI declares it available in advance. Exception limited to the shelf, with no external addon code in the host process and no changes to grants, quotas or the native gate.

- File shelf tranche of 26 September 2026: the user asks to map all the remaining tasks of the [approved plan](../../docs/superpowers/plans/2026-09-26-file-shelf.md) and run them in several consecutive tickets with subagents, GPT-6 Sol for simple tasks and GPT-5.6 Sol for complex tasks, mandatory root review and a weekly reserve of at least 80%. For the file shelf only, this authorization takes priority over the historical thresholds and models of the previous tranches. The [already verified internal path](../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md) does not qualify the native mounting: launcher and gate remain blocked, with no bypass. The persistence, presentation and FFmpeg bundle tasks can advance independently of the native qualification. The shelf routing follows the approved spec; [the general arbitration between activities, pages and contexts](issues/08-context-arbitration.md) remains a separate, open decision.

- Explicit continuation of 25 September 2026: map and implement the multi-display notch according to the 24 September plan with subagents, tests and review. This tranche is authorized beyond the historical limits of the addon tranches and admits several consecutive execution tickets. The spec's proposals become reversible initial settings; active-window focus confirmed. No change to the addon launcher. Complex model GPT-5.6 Sol; simple model being clarified because "GPT-6 Sol" is not available.

- Current continuation of 20 September: Wayfinder exclusively for the addon system; consecutive execution tickets assigned to Sol medium or Terra according to difficulty, with root review and fixes before closing. Stop at a new necessary design choice or below 75% of the available weekly budget (more than 25% consumed). This threshold replaces the previous 20% cap; blocked launcher and native guarantees unchanged. No work on the tickets of other subsystems.

- Continuation of 20 September, instruction restated: work on several consecutive execution tickets in the same session; stop only at a necessary design decision or at the margin of the weekly 20% cap. The historical limit of one decision ticket does not limit the authorized execution increments.

- Continuation of 20 September: several increments admitted up to a necessary design decision or the weekly 20% cap, keeping the operating margin. Decision received: [keep the launcher blocked and the full exit guarantee](issues/22-managed-process-exit-proof.md). Policy choice resolved; technical proof still open, no exception and no ticket closed. The 00:00 deadline reported below belongs to the previous run of 18 September.

- Resumption of 19 September: continue with Ponytail, Sol medium/Terra models according to difficulty and root evaluation before each follow-up. New weekly Codex limit of 20%, which for this resumption replaces the previous waiver without a reserve. Only one bounded increment at a time; requirements and native gates unchanged.


- Deadline for the current continuation set by the user: stop the work at 00:00 Italian time on 19 September 2026 (18 September, 22:00 UTC), or earlier if the Codex limit is reached. The deadline also applies to the agents; it does not automatically close incomplete tickets.

- Execution continuation authorized on 18 September: after the asset completion, the user asks to continue the remaining tranches of the addon plan up to the Codex limit, exclusively with Codex agents and without the 35% reserve. The following implementation tranches can be tracked here; the previous exception limited to assets is extended by this instruction. Every delivery requires evidence and review; this authorization does not turn platform limits into guarantees and does not accept new risks. External publication and relaxing the native requirements remain separate.

- By default this map indexes the decisions; the implementations and verifications are in the [current addon plan](../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md). The realignment of 14 September keeps the global destination.
- Bounded execution exception of 15 September, for the request to continue with astra-pipeline in pi: the task "Connect the asset messages to the runtime and the SDK client" brings execution into the map and ends only once implementation and independent evaluation have passed. Routing updated on explicit request of 18 September: Codex only, with 5.6 Sol medium or other models according to difficulty; read-only independent review. The previous DeepSeek pipeline remains documented as history. It neither closes nor reopens the other decisions and does not enable the launcher, C0d, remote scenes or releases.
- The approved addon architecture and the subsequent contracts are set in context in [Define the widget and Live Activity contracts](issues/06-public-contract.md); the global tickets remain open where evidence or remaining choices are missing.
- Requirements and initial survey: [Project baseline](../../docs/wayfinder/context/project-baseline.md). The user's answers at kickoff are entry constraints, not artificially resolved tickets.
- Language: English. Prefer small contracts, contained resources and no blocking work on the main thread.
- Consult wayfinder, grilling and domain-modeling; research for research tickets and prototype for prototypes. Complementary skills can be consulted from the sources in [Map guide](../../docs/wayfinder/README.md).
- For the UI, consult impeccable when working on a prototype. No prototype is authorized to turn implicitly into an implementation.
- Tracker: [local conventions](../../docs/agents/issue-tracker.md). Open questions are found by querying the children; they are not duplicated here.
- Close at most one decision ticket per progress session; research is the exception. The initial session drew the map and resolved only research. Later progress is recorded in the tickets without closing tests that were not run.
- The other Sapphire features are references to evaluate, not automatic requirements.

## Decisions so far

- [Compose the local page and the per-item outgoing drag](issues/89-file-shelf-local-composition.md): app integration and per-entry delivery accepted after root review and 6 signed app tests; final build, restart and native QA in the delivery ticket.

- [Route the local shelf and recognize the incoming drag](issues/88-file-shelf-local-routing.md): contextual page and drag preview accepted after root review and 71 targeted tests; composition and native QA come later.

- [Prepare the local host and the shelf's verified copies](issues/87-file-shelf-local-host.md): facade and verified per-entry delivery accepted after root review and 73 independent tests; the native page and drag follow in the next ticket, without addon activation.

- [Prepare conversion formats and progress](issues/86-file-workspace-conversion-planning.md): bounded internal parser and presets, reviewed, 64 tests passed; job execution and recovery remain separate.

- [Prepare verified FFmpeg and ffprobe in the bundle](issues/81-file-workspace-ffmpeg-bundle.md): authenticated sources, signed arm64 helpers and real conversion verified; no native activation.

- [Add the shared component and the shelf's animated list](issues/80-file-workspace-presentation.md): schema 3 and shared renderer reviewed, 86 targeted tests and local native previews; mounting in the notch is separate.

- [Persist file shelf entries and receipts](issues/78-file-workspace-persistence.md): retention and per-item deliveries implemented and reviewed, with 50 targeted tests passed; native integration separate.

- [Define file collection and lifetime on the shelf](issues/10-file-shelf.md): approved spec for capture on drop, originals preserved, persistent references and verified per-item delivery; general context arbitration separate.

- [File shelf contracts and authorized boundary](issues/76-file-workspace-contracts.md): public models, SDK client and internal host authority verified by 21 targeted tests and review; native qualification separate.

- [Follow the active window with a pointer fallback](issues/70-focused-display.md): resolver and event-driven monitor implemented; 11 tests and review PASS, integration later.

- [Display persistence and Live Activity modes](issues/69-display-identity-routing.md): identity, preferences and logical inventory implemented; 13 tests and review with fixes, wiring later.

- [Define the notch's monitors, focus and interactions](issues/14-displays-input.md): permanent presence, exclusive opening, two software styles and three destinations for activities; active-window focus with pointer fallback.

- [Design the notch states and surfaces](issues/07-notch-surfaces.md): visual contracts consolidated and native Spotlight confirmed; local verification of focus, calculation and restore, with the general qualification still separate.

- [Define macOS compatibility and allowed integrations](issues/04-platform-policy.md): approved the default public path with private exceptions decided one by one; project minimum of 14 kept, qualification separate.

- [Load external SwiftUI widgets: mechanisms and limits](issues/01-swiftui-extensions.md): in-process bundles and ExtensionKit remote UI are distinct paths; format, compatibility and installation require a choice and a test.
- [Integrate macOS Spotlight, notifications and activities: feasibility](issues/02-macos-integrations.md): Spotlight customization and universal notifications have no verified public contract; media, audio, Bluetooth and ActivityKit must be treated as distinct capabilities.
- [Evaluate glass and audio from the Sapphire and FineTune sources](issues/03-sapphire-finetune.md): renderer and audio engine are identified; minimum versions, internal APIs and runtime behavior must be kept distinct from Cascade's requirements.

- [Choose the image transfer between addon and host](issues/21-asset-transfer.md): approved 64 KiB chunks over messages.

- [Connect the asset messages to the runtime and the SDK client](issues/23-asset-message-integration.md): internal import/share/release path implemented and reviewed, 883 tests passed and signed delivery verified; native transport and C0d remain separate.

- [Generate a buildable SDK addon project](issues/24-sdk-source-scaffold.md): source generator reviewed, independent build and 896 tests passed; signed delivery and restart verified.

- [Observe a process's resources without enabling the launcher](issues/25-process-resource-observations.md): reader and reducer reviewed, 929 tests passed and delivery verified; native enforcement still separate.

- [Create the Focus example with the public SDK only](issues/26-standalone-focus-source.md): independent library reviewed, 37 tests passed and external build; the native container and parity remain to be qualified.

- [Show consuming a service through the public SDK](issues/27-service-consumer-source.md): synthetic source pair reviewed, independent build and 16 tests passed; no availability of a real service or native authority inferred.

- [Connect the SDK storage client to the message path](issues/28-storage-message-client.md): concrete client reviewed, 955 tests / 87 suites, examples updated and signed delivery verified.

- [Manage the SDK lifecycle of service invocations](issues/29-service-invocation-lifecycle.md): correlation and uncertainty reviewed with the canonical bridge, 978 tests / 89 suites and signed delivery verified.

- [Define and implement the dedicated service invocation messages](issues/30-service-invocation-frames.md): bounded codecs reviewed, 990 tests / 90 suites and signed delivery; no protocol activation.

- [Independently verify the CPU metric units](issues/32-process-cpu-calibration.md): POSIX comparison on exact copies of the reviewed reader/reducer PASS, limited to macOS 27 arm64/self-process.

- [Connect service invocations to the runtime and the SDK exchange](issues/31-service-invocation-host.md): internal path reviewed, 1,034 tests / 93 suites and signed delivery with restart verified; complete client and native separate.

- [Define the service control and update messages](issues/33-service-subscription-frames.md): closed contracts reviewed, 1,048 tests / 94 suites and signed delivery; no 1.4 activation.

- [Document addon compatibility, performance and distribution](issues/36-addon-developer-guides.md): three linked guides, sources verified and independent review PASS; native qualifications separate.

- [Verify the public boundaries of the SDK and the examples](issues/35-sdk-boundary-check.md): source check delivered, 20 tests and review PASS; original audit 3 packages/9 targets/88 sources/132 imports, extended with StandaloneClock in the next increment.

- [Verify the real dependencies of the ServiceConsumer manifests](issues/38-service-consumer-manifest-resolution.md): 7 tests/8 cases with the real resolver and review PASS; source proof separate from native parity.

- [Complete the service client, subscriptions and updates](issues/34-service-subscriptions-host-sdk.md): final review PASS, 1,084 tests/96 suites, Release and signed delivery with restart verified; 1.4 only for the complete assembly, native open.

- [Run the SDK check before the development build](issues/37-required-sdk-build-check.md): four fixtures and review PASS; mandatory check 3 packages/9 targets/88 sources/132 imports followed by a successful signed build and restart.

- [Verify the pre-tracing bootstrap abort offline](issues/39-bootstrap-abort-offline.md): 31 tests and review PASS; model and observations only synthetic, physical exit and native gate unchanged.

- [Implement the C bootstrap with a pre-tracing abort](issues/40-bootstrap-abort-c.md): candidate compiled and C check with sanitizers PASS after root review; POSIX main not run, native gate unchanged.

- [Connect the remote counter to the prototype's authenticated channel](issues/41-remote-scene-counter.md): local logic and signed build of the three targets verified, with root review; activation and qualification of the scene remain separate.

- [Verify and complete the counter lifecycle in the provider](issues/42-counter-provider-lifecycle.md): terminality defect reproduced and fixed; real callbacks verified in memory, separate signed build; native qualification separate.
- [Verify and complete the counter receiver lifecycle](issues/43-counter-host-lifecycle.md): terminality defect reproduced and fixed; real callbacks verified in memory, separate signed build; native qualification separate.

- [Prepare the Clock provider with the public SDK only](issues/44-standalone-clock-source.md): independent build, 3 Swift tests, 21 checker tests and 5 build fixtures PASS after root review; audit extended to 4 packages, no native qualification.

- [Sample the active addon processes together](issues/45-process-metrics-coordinator.md): internal coordinator reviewed, 47 metrics tests and 1,098 full tests PASS, signed build and restart verified; native binding/enforcement separate.

- [Clarify how a CPU burst consumes the addon budget](issues/46-addon-cpu-burst-policy.md): approved a shared 100 ms credit with a 5 ms/s refill, retained across jobs and provider restarts, in place of the rigid sliding window.

- [Implement the addon's shared CPU credit](issues/47-addon-cpu-credit.md): internal account with monotonic refill, retained debt and 12 tests; observational wiring separate.

- [Connect the CPU credit to the shared observations](issues/48-addon-cpu-accounting.md): shared accounts retained in the coordinator, incomplete measurements and persistent failures kept distinct; reviews PASS, 71 targeted tests and 1,122 full tests.

- [Define when CPU overruns become distinct violations](issues/49-addon-cpu-violation-counting.md): approved counting new consumption beyond credit, once per addon and round; residual debt without new consumption excluded.

- [Classify new CPU consumption beyond credit](issues/50-addon-cpu-violation-classification.md): classification per owner and round, idle debt excluded and partial data explicit; reviews PASS and 76 targeted tests.

- [Connect CPU overruns to runtime health](issues/51-addon-runtime-cpu-health.md): internal composition with per-incarnation sessions, retained history and shared cleanup; reviews PASS, 100 targeted tests and 1,135 full tests. Reduction of new admissions still to be defined.

- [Define the reduction of new work after a CPU overrun](issues/52-addon-cpu-reduced-admission.md): approved immediate refusal until positive credit is proven by complete measurements, with no new queue/replay; work already admitted is kept.

- [Apply the temporary refusal of new addon work](issues/53-addon-cpu-admission.md): new admissions blocked until measured positive credit, work already admitted and active sources preserved; reviews PASS and 191 targeted tests.

- [Connect the addon measurements to the shared deadline](issues/54-addon-metrics-deadline.md): fifth aggregate without a timer, coalescing wake and stale reads guarded; reviews PASS, 118 targeted tests and 1,153 full tests/104 suites.

- [Define the CPU attribution of services to consumers](issues/55-addon-delegated-cpu-attribution.md): conservative choice approved; the full interval to each active consumer, the process counted only once in the physical total.

- [Charge CPU intervals to verified consumers](issues/56-addon-delegated-cpu-accounting.md): coordinator extended without duplicate accounts or measurements, atomic preflight and persistent debt; reviews PASS, 126 targeted tests and 1,161 full/105 suites. Canonical producer still separate.

- [Decide CPU attribution in service chains](issues/57-addon-transitive-cpu-attribution.md): conservative propagation approved along simultaneously active interests, deduplicated by identity and process; no unused static dependencies.

- [Retain the CPU recipients of active chains](issues/58-addon-cpu-attribution-ledger.md): bounded temporal ledger reviewed, 9 new tests and 29 targeted PASS; deduplication and absence of phantom chains verified.

- [Connect the chain ledger to the CPU measurements](issues/59-addon-coordinator-attribution-ledger.md): domain preflight, synchronized observations and per-process provenance; reviews with no findings and 49 targeted tests PASS.

- [Connect the canonical interests to CPU accounting](issues/60-addon-broker-attribution-ledger.md): commits/removals wired to the ledger, retention beyond disconnect/exit and pausing of new interests only; 39 targeted tests PASS, reviews with no findings.

- [Prepare the demand and tickets for crash retries](issues/62-addon-crash-retry-projections.md): bounded projections/cancellation and canonical demand reviewed, 4 dedicated tests PASS; no autonomous relaunch wired yet.

- [Apply delegated CPU to addon admissions and health](issues/61-addon-runtime-transitive-cpu.md): internal integration reviewed, ack v1.4 preserved, 1,195 tests/112 suites PASS; signed final delivery of the tranche and updated launch verified.

- [Connect crash retries to the shared deadline](issues/63-addon-runtime-crash-retry.md): internal 1/5/30 seconds composition with current demand and single-use consumption, reviews PASS and 1,209 tests/113 suites; launcher unchanged.

- [Define whom the observed memory of services is attributed to](issues/64-addon-memory-attribution.md): the observed footprint belongs only to the owner of the physical process and not to direct or transitive consumers; thresholds, episodes and actions of the provider alone are defined by ticket 65; UI and native gate remain separate.

- [Define provider RAM thresholds and incidents](issues/65-addon-provider-memory-policy.md): progressive 64/96 MiB profile approved, implemented and verified in tickets 66/67; launcher blocked.

- [Classify provider memory episodes](issues/66-provider-memory-episodes.md): per-incarnation classifier verified, three tests and double review PASS; runtime integration verified in 67.

- [Connect provider memory, health and admissions](issues/67-runtime-provider-memory.md): owner-only composition verified, reviews PASS, 1,222 tests/115 suites and signed delivery; no native activation.

- [Verify lifetime management through launchd](issues/68-launchd-managed-lifetime-research.md): sources and SDK do not establish the required constraint; research concluded, native test still blocked with no change to the policy.

- [Share Live Activity selection and lifecycle](issues/71-shared-live-activity.md): independent selections, shared per-instance activation and revocation of ended copies verified.

- [Keep the panels and arbitrate a single opening](issues/72-persistent-display-panels.md): persistent surfaces, a single owner and arbitrated auxiliary interactions; review and targeted tests passed.

- [Design the software Notch and the droplet Dynamic Island](issues/73-software-notch-geometry.md): silhouettes, transitions and contexts verified; review PASS and renderer comparison approved.

- [Connect display preferences and auxiliary surfaces](issues/74-display-settings.md): native preferences, contextual anchors and Spotlight reservations integrated; positive review, full delivery verification separate.

- [Verify and deliver the multi-display notch](issues/75-multi-display-verification.md): positive cross-cutting review, signed build and restart verified; test outcomes and native limits logged in the record.

## Not yet specified

- Details of the data and preference migrations of future modules: the application schemas are pinned down once the modules and their real consumers are defined. The addon persistence already chosen is not to be reopened here.
- Exceptional combinations of capabilities and permissions of future extensions, to be surfaced during integration tests and the definition of the modules.

## Out of scope

- External publication of the app or the SDK and creating a Homebrew release without the corresponding assignment; the local tranches of the addon plan are admitted by the continuation in the Notes.
- Indiscriminate parity with all the features of Sapphire or FineTune: beyond the requested features, every addition requires an explicit choice.

## Comments

- 15 September 2026: The Astra evaluation of [Connect the asset messages to the runtime and the SDK client](issues/23-asset-message-integration.md) is PARTIAL. Pipeline paused at the user's request after the first corrective worker; the ticket keeps the evidence, the limits and the resumption point. No global decision or qualification is closed by this progress.
- 15 September 2026, resumption: The user again authorized continuing the task [Connect the asset messages to the runtime and the SDK client](issues/23-asset-message-integration.md), with a 35% GPT reserve and DeepSeek credit available. Work restarts from the checkpoint, without reopening choices already resolved.
- 15 September 2026, budget stop: [Connect the asset messages to the runtime and the SDK client](issues/23-asset-message-integration.md) is suspended at the 35% GPT reserve. Last evaluation PARTIAL; the ticket links the checkpoint and the details of the interrupted worker. No active subagent and no approved delivery.

- 17 September 2026: Resumption of [Connect the asset messages to the runtime and the SDK client](issues/23-asset-message-integration.md) authorized with an explicit waiver of the 35% GPT reserve; the independent evaluation before delivery is still required.

- 18 September 2026: For [Connect the asset messages to the runtime and the SDK client](issues/23-asset-message-integration.md), the user replaces the DeepSeek pipeline with Codex agents chosen according to difficulty; 35% waiver active, technical criteria unchanged.

### Shelf refinement: 27 September

[Main shelf and cards](issues/92-file-shelf-primary-and-clear.md): compact fan, return with the reverse gesture and Xcode preview on the real component. Root review, 20 targeted tests, signed build and restart at PID 5063; Canvas awaits Xcode setup, native trackpad QA pending.

[Shelf and cards](issues/92-file-shelf-primary-and-clear.md): new refinement with stepped focus, multiple selection, fade, drag of all/selected and authorized renaming of the original. Root review, 1,452 SwiftPM tests and 17 app tests passed; the native test remains separate.
