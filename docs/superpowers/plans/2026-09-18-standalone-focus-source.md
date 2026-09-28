# StandaloneFocus public source example

Approved C7/C12 request and sustained Codex-only continuation authorize this source-library increment. [Design investigation](../../../.scratch/codex-addon/20260918-continuation/focus-example-design.md). No verified builtin Focus was found; this is an independent example, not a migration/parity claim. No C0d or OS launcher changes.

## Behavior and boundaries

Build a standalone SwiftPM library in Examples/StandaloneFocus with direct dependencies only public CascadeAddonSDK/CascadeContracts. Explicit CASCADE_SDK_PATH manifest configuration, no hidden local fallback or remote URL. README shows configuring/copying the SDK and building outside checkout. Manifest source-only, honest implemented permissions/features; no service advertisement, executable, signing credentials or install claim.

Actor provider uses exact host-supplied PublicationID, expected owner, injected Date clock and bounded configurable timer duration (example default25minutes; not product policy). Approved actions are start/pause/resume/end; no reset/breaks/history/notification/source-app/service extras. Countdown is declarative host content with finite expiry; no tick task. Reconcile overdue state onrefresh/action/scheduledtoken. At most one schedule operation per relevant transition; obsolete tokens ignored, no physical queue cancellation claim. State-only completion, no external effect or work-while-host-closed claim.

Persist one schema-versioned <=16KiB record with exact assignment, phase, remaining/deadline, revision high-water, active token and <=16 correlated action receipts. Validate values/corruption/futureversion; don't overwrite malformed state. Explicit initializer mode distinguishes caller-declared new host assignment from resume-existing: missing persisted state in resume mode fails closed; never infer freshhost revisionhistory merely from missing storage. New assignment must not silently adopt previous session; preserve priorbytesonmismatch. Require host single writer, noCAS/atomic output+storage guarantees invented.

Busy flag acrossawaits rejects reentrancy. Build/validate candidate output before storage handoff, commit state+revision+receipt before return. Crash gaps allowed, reuse forbidden. Action fingerprint duplicates precede stale-revision refusal, sameIDdifferentrequest rejected; output completion correlated. No replay of old publicationrevision. Current snapshot onduplicate onlyafternewrevisionreservation. Evictedreceipt staleobservedrevision rejected. Validate exact publication,deadline,input,action andobservedrevision before mutation.

Before-write cancellation has no effect. Ambiguous write failure requires reread before mutation and outcomeUnknown when reply can be correlated; successfulwrite isn't retroactively uncommitted by cancellation. Stopemptyoutput, nofinalflushneeded. Separate authoritative storage from ProviderOutput.checkpoint; no duplicate authority. State ahead of refused/missing output is repaired onrefresh, not claimed rolledback. Civil-clock rollback behavior explicitlybounded/documented.

## Work and evidence

- Capture absent Examples/StandaloneFocus beforefirstedit. New files only there plus scratchreports; no existingSDK/Runtime/app changes, no Git operations.
- Pure reducer and provider tests using publicSDK, fakeboundedstorage andclock: lifecycle acrossrecreation/generation, revisionreservation, validwireoutput, actioncompletion/dedupe, stale/malformedinputs, cancellation/ambiguouscommit/busy, corrupt/future/oversizeddata, overflow, obsoleteexpiry andoverdue reconciliation. Meaningful compilingRED before implementation; retain failures.
- Independent copy outsidecheckout with explicit public SDKcopy, build/test/manifestvalidation and dependency/import audit. No private @testable SDKimports/Runtime/hostsource dependencies, no executable/OSprocessfixtures. Dedicated caches isolated from ongoingmetricsworker; monitordisk.
- Independentreview, scopedfixes, rootverification andtrackerupdate. NativeC7/C12 qualification (signedstandalone,sourceappabsent,realadmission/grants/revocation,hostexitcleanup) stayspending.

## Source increment verified

Independent source build/tests and review PASS. [Evidence and remaining native gaps](../verification/2026-09-18-standalone-focus-source.md). Updated-SDK integration and final app delivery belong to the ongoing storage-client increment.
