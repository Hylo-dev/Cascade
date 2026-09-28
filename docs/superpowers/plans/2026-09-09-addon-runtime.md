# Cascade Addon Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent-driven execution is optional only when separately selected; planning this work does not dispatch agents.

**Goal:** Build a native platform of addons autonomous from the source app, with content retained by the host and a single SDK that Cascade's widgets are also required to use.

**Architecture:** Cascade retains and draws ordinary content with SwiftUI; providers run code in separate processes on demand. REQUIRES, shared services, actions, timelines, leases and budgets go through a common runtime. Remote SwiftUI scenes offer advanced UI only when requested and visible.

**Tech Stack:** Swift tools 6.2, macOS 14, SwiftUI/AppKit, Foundation, Swift Concurrency/Dispatch, XPC, ExtensionFoundation/ExtensionKit through verified compatible APIs; Swift Testing, XCTest and Apple profiling tools.

**Spec:** [approved architecture](../specs/2026-09-09-addon-runtime-design.md), to be read together with this plan.

## Global Constraints

- macOS 14 as the app's minimum. The deployment target is not raised implicitly.
- Fully native system: no WebAssembly, JavaScriptCore, general-purpose interpreter or third-party dependency without a new justification.
- Cascade must be open. The source app may be closed or absent if the addon's functions are self-sufficient.
- All future widgets, notices and activities developed by the team use the same SDK, manifest, REQUIRES, content/action model, catalog, lifecycle and resource control as external addons.
- Custom addon code is not loaded into the host's graphics process, the team's addons included. In-process substitutes allowed only in tests.
- Renderers and system adapters are shared infrastructure. No quota exemption or direct engine access based on the widget's producer.
- Visible content does not require a resident provider. The provider's expected exit does not end the publication.
- SDK SwiftUI means components with a serializable description; not arbitrary serialization of AnyView. The remote scene has a distinct lifecycle.
- No per-addon polling, synchronous IPC wait on the MainActor or provider call in the display link. Queues and collections have limits.
- Numeric budgets in the specification: initial values to be measured, not performance already achieved. Application quotas and monitored CPU/RAM thresholds remain distinct.
- Process freezing excluded from ordinary v1 behavior; a possible separate experiment after measurements of IPC wait/restart.
- Preserve signing/TCC identity and existing visual/input behaviors during the migration; no automatic granting of macOS permissions.
- After app code changes: successful build, update of /Applications/Cascade.app through the project script, relaunch and verification of the new process. If blocked, state the impediment.

## Status and scope

**Remaining execution from 10 September:** follow the [completion plan](2026-09-10-addon-runtime-completion.md), which reuses P1, corrects the proposed signatures against the code present and organizes the work into five verifiable deliveries. The later [approved decision on delegated work](../specs/2026-09-10-addon-control-policy.md) settles the product question: stop and identity of the managed processes remain to be qualified.

Implementation began on 9 September 2026. **P0 did not pass the launcher gate**: the ExtensionKit path authenticates the processes but does not stop the blocked worker while the host stays open. The later prototype with a direct child solves stop and metrics, but allows launches delegated to Launch Services outside the supervisor. Both remain experimental. Results and commands are in the [P0 report](../verification/2026-09-09-addon-runtime-P0.md).

P1 introduces contracts, SwiftUI builder/renderer, provider SDK, REQUIRES and host-owned publications. The automated verifications and the reviews are recorded in the [P1 report](../verification/2026-09-09-addon-runtime-P1.md). P2/P3/P4 remain open: no unverified launcher has been incorporated and no widget has been migrated through a private exemption. The checkboxes below mark completion of the whole phase, including the desktop proofs still missing.

The plan is divided into **5 phases, 19 tasks**, each with files, interfaces, verification cases and expected result. P0 first resolves the platform unknowns; the details of the macOS adapter are fixed from its evidence, without inventing APIs or launch guarantees today. For the platform-independent contracts, P1/P2 already define the values and signatures to share.

The working tree contains earlier uncommitted work. At the start of each phase read git status, preserve those changes, isolate the work if necessary and do not use global restore commands. The paths below are relative to the repository root. No proposed file is declared as already existing.

