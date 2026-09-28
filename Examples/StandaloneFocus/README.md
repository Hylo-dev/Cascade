# StandaloneFocus public source example

A bounded SwiftPM **library** implementing `AddonProvider` with public
`CascadeAddonSDK` and `CascadeContracts` APIs. The example duration is configurable
from 1 to 86,400 seconds; its default is 25 minutes, an example choice rather than
product policy. Commands are **start, pause, resume, end**. Start while running or
paused is a no-op; start after completion/end begins a new timer. Pause/resume in
an unavailable phase is rejected. End is terminal, retains revision history, and
can be followed by an explicit start. There is no reset command.

This is an independent example. No builtin Focus migration or visual/input parity
is claimed. There is no executable, host registration, transport bootstrap,
native launcher, process control, signing, service, source application,
notification, history, or work while Cascade is closed. C0d and native qualification
remain unchanged; this library is not signed/installable addon evidence.

## Explicit local SDK configuration and independent build

`Package.swift` reads `CASCADE_SDK_PATH` using Foundation. It must be an absolute
path to a public SDK SwiftPM package exporting `CascadeAddonSDK` and
`CascadeContracts`; missing configuration fails the manifest. There is no relative
fallback or remote SDK release claim. The current development reference is the
local public source package, not a published SDK version. The SDK may also declare
unbuilt targets; warnings about their missing sources are acceptable when using a
public-only copy. Do not copy private Runtime/host sources to resolve those warnings.

Use a compatible Swift 6.2 or newer toolchain and copy only this example outside
the checkout. Choose your own absolute development-copy and build-scratch paths:

```sh
export CASCADE_SDK_PATH='/absolute/path/to/public-sdk-package'
cp -R /absolute/path/to/Cascade/Examples/StandaloneFocus /absolute/path/to/focus-dev-copy
swift test \
  --package-path /absolute/path/to/focus-dev-copy \
  --scratch-path /absolute/path/to/focus-build-scratch \
  --no-parallel
```

The same external paths support `swift build`. Inspect the manifest with
`swift package --package-path /absolute/path/to/focus-dev-copy dump-package`.
Keep development copies and build artifacts outside the source checkout. The
explicit SDK path must contain the public SDK package you have prepared; the
example does not fetch or infer one. Tests import only public modules and the
example's public API, without `@testable`. They use an in-memory bounded storage
adapter and injected civil clock, not real host admission or a process fixture.

## Host integration contract

The authenticated host supplies the **entire** `PublicationID` and expected addon
owner. The provider does not generate host instance/session IDs. A minimal caller
constructs the library with that assignment and forwards public events/context:

```swift
import Foundation
import CascadeAddonSDK
import CascadeContracts
import StandaloneFocusProvider

// assignedPublication and authenticatedOwner come from the host, not this example.
let provider = try StandaloneFocusProvider(
    expectedOwner: authenticatedOwner,
    publicationID: assignedPublication,
    mode: .resumeExisting,
    duration: 25 * 60,
    clock: { Date() }
)
let output = try await provider.handle(event, context: context)
```

`freshAssignment` is an explicit caller declaration that the host has **no prior
publication revision history** for this assignment and the storage record is
absent. It refuses even an existing matching record on first use. Use
`resumeExisting` for recreation, including a new connection generation; missing
storage fails closed. An assignment or duration mismatch preserves prior bytes.
There is no automatic adoption, deletion, migration, or repair of missing history.
The lifecycle owner must provision a safe empty store for a genuinely fresh
assignment, or resume the existing assignment with its original configuration.
A first refresh commits the idle snapshot at revision 1; fresh actions need that
observed snapshot. Once any write has been handed off, missing state also fails closed in the same
provider. A throwing first write with an authoritative absent reread therefore
requires lifecycle-owner recovery; the example cannot prove host history absent.

The host must serialize **one writer** for the assigned record across provider
instances/processes, supply authoritative consistent reads and known successful
write semantics, and enforce permissions, quotas, revocation and event authority
in its broker. `expectedOwner` is a validation input, not authentication. Public
storage has no CAS/transaction API; actor isolation and this example's busy flag
cannot enforce serialization across multiple providers. The busy flag covers all
awaits and throws `FocusError.busy` for concurrent invocations instead of queuing
unbounded work. Stop returns empty output without reading/writing or final flush
and terminates that actor's authority; recreation can resume committed state.
Unsupported service events throw and never invoke services.

## Durable state and action receipts

One fixed key, `standalone-focus.state.v1`, holds one schema-versioned JSON record
of at most **16 KiB**: exact assignment, timer identity, phase, configured duration,
remaining/deadline, revision high-water, active expiry token and the most recent
**16** action receipts. Corrupt, inconsistent, oversized and future-version data
is refused without overwriting it. The size check occurs **after** the client's
read has returned Data; it cannot prevent upstream allocation. The broker must
apply its own upstream bounds. `ProviderOutput.checkpoint` remains nil: keyed
storage is the sole authority and the public API offers no checkpoint restoration.

Every emitted snapshot reserves a revision above the durable high-water, including
refreshes and retained duplicate receipts. The provider builds and validates the
candidate output and record before storage handoff, then commits lifecycle state,
revision and receipt together before returning output. It does not claim atomic
storage+host-output admission. Crash or refused/missing output after commit may
leave durable state ahead of displayed content; gaps are permitted, reuse is not.
The next refresh repairs content with a higher revision. An action observing the
old snapshot is fenced until the host has a current snapshot. Successful storage
alone does not prove schedule admission or completion delivery.

