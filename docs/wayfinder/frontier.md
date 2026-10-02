# Cascade decision frontier

> **Superseded record.** The [plugin engine spec](../superpowers/specs/2026-09-29-plugin-engine-design.md) of 29 September 2026 supersedes the addon frontier below, and the addon runtime and its SDK were deleted on 2 October 2026. This page is a dated record and is not kept current.

Updated as of 27 September 2026 and derived from the ticket metadata. The [map](../../.scratch/cascade-product/map.md) stays canonical; this view does not keep the resolutions.

92 tickets: 69 resolved, 0 in progress, 7 available, 16 blocked.

Decision of 20 September: the user keeps the launcher blocked and the full requirement for the exit of managed processes. The [choice is recorded](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md); the technical proof stays open, without a new request for the same exception.


In the checkpoint of 20 September the surface decisions and the local native verification of Spotlight/settings are concluded: native field and calculation, focus and restore observed. Toggle set back to off, launcher blocked, last verified relaunch PID 10620. [Outcomes and limits](../superpowers/verification/2026-09-20-spotlight-native-continuation.md). [The general arbitration between activities, pages and contexts](../../.scratch/cascade-product/issues/08-context-arbitration.md) stays open; the shelf's behavior follows its approved specification.

## Available decisions and tasks

The retention decision and the routing limited to the shelf are fixed by the approved specification; the general precedence between activities and contexts remains open. The launcher stays blocked. Persistence, shared component and FFmpeg bundle are concluded; the native qualification waits on the platform proofs.