The product map remains [here](../../../.scratch/cascade-product/map.md). This plan makes the addon subsystem executable; it does not declare closed the tickets on audio routing, the file shelf or all the app's future functions.

## Execution order

| Phase | Operational plan | Verifiable output |
| --- | --- | --- |
| P0 | [Process and scene feasibility](2026-09-09-addon-runtime-00-platform.md) | Native standalone addon, authenticated connection, exit after host death and remote scene proven on the available combinations |
| P1 | [Contracts, SDK and content](2026-09-09-addon-runtime-01-contracts.md) | Bounded manifest and content, Swift builder, resolver, renderer and snapshots independent of the connection |
| P2 | [Runtime, services and resources](2026-09-09-addon-runtime-02-execution.md) | On-demand processes, reliable actions, leases, shared services, storage and supervision |
| P3 | [Integration and team widgets](2026-09-09-addon-runtime-03-adoption.md) | Clock, timer, notices and media through the common SDK; remote UI managed by the same runtime |
| P4 | [Distribution and qualification](2026-09-09-addon-runtime-04-release.md) | Installation/update, external example, SDK tools and performance/fault proofs |

- [ ] P0 completed with matrix and launcher choice documented.
- [ ] P1 completed with pure tests, previews and a first proof of retained content.
- [ ] P2 completed with real process failures and no process after host exit.
- [ ] P3 completed with the team's widgets on the public path and old bypasses removed.
- [ ] P4 completed with an addon built in an independent project and reproducible measurements.

P1 can advance on the pure models while P0 verifies the platform, but P2 does not incorporate an unverified launcher. P3 does not use in-process shortcuts to get around P2. The remote scene is part of the goal: it can be integrated after the ordinary path, but not omitted in order to declare the whole plan finished.

## File structure and responsibilities

The existing Swift package is extended at first, without opening additional repositories.

| Path | Responsibility |
| --- | --- |
| CascadeKit/Package.swift | Public SDK products and internal targets; verifiable dependencies |
| CascadeKit/Sources/CascadeContracts/ | Wire values, manifest, identity, errors, content, versions and requested resources |
| CascadeKit/Sources/CascadePresentation/ | Component-based Swift builder and SwiftUI renderer shared with the previews |
| CascadeKit/Sources/CascadeAddonSDK/ | Developer API for handlers, actions, publications, storage and services |
| CascadeKit/Sources/CascadeTransport/ | Native codecs/connections, peer verification and platform adapters |
| CascadeKit/Sources/CascadeRuntime/ | Catalog, resolution, processes, publications, scheduler, broker and supervision |
| CascadeKit/Sources/CascadeKit/Core/AddonPresentation/ | Single adaptation from runtime content to the notch engine |
| Cascade/Addons/ | Catalog of the addons distributed with Cascade, without private widget implementations |
| Addons/Clock/, Addons/FocusTimer/, Addons/SystemNotices/, Addons/Media/ | Manifests, providers, any scenes and resources of the team's widgets |
| Cascade/Integrations/ | Existing system adapters, exposed to the broker as shared services |
| Examples/StandaloneFocus/ | Project that depends only on the public SDK products |
| Prototypes/AddonPlatform/ | Isolated proof of packaging, launch, signatures and scenes; not a production dependency |
| scripts/test-addon-*.sh | Reproducible verifications introduced in the respective tasks |

The Runtime and Transport modules import neither CascadeKit nor the names of concrete widgets. CascadeKit can consume Contracts and Presentation. The SDK product does not export the engine, windows, hardware monitors or the internal catalog. The SDK's Transport dependency exposes only the client channel, without privileged host APIs.

## Common interface vocabulary

The signatures in the sub-plans are proposed implementation contracts, not APIs that already exist. The value types must be defined in P1 before they are used in production:

| Type | Fields / meaning |
| --- | --- |
| AddonID | Validated reverse-DNS string |
| PublicationID | Authenticated AddonID, instanceID and sessionID; does not coincide with the PID |
| ConnectionGeneration | New UUID at every launch/handshake |
| AddonManifest | Identity, version, compatibility, execution, sourceApp, bundledLibraries, REQUIRES, PROVIDES, features, permissions, resources from the specification |
| ContentDocument | schemaVersion, root node, accessibilityLabel, privacy, referenced assets |
| ContentNode | Text, symbol, image, row, column, progress, countdown, clock, action; bounded children and strings |
| PresentationSet | Bounded map of the widget, compactLeading, compactTrailing, minimal, expanded representations to ContentDocument; under the same identity/revision |
| Publication | ID, revision, widget/activity/notice type, PresentationSet or timeline, expiry and staleness policy |
| ScheduledEntry | Date, PresentationSet; at most 32 entries / 256 KiB per instance |
| ActionRequest | Request UUID, PublicationID, actionID, bounded input, deadline and observed revision; the generation is added by the host on send, after any launch |
| ActionOutcome | completed(payload), rejected(reason), outcomeUnknown; accepted is a separate ack |
| Grant / Lease | Owner, service, scope, expiry, generation, granted cost; data assigned by the host. Connection tokens are distinct from the host-owned interest subscriptions |
| ServiceInvocation / ServiceResponse | Request ID, contract/operation and bounded payload; the broker authenticates and routes calls/responses without passing the caller's privileges to the provider |
| InvocationCompletion | Correlated result action(requestID, outcome) or service(requestID, response), distinct from state updates |
| ProviderOutput | Publications, operation/lease requests, optional InvocationCompletion and bounded checkpoints; no closures in the payload |
| StopReason | idle, disabled, permissionRevoked, resourceExceeded, hostStopping, updated |

Connection state, work state and publication state are distinct. A valid publication survives the provider's expected exit; old handles and results do not. A crash can make the content stale, while a disable also removes future entries and actions.

## Verification and recording of the outcome

Each task: add the indicated behavioral proof, observe its relevant failure, implement, run the named verifications and review the diff. A nonexistent test file or a configuration error is not a valid behavioral failure. Commit limited to the task's files when the state of the checkout allows it; do not include pre-existing changes.

Base command for the package tests, with writable caches even in the restricted environment:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-addon-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-addon-swift-cache \
xcrun swift test --disable-sandbox --package-path CascadeKit \
  --scratch-path /private/tmp/cascade-addon-tests --filter SUITE_NAME
```

SUITE_NAME is the operational argument to replace with the suite named in the task; do not switch all targets to Swift 6 in one go. Prefer complete concurrency checks in the new targets, keeping the behavior of the existing targets until their migration.

For a phase that modifies the app:

```sh
/bin/zsh scripts/build-development.sh
/usr/bin/codesign --verify --deep --strict /Applications/Cascade.app
```

The script updates the managed link in /Applications. Only after success quit Cascade, verify that it has exited, relaunch that path and verify the new PID/path. Save outcome, reviews, commands, OS and cases not run in docs/superpowers/verification/2026-09-09-addon-runtime-PN.md, where PN is the phase. Do not declare support on the basis of mocks alone or of APIs present in the SDK.

## Specification coverage

| Requirement | Task |
| --- | --- |
| Source app absent, Cascade required | 00.1–00.2, 02.1, 03.2, 04.1 |
| REQUIRES, versions, cycles, features and bindings | 01.1, 01.3, 02.3, 04.1 |
| SwiftUI components and persistent content without a provider | 01.2, 01.4, 02.2, 03.1–03.2 |
| Remote SwiftUI scenes | 00.3, 03.4 |
| Actions, revisions, reconnections and uncertain results | 01.1, 02.1–02.2 |
| Scheduler, shared services, privacy and permissions | 02.2–02.3, 03.3–03.4 |
| Quotas, CPU/RAM, flooding, crashes and quarantine | 00.2, 02.4, 04.3 |
| Assets, storage, migrations and rollback | 01.4, 02.5, 04.1 |
| Same system for our widgets | 01.2, 03.1–03.4, 04.2 |
| Compatibility, independent package, guides and tools | 00.1–00.3, 04.1–04.3 |

## Definition of done

The platform is complete when an external addon and the team's addons use the same contracts and controls, ordinary content survives the providers' exit, remote scenes follow visibility, dependencies resolve without hidden effects and failures/resource pressure do not require relaunching Cascade. Real-process evidence and measurements are required; documents, declared protocols or examples run inside the host are not enough.