Actions require the exact assignment, a supported action ID, **empty input**, a
finite future request deadline for a fresh command, and the current observed revision for a fresh
request. A retained request ID is matched against the whole public `ActionRequest`
(including identity, action, input, deadline and observed revision) before stale
revision refusal. A changed fingerprint is rejected. An exact retained duplicate
returns its original outcome with a newly reserved current snapshot, without
reapplying the command or replaying its publication revision. An identical retained receipt
returns its known original outcome even after the request deadline, without
reapplying the command. Its current snapshot still reserves a new revision and
reconciles overdue state. A changed fingerprint is rejected even after deadline. Whether the host forwards
or accepts a late retry remains its own admission policy. Evicted receipt retries with an old observed
revision are rejected; this is bounded deduplication, not unbounded exactly-once
history. Phase refusals after overdue reconciliation are durably receipted;
invalid identity/input/deadline/fence requests produce only correlated rejection.

Before-write cancellation has no effect. If a valid action's authoritative storage
read fails, the provider returns correlated `outcomeUnknown` with no publication,
operation, checkpoint or write: unavailable receipt history cannot prove that the
original command was rejected. This also applies after recreation, without any
in-memory uncertainty flag. Proven invalid input/identity is rejected before the
read. Successfully retrieving bytes does not establish trustworthy action history:
if decoding, schema/integrity, assignment, initialization-mode or configuration
validation fails, or required resume history is missing, a valid action likewise
returns only correlated `outcomeUnknown` without any write or candidate output.
Refresh still throws the specific diagnostic (`corruptState`, `missingState`,
`assignmentMismatch`, `invalidConfiguration`, etc.) and preserves the exact bytes.
Strict validation remains in force, including unknown fields inside a rejected
receipt's nested `reason` object (exact keys: `code`, `reason`). No invalid ledger
is partially trusted, repaired or treated as proof that a receipt was evicted.
With valid supported history, the existing bounded receipt policy still rejects
an evicted retry's stale observed revision; this does not promise unbounded
historical exactly-once results. Restoring usable history can recover an original
retained outcome without reapplying the command; the provider performs no
automatic restoration.

A fresh command's throwing first state/receipt write is ambiguous, so its reply is
correlated `outcomeUnknown` with no candidate publication/operation/checkpoint.
For an exact duplicate whose original completed **or rejected** receipt was
successfully recovered, a later throwing snapshot write does not erase that known
outcome. The reply contains **only the original correlated action completion**,
with no publication, operation or checkpoint. This remains true after deadline,
after overdue reconciliation, and during cancellation of the snapshot write.
The reply makes no assertion that the new snapshot revision or reconciliation
committed. For refresh/scheduled handling, a throwing write still throws an
`.outcomeUnknown` `AddonFailure`.

The provider never automatically retries an ambiguous write. Every next invocation
rereads authoritative storage before mutation; a failed reread blocks mutation
and leaves a valid action's result unknown until its receipt is recovered again.
A retry after a committed fresh write uses its durable receipt, while a confirmed
uncommitted write against an existing record can be retried from that record.
Known successful writes are not retroactively undone by cancellation; their
completed output is retained. Fresh-command deadlines are checked after the
authoritative receipt lookup and again before write handoff but cannot be
atomically coupled to storage commit or output admission. The write adapter and
host still decide whether a reply is deliverable.

## Countdown, scheduling and clock limitations

Running widget content is a public declarative `ContentNode.countdown`. Paused
content is static remaining time rounded up for display. The provider has no tick
task. Content has finite remove-on-expiry lifetime: deadline + one hour while
running, one hour from snapshot time otherwise. These are example retention
choices. Content expiry is not timer completion, and the displayed countdown may
reach zero before durable state reconciles.

Start/resume changing a running deadline emits at most one schedule operation.
The active token is stored in the same commit. Refreshes, duplicate commands and
receipt retries do not enqueue another token. Pause/end/completion invalidate the
logical token; obsolete or early scheduled tokens return empty output. Public
operations have no schedule cancellation, so old queue entries remain subject to
host admission limits. Lost/refused schedule output is not automatically
rescheduled; later refresh/action reconciles overdue state. No physical single
queued deadline is promised. Completion is a durable phase change with no external
side effect and no claim of work performed while the host was absent.

Reconciliation uses the injected civil `Date` clock on refresh/action/current
expiry delivery. A forward jump completes an overdue timer. A backward jump can
extend wall-clock waiting; pausing clamps `deadline - now` to `0...duration` to
prevent remaining time exceeding the configured bound. This is not monotonic
elapsed-time accounting across clock changes or a policy for the host.

`Manifest.json` is a **source manifest**: the named entry point is this library
actor, not an installed executable. It declares the implemented timer actions,
`storage.own`, event-driven single-work profile and scheduled-deadline background
request only. No services, optional source-app opening, signing identity or bundled
SDK version are advertised. The copied test fixture is kept identical to it.
Real signed standalone execution, source-app absence, admission/grants/revocation,
resource limits and host-exit cleanup remain native qualification work for the host.
