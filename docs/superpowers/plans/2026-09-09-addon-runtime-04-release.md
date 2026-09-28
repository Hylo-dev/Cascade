# P4: Distribution, SDK and qualification

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the system usable by an independent project and demonstrate its control, efficiency and parity with the Cascade widgets.

**Architecture:** A single catalog verifies packages, identities and compatibility. Installation and update re-evaluate dependencies and grants; qualification crosses the whole public path with real processes.

**Tech Stack:** SDK/runtime from P1–P3, signing and packaging from P0, Swift Testing/XCTest, Apple measurement tools and repository scripts.

**Spec:** [architecture](../specs/2026-09-09-addon-runtime-design.md); [main plan](2026-09-09-addon-runtime.md).

## Global Constraints

All the constraints of the main plan apply. P4 requires P0–P3 for the final qualification; documentation and examples can be prepared earlier. The format selected in P0 is the only initial production format. No download, app launch, irreversible migration or new permission is authorized by REQUIRES alone. Missing proofs stay explicit.

## Task 04.1: Catalog, installation, update and recovery

**Files:** create CascadeKit/Sources/CascadeRuntime/Catalog/AddonCatalog.swift, PackageVerifier.swift, AddonUpdateCoordinator.swift, CatalogReconciler.swift; Tests/CascadeRuntimeTests/AddonCatalogTests.swift, AddonUpdateTests.swift, CatalogReconciliationTests.swift under CascadeKit; Cascade/Features/Settings/AddonsSettingsView.swift; scripts/test-addon-installation.sh; docs/addons/distribution.md. Change the app composition, the settings navigation and the build target according to the structure that exists at the time of the task.

**Interfaces:** `AddonCatalog.inspect(_ location: URL) async throws -> VerifiedPackage`; `enable(_ id: AddonID) async throws`; `disable(_ id: AddonID) async`; `AddonUpdateCoordinator.prepare(_ package: VerifiedPackage) async throws -> UpdatePlan`; `apply(_ plan: UpdatePlan) async throws`. VerifiedPackage has a verified identity, manifest, digest, origin and authorized path; UpdatePlan lists dependents, new permissions, state to migrate and rollback possibility.

- [ ] Write AddonCatalogTests with a valid identity, altered signature, bundle replaced after inspect, incompatible version/schema, same ID with a different publisher, disabled addon and duplication between full app and standalone container. Revalidate at launch: the path alone does not authorize the executable.
- [ ] Implement discovery through the mechanism verified in P0, event-driven reconciliation and a bounded initial check. A hundred installed addons must not mean a hundred launches or a scan timer per package. Catalog metadata/caches are bounded too; declare the supported maximum and the behavior when it is exceeded.
- [ ] Apply installation, enabling, disabling and removal as atomic transitions. For packages managed by macOS use their lifecycle, without moving registered bundles by hand or writing inside signed apps. Removing a source app removes the functions that require it; an installed standalone copy stays independent.
- [ ] Avoid a silent choice between two copies of the same ID: preserve the authorized selection and show the conflict when identities/services differ. Installation does not mean granting all permissions; the settings show producer, origin, requests, blocked features and the reason, observed consumption and quarantine in understandable language.
- [ ] Write AddonUpdateTests with a signature change, new permissions, a dependency that has become incompatible, a failed migration, a crash before/after replacement and publication of the previous version. Quiescence, staging, verification, checkpoint, new handshake and commit; old actions/generations are not blindly transferred to the new version.
- [ ] Keep a copy of the state and of the previous version only when the format/distributor allows rollback. After an error restore the compatible state atomically; if the system does not allow restoring the binary, disable the version and show the available recovery. No universal promise of downgrade.
- [ ] Re-evaluate the dependency closure on update/removal/revocation. An independent feature continues; the consumers lose the handles of the removed provider and receive a stable reason. Do not automatically start another service that requires different grants.
- [ ] Run AddonCatalogTests, AddonUpdateTests, CatalogReconciliationTests and `/bin/zsh scripts/test-addon-installation.sh`; prove the real standalone/bundled paths, record the distribution limits and build/relaunch; commit.

## Task 04.2: Public tools and mandatory parity for our widgets

**Files:** create CascadeKit/Sources/CascadeAddonTool/main.swift, ManifestValidationCommand.swift, ScaffoldCommand.swift and the related executable product in Package.swift; Tests/CascadeAddonToolTests/AddonToolTests.swift and Tests/CascadeRuntimeIntegrationTests/SDKParityTests.swift under CascadeKit; Examples/ServiceConsumer/ with manifest/provider/container; docs/addons/README.md, quickstart.md, compatibility.md, performance.md, testing.md. Complete docs/addons/manifest.schema.json, protocol.md, services.md, lifecycle.md and distribution.md from the previous tasks; consolidate scripts/check-addon-boundaries.sh.

**Interfaces:** proposed commands `cascade-addon validate <package-path>` and `cascade-addon init --name <name> --destination <path>`. The arguments in angle brackets are CLI inputs, not text to insert into the generated files. Validation reuses the P1 decoders/validators; the scaffold generates a complete, compilable provider and manifest, with an identity to be assigned explicitly before signing.