- [Decide priorities between activities, pages and context](../../.scratch/cascade-product/issues/08-context-arbitration.md)
- [Define the connection between Spotlight and the notch](../../.scratch/cascade-product/issues/12-spotlight-experience.md)
- [Probe an external SwiftUI UI inside the notch](../../.scratch/cascade-product/issues/19-extension-host-probe.md)
- [Probe per-app routing and simultaneous outputs](../../.scratch/cascade-product/issues/20-audio-routing-probe.md)
- [Define a safe proof of managed process exit](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md)
- [Fix file acquisition in the shelf's native drag](../../.scratch/cascade-product/issues/91-file-shelf-native-drop-regression.md)
- [Make the shelf the main page and simplify its cards](../../.scratch/cascade-product/issues/92-file-shelf-primary-and-clear.md)

"Available" means that the ticket can be taken on. The proofs of the managed processes and of the SwiftUI scene stay separate; no availability opens the native gate.

## Mapped file-shelf tranche

New UI/interaction tranche reviewed: large icons, colored actions, discreet focus, multiple selection, Delete with a fade, full/selective drag and rename of the original. 1,452 SwiftPM tests and 17 app tests passed; weekly reserve 85%. The [shelf ticket](../../.scratch/cascade-product/issues/92-file-shelf-primary-and-clear.md) stays open for native QA.

Subsequent refinement of the fan and the reverse gesture reviewed; native SwiftUI preview added. Focused tests 8 renderer + 12 app passed, signed build and relaunch PID 5063. Canvas blocked by the initial Xcode setup; physical trackpad test pending.

[Prepare conversion formats and progress](../../.scratch/cascade-product/issues/86-file-workspace-conversion-planning.md) is also concluded: 64 independent tests passed, signed build and relaunch PID 34695 verified. The complete conversion keeps its native requirements; no production activation.

In the [authorized local plan](../superpowers/plans/2026-09-26-local-file-shelf.md), host, page/input and composition/output are resolved after root review and tests. The A/B without the SkyLight pin received native callbacks and the user saw a file in the shelf; the manifest contains one entry, while the final receiver is reviewed and tested, with a manual test pending. The [final verification](../../.scratch/cascade-product/issues/90-file-shelf-local-delivery.md) stays blocked by the [drag](../../.scratch/cascade-product/issues/91-file-shelf-native-drop-regression.md). The [shelf design](../../.scratch/cascade-product/issues/92-file-shelf-primary-and-clear.md) and the fix for the fast drag are integrated in `48e682c`: root review, 1,447 SwiftPM tests and 9 app tests passed, previews examined, signed build and relaunch PID 97319 verified. The native proof in the notch and in Finder stays pending; weekly reserve 87%. This tranche does not open the addon launcher and does not enable Convert.

The three independent tasks are concluded: persistence, shared component and [verified FFmpeg bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md). Signed build and relaunch of the previous delivery PID 27461 verified; weekly reserve 93%. The remaining shelf tickets wait on the native qualification, without reopening the launcher.

[Approved plan](../superpowers/plans/2026-09-26-file-shelf.md): internal service boundary completed; persistence, presentation and FFmpeg bundle completed. Real drag, conversions, composition and integrated verification follow the DAG in the table. The [runtime verification](../superpowers/verification/2026-09-26-file-workspace-runtime.md) does not qualify the production path.

## Concluded multi-display tranche

[Multi-display notch plan](../superpowers/plans/2026-09-24-multi-display-notch.md): all seven execution tickets of the tranche are resolved; the build and relaunch of the delivery are recorded in the final ticket.

## Earlier addon research

[Lifetime management through launchd](research/2026-09-23-launchd-managed-lifetime.md): Sol medium research and root review concluded. It does not establish the exit constraint already required; no code or gate changed. Relaunch of the unchanged build verified PID 22870, remaining quota 77%.

## Earlier addon deliveries

[Provider RAM](../superpowers/verification/2026-09-23-addon-provider-memory.md): Terra/Sol medium, root and independent reviews PASS, 1,222 tests/115 suites, signed build from 500 inputs and updated launch PID 21839 verified; app already closed. Remaining quota 77%. Only tasks that depend on the suspended native proofs follow; launcher blocked.


[Transitive CPU and recovery after a crash](../superpowers/verification/2026-09-22-addon-transitive-cpu.md): six execution increments with Sol/Terra medium, root and independent reviews PASS. 1,209 tests/113 suites, official signed build from 497 verified inputs and updated launch PID 62002; app already closed before the delivery. Remaining quota 79%. Next choice: RAM attribution; launcher blocked.

[Delegated CPU accounting](../superpowers/verification/2026-09-22-addon-delegated-cpu.md): conservative formula approved and coordinator implemented by Sol medium, root and independent Sol reviews PASS. 126 focused tests, 1,161 full tests/105 suites, official signed build from 488 verified inputs and relaunch PID 46952. Remaining budget 86%. The connection to the broker waits on [the choice on service chains](../../.scratch/cascade-product/issues/57-addon-transitive-cpu-attribution.md); launcher blocked.

[CPU admission and common deadlines](../superpowers/verification/2026-09-21-addon-cpu-admission.md): two tickets implemented with Sol/Terra medium and root/independent reviews PASS. 1,153 tests/104 suites, official signed build from 487 verified inputs and stable launch PID 42941; Cascade was already closed before the launch. Weekly remainder 87%. Next choice: [CPU attribution of services to consumers](../../.scratch/cascade-product/issues/55-addon-delegated-cpu-attribution.md). Launcher blocked.

[CPU violations and runtime health](../superpowers/verification/2026-09-21-addon-cpu-violations.md): 100 focused tests and 1,135 package tests in 101 suites PASS, root and independent reviews, official signed build and verified relaunch PID 32112. Weekly remainder 90%; next point: refusal and reopening of new work after an overrun. Quarantine internal for now, launcher blocked.

[Shared CPU credit and observational connection](../superpowers/verification/2026-09-20-addon-cpu-credit.md): 71 focused tests, 1,122 package tests in 99 suites, root and independent reviews PASS; official signed build, Applications link updated and verified relaunch PID 25071. Remaining budget 92%; launcher blocked and sanctions not yet connected.

[Sample the active addon processes together](../../.scratch/cascade-product/issues/45-process-metrics-coordinator.md): 47 metrics tests, 1,098 package tests/97 suites, root and independent review PASS; official signed build and verified relaunch. The component does not enable the launcher or the enforcement.

[Prepare the Clock provider with the public SDK only](../../.scratch/cascade-product/issues/44-standalone-clock-source.md): 3 Swift tests, 21 checker tests, 5 build fixtures and root review PASS; audit 4 packages/11 targets/90 sources/140 imports. Relaunch of the existing signed build verified. The subsequent [choice of Spotlight's native sizes](context/2026-09-20-notch-surfaces-checkpoint.md) was approved; the qualification remains, without reopening the launcher.

[Complete service client and subscription host](../../.scratch/cascade-product/issues/34-service-subscriptions-host-sdk.md): 1084 tests/96 suites and Release PASS, final review, Apple Development build and relaunch PID 85871 verified. Protocol 1.4 requires the complete cumulative assembly; the native qualification stays open.

[Mandatory SDK check in the build](../../.scratch/cascade-product/issues/37-required-sdk-build-check.md): four fixtures and review PASS; the delivered build checks 3 packages/9 targets/88 sources/132 imports before Xcode.

## Full status

| Decision, research or task | Status | Waiting on |
| --- | --- | --- |
| [Load external SwiftUI widgets: mechanisms and limits](../../.scratch/cascade-product/issues/01-swiftui-extensions.md) | Resolved | None |
| [Integrate Spotlight, notifications and macOS activities: feasibility](../../.scratch/cascade-product/issues/02-macos-integrations.md) | Resolved | None |
| [Assess glass and audio from the Sapphire and FineTune sources](../../.scratch/cascade-product/issues/03-sapphire-finetune.md) | Resolved | None |
| [Define macOS compatibility and allowed integrations](../../.scratch/cascade-product/issues/04-platform-policy.md) | Resolved | None |
| [Define extension installation and isolation](../../.scratch/cascade-product/issues/05-extension-distribution.md) | Blocked | [Load external SwiftUI widgets: mechanisms and limits](../../.scratch/cascade-product/issues/01-swiftui-extensions.md); [Define macOS compatibility and allowed integrations](../../.scratch/cascade-product/issues/04-platform-policy.md); [Probe an external SwiftUI UI inside the notch](../../.scratch/cascade-product/issues/19-extension-host-probe.md); [Define a safe proof of managed process exit](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) |
| [Define the widget and Live Activity contracts](../../.scratch/cascade-product/issues/06-public-contract.md) | Blocked | [Define extension installation and isolation](../../.scratch/cascade-product/issues/05-extension-distribution.md) |
| [Design the notch states and surfaces](../../.scratch/cascade-product/issues/07-notch-surfaces.md) | Resolved | None |
| [Decide priorities between activities, pages and context](../../.scratch/cascade-product/issues/08-context-arbitration.md) | Available | None |
| [Define grid, pages and widget customization](../../.scratch/cascade-product/issues/09-grid-pages.md) | Blocked | [Define the widget and Live Activity contracts](../../.scratch/cascade-product/issues/06-public-contract.md); [Design the notch states and surfaces](../../.scratch/cascade-product/issues/07-notch-surfaces.md) |
| [Define collection and retention of files in the shelf](../../.scratch/cascade-product/issues/10-file-shelf.md) | Resolved | None |
| [Define notifications from other apps and device notices](../../.scratch/cascade-product/issues/11-notification-experience.md) | Blocked | [Integrate Spotlight, notifications and macOS activities: feasibility](../../.scratch/cascade-product/issues/02-macos-integrations.md); [Define macOS compatibility and allowed integrations](../../.scratch/cascade-product/issues/04-platform-policy.md); [Decide priorities between activities, pages and context](../../.scratch/cascade-product/issues/08-context-arbitration.md) |
| [Define the connection between Spotlight and the notch](../../.scratch/cascade-product/issues/12-spotlight-experience.md) | Available | None |
| [Define the contextual audio manager](../../.scratch/cascade-product/issues/13-audio-experience.md) | Blocked | [Assess glass and audio from the Sapphire and FineTune sources](../../.scratch/cascade-product/issues/03-sapphire-finetune.md); [Define macOS compatibility and allowed integrations](../../.scratch/cascade-product/issues/04-platform-policy.md); [Decide priorities between activities, pages and context](../../.scratch/cascade-product/issues/08-context-arbitration.md); [Probe per-app routing and simultaneous outputs](../../.scratch/cascade-product/issues/20-audio-routing-probe.md) |
| [Define monitors, focus and notch interactions](../../.scratch/cascade-product/issues/14-displays-input.md) | Resolved | None |
| [Design settings and integration management](../../.scratch/cascade-product/issues/15-settings-experience.md) | Blocked | [Define extension installation and isolation](../../.scratch/cascade-product/issues/05-extension-distribution.md); [Define grid, pages and widget customization](../../.scratch/cascade-product/issues/09-grid-pages.md); [Define collection and retention of files in the shelf](../../.scratch/cascade-product/issues/10-file-shelf.md); [Define notifications from other apps and device notices](../../.scratch/cascade-product/issues/11-notification-experience.md); [Define the connection between Spotlight and the notch](../../.scratch/cascade-product/issues/12-spotlight-experience.md); [Define the contextual audio manager](../../.scratch/cascade-product/issues/13-audio-experience.md); [Define monitors, focus and notch interactions](../../.scratch/cascade-product/issues/14-displays-input.md) |
| [Define budgets, isolation and failure recovery](../../.scratch/cascade-product/issues/16-resource-contract.md) | Blocked | [Define extension installation and isolation](../../.scratch/cascade-product/issues/05-extension-distribution.md); [Define the widget and Live Activity contracts](../../.scratch/cascade-product/issues/06-public-contract.md); [Define the contextual audio manager](../../.scratch/cascade-product/issues/13-audio-experience.md) |
| [Order the releases and define the completion criteria](../../.scratch/cascade-product/issues/17-delivery-roadmap.md) | Blocked | [Define the widget and Live Activity contracts](../../.scratch/cascade-product/issues/06-public-contract.md); [Decide priorities between activities, pages and context](../../.scratch/cascade-product/issues/08-context-arbitration.md); [Define grid, pages and widget customization](../../.scratch/cascade-product/issues/09-grid-pages.md); [Define collection and retention of files in the shelf](../../.scratch/cascade-product/issues/10-file-shelf.md); [Define notifications from other apps and device notices](../../.scratch/cascade-product/issues/11-notification-experience.md); [Define the connection between Spotlight and the notch](../../.scratch/cascade-product/issues/12-spotlight-experience.md); [Define the contextual audio manager](../../.scratch/cascade-product/issues/13-audio-experience.md); [Define monitors, focus and notch interactions](../../.scratch/cascade-product/issues/14-displays-input.md); [Design settings and integration management](../../.scratch/cascade-product/issues/15-settings-experience.md); [Define budgets, isolation and failure recovery](../../.scratch/cascade-product/issues/16-resource-contract.md); [Define Now Playing and the first Live Activities](../../.scratch/cascade-product/issues/18-media-live-activities.md) |
| [Define Now Playing and the first Live Activities](../../.scratch/cascade-product/issues/18-media-live-activities.md) | Blocked | [Integrate Spotlight, notifications and macOS activities: feasibility](../../.scratch/cascade-product/issues/02-macos-integrations.md); [Define macOS compatibility and allowed integrations](../../.scratch/cascade-product/issues/04-platform-policy.md); [Define the widget and Live Activity contracts](../../.scratch/cascade-product/issues/06-public-contract.md); [Decide priorities between activities, pages and context](../../.scratch/cascade-product/issues/08-context-arbitration.md) |
| [Probe an external SwiftUI UI inside the notch](../../.scratch/cascade-product/issues/19-extension-host-probe.md) | Available | None |
| [Probe per-app routing and simultaneous outputs](../../.scratch/cascade-product/issues/20-audio-routing-probe.md) | Available | None |
| [Choose the image transfer between addon and host](../../.scratch/cascade-product/issues/21-asset-transfer.md) | Resolved | None |
| [Define a safe proof of managed process exit](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) | Available | None |
| [Connect asset messages to the runtime and the SDK client](../../.scratch/cascade-product/issues/23-asset-message-integration.md) | Resolved | None |
| [Generate a compilable addon SDK project](../../.scratch/cascade-product/issues/24-sdk-source-scaffold.md) | Resolved | None |
| [Observe a process's resources without enabling the launcher](../../.scratch/cascade-product/issues/25-process-resource-observations.md) | Resolved | None |
| [Create the Focus example with the public SDK only](../../.scratch/cascade-product/issues/26-standalone-focus-source.md) | Resolved | None |
| [Show the consumption of a service through the public SDK](../../.scratch/cascade-product/issues/27-service-consumer-source.md) | Resolved | None |
| [Connect the SDK storage client to the message path](../../.scratch/cascade-product/issues/28-storage-message-client.md) | Resolved | None |
| [Manage the SDK lifecycle of service invocations](../../.scratch/cascade-product/issues/29-service-invocation-lifecycle.md) | Resolved | None |
| [Define and implement the messages dedicated to service invocations](../../.scratch/cascade-product/issues/30-service-invocation-frames.md) | Resolved | None |
| [Connect service invocations to the runtime and to the SDK exchange](../../.scratch/cascade-product/issues/31-service-invocation-host.md) | Resolved | None |
| [Independently verify the units of the CPU metrics](../../.scratch/cascade-product/issues/32-process-cpu-calibration.md) | Resolved | None |
| [Define the service control and update messages](../../.scratch/cascade-product/issues/33-service-subscription-frames.md) | Resolved | None |
| [Complete the service client, subscriptions and updates](../../.scratch/cascade-product/issues/34-service-subscriptions-host-sdk.md) | Resolved | None |
| [Verify the public boundaries of the SDK and of the examples](../../.scratch/cascade-product/issues/35-sdk-boundary-check.md) | Resolved | None |
| [Document addon compatibility, performance and distribution](../../.scratch/cascade-product/issues/36-addon-developer-guides.md) | Resolved | None |
| [Run the SDK check before the development build](../../.scratch/cascade-product/issues/37-required-sdk-build-check.md) | Resolved | None |
| [Verify the real dependencies of the ServiceConsumer manifests](../../.scratch/cascade-product/issues/38-service-consumer-manifest-resolution.md) | Resolved | None |
| [Verify offline the bootstrap abort before tracing](../../.scratch/cascade-product/issues/39-bootstrap-abort-offline.md) | Resolved | None |
| [Implement the C bootstrap with abort before tracing](../../.scratch/cascade-product/issues/40-bootstrap-abort-c.md) | Resolved | None |
| [Connect the remote counter to the prototype's authenticated channel](../../.scratch/cascade-product/issues/41-remote-scene-counter.md) | Resolved | None |
| [Verify and complete the counter lifecycle in the provider](../../.scratch/cascade-product/issues/42-counter-provider-lifecycle.md) | Resolved | None |
| [Verify and complete the lifecycle of the counter receiver](../../.scratch/cascade-product/issues/43-counter-host-lifecycle.md) | Resolved | None |
| [Prepare the Clock provider with the public SDK only](../../.scratch/cascade-product/issues/44-standalone-clock-source.md) | Resolved | None |
| [Sample the active addon processes together](../../.scratch/cascade-product/issues/45-process-metrics-coordinator.md) | Resolved | None |
| [Clarify how the CPU burst consumes the addon budget](../../.scratch/cascade-product/issues/46-addon-cpu-burst-policy.md) | Resolved | None |
| [Implement the addon's shared CPU credit](../../.scratch/cascade-product/issues/47-addon-cpu-credit.md) | Resolved | None |
| [Connect the CPU credit to the common observations](../../.scratch/cascade-product/issues/48-addon-cpu-accounting.md) | Resolved | None |
| [Define when CPU overruns become distinct violations](../../.scratch/cascade-product/issues/49-addon-cpu-violation-counting.md) | Resolved | None |
| [Classify new CPU consumption beyond the credit](../../.scratch/cascade-product/issues/50-addon-cpu-violation-classification.md) | Resolved | None |
| [Connect CPU overruns to runtime health](../../.scratch/cascade-product/issues/51-addon-runtime-cpu-health.md) | Resolved | None |
| [Define the reduction of new work after a CPU overrun](../../.scratch/cascade-product/issues/52-addon-cpu-reduced-admission.md) | Resolved | None |
| [Apply the temporary refusal of new addon work](../../.scratch/cascade-product/issues/53-addon-cpu-admission.md) | Resolved | None |
| [Connect the addon measurements to the common deadline](../../.scratch/cascade-product/issues/54-addon-metrics-deadline.md) | Resolved | None |
| [Define the CPU attribution of services to consumers](../../.scratch/cascade-product/issues/55-addon-delegated-cpu-attribution.md) | Resolved | None |
| [Charge CPU intervals to the verified consumers](../../.scratch/cascade-product/issues/56-addon-delegated-cpu-accounting.md) | Resolved | None |
| [Decide the CPU attribution in service chains](../../.scratch/cascade-product/issues/57-addon-transitive-cpu-attribution.md) | Resolved | None |
| [Keep the CPU recipients of the active chains](../../.scratch/cascade-product/issues/58-addon-cpu-attribution-ledger.md) | Resolved | None |
| [Connect the chain ledger to the CPU measurements](../../.scratch/cascade-product/issues/59-addon-coordinator-attribution-ledger.md) | Resolved | None |
| [Connect the canonical interests to CPU accounting](../../.scratch/cascade-product/issues/60-addon-broker-attribution-ledger.md) | Resolved | None |
| [Apply delegated CPU to addon admissions and health](../../.scratch/cascade-product/issues/61-addon-runtime-transitive-cpu.md) | Resolved | None |
| [Prepare the question and tickets for retries after a crash](../../.scratch/cascade-product/issues/62-addon-crash-retry-projections.md) | Resolved | None |
| [Connect retries after a crash to the common deadline](../../.scratch/cascade-product/issues/63-addon-runtime-crash-retry.md) | Resolved | None |
| [Define whom to attribute the observed memory of services to](../../.scratch/cascade-product/issues/64-addon-memory-attribution.md) | Resolved | None |
| [Define provider RAM thresholds and incidents](../../.scratch/cascade-product/issues/65-addon-provider-memory-policy.md) | Resolved | None |
| [Classify provider memory episodes](../../.scratch/cascade-product/issues/66-provider-memory-episodes.md) | Resolved | None |
| [Connect provider memory, health and admissions](../../.scratch/cascade-product/issues/67-runtime-provider-memory.md) | Resolved | None |
| [Verify lifetime management through launchd](../../.scratch/cascade-product/issues/68-launchd-managed-lifetime-research.md) | Resolved | None |
| [Display persistence and Live Activity modes](../../.scratch/cascade-product/issues/69-display-identity-routing.md) | Resolved | None |
| [Follow the active window with fallback to the pointer](../../.scratch/cascade-product/issues/70-focused-display.md) | Resolved | None |
| [Share Live Activity selection and lifecycle](../../.scratch/cascade-product/issues/71-shared-live-activity.md) | Resolved | None |
| [Keep the panels and arbitrate a single opening](../../.scratch/cascade-product/issues/72-persistent-display-panels.md) | Resolved | None |
| [Design the software Notch and the droplet Dynamic Island](../../.scratch/cascade-product/issues/73-software-notch-geometry.md) | Resolved | None |
| [Connect display preferences and auxiliary surfaces](../../.scratch/cascade-product/issues/74-display-settings.md) | Resolved | None |
| [Verify and deliver the multi-display notch](../../.scratch/cascade-product/issues/75-multi-display-verification.md) | Resolved | None |
| [Contracts and authorized boundary of the file shelf](../../.scratch/cascade-product/issues/76-file-workspace-contracts.md) | Resolved | None |
| [Qualify the native path of the files.workspace service](../../.scratch/cascade-product/issues/77-file-workspace-native-path.md) | Blocked | [Probe an external SwiftUI UI inside the notch](../../.scratch/cascade-product/issues/19-extension-host-probe.md); [Define a safe proof of managed process exit](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) |
| [Persist file shelf entries and receipts](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md) | Resolved | None |
| [Acquire and deliver files with per-item native drag](../../.scratch/cascade-product/issues/79-file-workspace-native-drag.md) | Blocked | [Qualify the native path of the files.workspace service](../../.scratch/cascade-product/issues/77-file-workspace-native-path.md); [Persist file shelf entries and receipts](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md) |
| [Add the shared component and the animated shelf list](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md) | Resolved | None |
| [Prepare verified FFmpeg and ffprobe in the bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md) | Resolved | None |
| [Run file conversions in recoverable jobs](../../.scratch/cascade-product/issues/82-file-workspace-conversion-jobs.md) | Blocked | [Qualify the native path of the files.workspace service](../../.scratch/cascade-product/issues/77-file-workspace-native-path.md); [Persist file shelf entries and receipts](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md); [Prepare verified FFmpeg and ffprobe in the bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md); [Prepare conversion formats and progress](../../.scratch/cascade-product/issues/86-file-workspace-conversion-planning.md) |
| [Route the shelf as a contextual page and notch heartbeat](../../.scratch/cascade-product/issues/83-file-workspace-routing.md) | Blocked | [Acquire and deliver files with per-item native drag](../../.scratch/cascade-product/issues/79-file-workspace-native-drag.md); [Add the shared component and the animated shelf list](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md) |
| [Compose the shelf provider and the conversion commands](../../.scratch/cascade-product/issues/84-file-workspace-provider-composition.md) | Blocked | [Qualify the native path of the files.workspace service](../../.scratch/cascade-product/issues/77-file-workspace-native-path.md); [Add the shared component and the animated shelf list](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md); [Run file conversions in recoverable jobs](../../.scratch/cascade-product/issues/82-file-workspace-conversion-jobs.md); [Route the shelf as a contextual page and notch heartbeat](../../.scratch/cascade-product/issues/83-file-workspace-routing.md) |
| [Verify and deliver the integrated file shelf](../../.scratch/cascade-product/issues/85-file-workspace-integration.md) | Blocked | [Persist file shelf entries and receipts](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md); [Acquire and deliver files with per-item native drag](../../.scratch/cascade-product/issues/79-file-workspace-native-drag.md); [Add the shared component and the animated shelf list](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md); [Prepare verified FFmpeg and ffprobe in the bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md); [Run file conversions in recoverable jobs](../../.scratch/cascade-product/issues/82-file-workspace-conversion-jobs.md); [Route the shelf as a contextual page and notch heartbeat](../../.scratch/cascade-product/issues/83-file-workspace-routing.md); [Compose the shelf provider and the conversion commands](../../.scratch/cascade-product/issues/84-file-workspace-provider-composition.md) |
| [Prepare conversion formats and progress](../../.scratch/cascade-product/issues/86-file-workspace-conversion-planning.md) | Resolved | [Contracts and authorized boundary of the file shelf](../../.scratch/cascade-product/issues/76-file-workspace-contracts.md); [Prepare verified FFmpeg and ffprobe in the bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md) |
| [Prepare the local host and the verified shelf copies](../../.scratch/cascade-product/issues/87-file-shelf-local-host.md) | Resolved | [Persist file shelf entries and receipts](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md) |
| [Route the local shelf and recognize the incoming drag](../../.scratch/cascade-product/issues/88-file-shelf-local-routing.md) | Resolved | [Add the shared component and the animated shelf list](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md); [Prepare the local host and the verified shelf copies](../../.scratch/cascade-product/issues/87-file-shelf-local-host.md) |
| [Compose the local page and the per-item outgoing drag](../../.scratch/cascade-product/issues/89-file-shelf-local-composition.md) | Resolved | [Prepare the local host and the verified shelf copies](../../.scratch/cascade-product/issues/87-file-shelf-local-host.md); [Route the local shelf and recognize the incoming drag](../../.scratch/cascade-product/issues/88-file-shelf-local-routing.md) |
| [Verify and deliver the first local file shelf](../../.scratch/cascade-product/issues/90-file-shelf-local-delivery.md) | Blocked | [Compose the local page and the per-item outgoing drag](../../.scratch/cascade-product/issues/89-file-shelf-local-composition.md); [Fix file acquisition in the shelf's native drag](../../.scratch/cascade-product/issues/91-file-shelf-native-drop-regression.md); [Make the shelf the main page and simplify its cards](../../.scratch/cascade-product/issues/92-file-shelf-primary-and-clear.md) |
| [Fix file acquisition in the shelf's native drag](../../.scratch/cascade-product/issues/91-file-shelf-native-drop-regression.md) | Available | [Route the local shelf and recognize the incoming drag](../../.scratch/cascade-product/issues/88-file-shelf-local-routing.md); [Compose the local page and the per-item outgoing drag](../../.scratch/cascade-product/issues/89-file-shelf-local-composition.md) |
| [Make the shelf the main page and simplify its cards](../../.scratch/cascade-product/issues/92-file-shelf-primary-and-clear.md) | Available | [Compose the local page and the per-item outgoing drag](../../.scratch/cascade-product/issues/89-file-shelf-local-composition.md) |

## Link to the addon work

The [completion plan](../superpowers/plans/2026-09-10-addon-runtime-completion.md) keeps deliveries, evidence and execution tasks. The latest [SDK/runtime asset verification](../superpowers/verification/2026-09-18-addon-asset-message-integration.md) records 883 tests / 83 suites, independent review PASS, signed build and verified updated relaunch; it does not qualify the OS transport, the launcher or real external addons.

[Choose the image transfer between addon and host](../../.scratch/cascade-product/issues/21-asset-transfer.md) is resolved by the user's answer. [Connect asset messages to the runtime and the SDK client](../../.scratch/cascade-product/issues/23-asset-message-integration.md) is now also complete within its internal scope. The other global tickets keep their own remaining questions open.

Previous delivery: [complete client, subscriptions and protected build](../superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md), 1084 tests/96 suites PASS, review, signed build and verified relaunch. [Mandatory SDK check](../superpowers/verification/2026-09-18-addon-required-sdk-build-check.md) and [manifest source matrix](../superpowers/verification/2026-09-18-service-consumer-manifest-resolution.md) have separate evidence.

Still remaining: launcher and authenticated transport, safe proof of process exit, connection to the app, migrations, remote UI, catalog/installation and native qualification. The C bootstrap candidate is compiled and verified locally; the available questions above represent the current frontier.

[Offline bootstrap model](../../.scratch/cascade-product/issues/39-bootstrap-abort-offline.md): completed with 31 tests and review PASS, without native execution or opening of the gate.

[Remote scene counter](../../.scratch/cascade-product/issues/41-remote-scene-counter.md): local check, Release build and signatures PASS after root review; no native activation performed. The policy for new integrations is now resolved: public by default, every new private exception decided individually.