- [ ] Write AddonToolTests: valid package, schema error with a readable position, non-empty destination refused and compilable scaffold. No shell contained in the manifest is executed; do not overwrite existing files or invent signing credentials.
- [ ] Document how to create a widget with Swift components, publish a timeline, receive actions, use storage/services, declare REQUIRES and add an advanced SwiftUI scene. Distinguish shared code included in the package from a service offered by another addon; explain the optional source app, grants and the verified minimum macOS.
- [ ] Build StandaloneFocus and ServiceConsumer in an independent project that depends only on the public SDK products. ServiceConsumer requires the timer's focus.sessions service: prove provider present, absent, disabled, incompatible version, cycle and revocation of the consent to the consumer.
- [ ] Write SDKParityTests using the same fixture provider first as bundled and then as external, with the same initial set of grants: the same decisions on quotas, revocations, service access, signatures, crashes, lifecycle and exit times. The only allowed difference is discovery/distribution and the UI that describes it.
- [ ] Make check-addon-boundaries.sh a mandatory check of the project verification: no private import in the addon targets, no direct registration of new widgets/activities, no factory or quota decided by the widget's name or by the publisher. The generic bridge stays the only user of the internal protocols for the migrated content. A text search alone does not replace the verification of the targets' dependencies.
- [ ] Update CODE_STYLE.md, PRODUCT.md and docs/architecture/live-activity-contracts.md to reflect the APIs actually implemented; remove the legacy examples after the migration. The documented path must be the one used in the source by Clock, SystemNotices and Media, with no second internal guide with shortcuts.
- [ ] Run AddonToolTests, SDKParityTests, the boundary check and the independent build of the examples. Review documentation and code together; publish only the combinations actually proven and do not declare a stable ABI across compiler versions without proof. Commit.

## Task 04.3: Measurements, real faults and first-release thresholds

**Files:** create scripts/benchmark-addon-runtime.sh, scripts/test-addon-e2e.sh; CascadeKit/Tests/CascadeRuntimeIntegrationTests/AddonEndToEndTests.swift; docs/superpowers/verification/2026-09-09-addon-runtime-P4.md and docs/addons/resource-profiles.md. Change ResourcePolicy and the manifest profiles only on the basis of the measurements collected.

**Interfaces:** benchmark-addon-runtime.sh produces samples with timestamp, scenario, OS/hardware/build, process identities, CPU, footprint, wakeups if observable and latencies. Report baseline, increment, peak, p50/p95/p99 and number of samples; an unavailable metric does not count as zero. All addon/scene/service processes and the work added to the host contribute to the total.

- [ ] Write AddonEndToEndTests and a matrix with: zero addons; a hundred installed but inactive; Clock/timer with providers already exited; twenty simultaneous requests beyond the process limit; visible/hidden scene; two consumers of the same service; update/removal; host closed and host killed; blocked or malicious addon; revocation and missing dependency. Count the real processes and subscriptions, not only the state of the mocks.
- [ ] Record a baseline of the app without active addons and comparable scenarios for at least 60 s after warm-up, repeated three times, both on power and on battery when available. Note other significant activity on the machine. Measure startup, warm/cold action and scene opening over at least 30 samples per scenario; do not infer a robust p99 from a few samples.
- [ ] Verify candidate limits: messages/s, bytes, number of instances/activities, queues, assets, disk, jobs, process admission and memory. For observed CPU/RAM measure overshoot and stop latency; do not equate them with a limit enforced instantly by the kernel. Include the cost of the supervisor and of the decoder.
- [ ] Run a hundred cycles of open/close and enable/disable. After the release window no leases, captures, processes or monotonic memory growth attributable to retained resources must remain. Legitimate caches must stay within quota; record the allocator noise separately.
- [ ] Define the continuous profile for advanced scenes and audio only after the measurements: maximum rate, CPU/time cost, footprint, buffers, concurrency and response to overshoot. Compare the same media player load before/after the migration. If the profile does not pass, reduce work/components or keep it publicly unavailable; no exception for our widgets.
- [ ] Choose and document the reuse window by comparing immediate closing, a short IPC wait and reopening. Any freezing is a separate and optional experiment, not a requirement to complete the plan: it does not enter the default without a measured advantage and verification of pending resources.
- [ ] Prove the required macOS versions and signatures from different publishers where available. The matrix distinguishes compilation, process actually launched, sandbox/permissions, scene, recovery and performance. An unavailable macOS or a missing second signature stay unverified cases, not green rows.
- [ ] Run all the suites introduced by P1–P4, the boundary check, test-addon-e2e.sh and the affected existing regressions. After a positive outcome: build with the official script, signature verification, the /Applications update performed by the script, quit/relaunch and verification of the new PID. Save logs, package versions and parameters to repeat the measurements.
- [ ] Update the specification and resource-profiles.md with the values actually qualified, the rationale and the residual limits. Close P4 only if the criteria of the main plan are covered; a platform impediment requires an explicit change of the requirement or stays open. Prepare a release candidate and local documentation; public distribution only in the related release assignment. Commit limited to the phase's files.
