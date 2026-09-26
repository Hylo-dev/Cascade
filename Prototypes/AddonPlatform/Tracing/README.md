# Development tracing and fixed-image exec characterization (C0b–C0u)

This isolated diagnostic measures public signing status around one `PT_TRACE_ME` request. It also characterizes one fixed signed Worker replacement under an owned kernel exec stop. It does not admit native launchers, execute addon payloads, prove managed death, or qualify macOS 14 / Developer ID distribution.

Run offline evidence tests with `python3 Prototypes/AddonPlatform/Tests/TracingEvidenceTests.py` and `python3 Prototypes/AddonPlatform/Tests/TracingExecEvidenceTests.py`. Run the signed fixture once with `zsh scripts/test-addon-tracing.sh` from an explicitly authorized desktop execution context. Do not interpret inherited Codex sandbox failures as production policy. Artifacts and unconditional failure reports are written under a fresh `/private/tmp/cascade-tracing-untraced-*` directory. Do not retry a deterministic rejection or weaken profiles.

The exact roles are hardened, unsandboxed `TraceSupervisor` with no entitlements; hardened `TraceStub` and `TraceWorker` each with exactly `com.apple.security.app-sandbox=true`. All have distinct embedded signed identifiers and the existing configured development signer. Build flags use Xcode-beta, warnings as errors and a macOS 14 deployment target. The same signed files serve baseline and trace invocations. The observer is the existing Python interpreter, outside the measured trace pair; its static signature is captured separately.

Root's finite-count ruling replaces the proposal's three executable baseline count: two independent baseline cases (`Supervisor → Stub`, `Supervisor → Worker`) create four baseline participants. A single conditional trace-only case (`Supervisor → Stub`) creates two additional participants. Independent supervisors avoid carrying state between role baselines. After accepted A/B controls, C creates one fresh Supervisor and Stub; that Stub execs the same-build Worker while retaining its PID. The original C progression has four cases/eight created processes. The conditional U contrast described below raises the absolute maximum to five cases/ten created processes, with no retries or death cases.

Each supervisor records its own S0, S1 before granting the child request, and S2 after the child response. Each child records S0, S1 after sandbox/resource controls, and S2 after the request or its baseline equivalent. Snapshots use public `SecCodeCopySelf`, expected-identifier/certificate `SecCodeCheckValidity`, and `SecCodeCopySigningInformation` with dynamic and signing information. The raw public status and documented Valid/Hard/Kill/Debugged/Platform bits are distinct from static signature flags. Missing/ill-typed public fields fail closed. `allVMProtectionsPreserved` always remains `unknown`.

The observer positively opens an existing foreign `.zshrc` without reading it and connects to/accepts its own loopback listener. Children must show permission denials on those same resources, hard NPROC=0, and a denied raise. These controls make no supervisor sandbox claim.

Every case has an external five-second deadline, a default three-second supervisor alarm and a two-second child alarm, with monotonic lower bounds recorded before arming. A/B child waits forward traced signal stops; unexpected C stops are terminated through the owned trace relationship; alarms/kill requests are never exit evidence. Observer registers the child NOTE_EXIT before the initial nonce token. Native wait records and the observer's owned direct-child wait/kqueue supply actual cleanup evidence. There is no arbitrary PID lookup, attach, detach, kill-by-name, or SIGSTOP parking. Records are at most 4 KiB per line, 96 records / 256 KiB per case; code uses fixed bounded buffers and no stress allocations. Public framework internal allocations are not a claim of measured total resident memory.

A detected protection regression is reported even if cleanup also fails; inspect the separate cleanup fields. Baseline/setup errors remain unknown rather than being relabeled ptrace rejection. Exact phase/nonces/sequences and same artifact hashes are required. All native admission fields are false, including when the narrow result is `basicCompatibilityObserved`.

The evidence reducer retains separate `refusals`, `regressions`, `unavailableEvidence` and raw `terminations` with phase/role/stage context. Summary precedence is observed regression, observed refusal, incomplete evidence, then complete compatibility. An unavailable query cannot erase another observation; missing or mistyped fields cannot establish a regression or positive result. In particular, booleans must be explicit and artifact fingerprints must be nonempty SHA-256 strings.

Progression uses the accumulated baseline cases, including cross-case Supervisor identity/status and artifact comparisons. Normal successful native completion is required in addition to observed cleanup. Wait-observed SIGALRM is explicitly a guard termination without any cross-clock inference. The observer allocates kqueue before creating a process and retains setup-failure cases. A failure after spawn retains the owned supervisor PID/wait; if the child identity was never received, descendant cleanup stays unknown.

## Fixed-image exec characterization (C0c)

The original C prefix runs A-Stub, A-Worker, B-Stub and C-Stub from one signed
build; C0u adds only the conditional contrast below. Each completed prefix must pass before the next case is created. C uses
only the generated Worker path, and passes the accepted same-build baseline
status, static flags, runtime, signature hash, team and exact entitlement profile
to the fixed native roles. Expected identifiers and the selected signer remain
compiled into the validity requirement. S0/S1/S2 must match before the nonce and
phase-bound exec grant can be consumed.

Stub records exec intent, closes its control descriptors, and execs Worker in
the same process. Supervisor requires an owned-child waitpid SIGTRAP stop; pipe
readiness is never exec evidence. While that exact child is stopped and unreaped,
it creates a fresh public SecCodeRef with SecCodeCopyGuestWithAttributes and the
owned PID, validates the expected Worker signer/identifier requirement, and
records dynamic public status plus same-build signature/profile comparisons.
Only accepted S3 permits one PT_CONTINUE. An explicit pre-call continueIntent,
the call's CLOCK_MONOTONIC request time and its actual result are separate: Worker may write S4 before the parent writes the return
record. No old Stub reference or child self-report substitutes for S3.

Worker emits a bounded main-entry diagnostic before its first S4 self-query.
After S4 it observes the inherited ITIMER_REAL timer,
SIGALRM disposition/mask and original native guard bound without rearming it.
Its NPROC check reads inherited hard/soft zero before testing a rejected raise;
it does not set the inherited limit again. The foreign-file and loopback tests
remain bounded denial controls. Every native phase/time comparison uses explicit
CLOCK_MONOTONIC; Python's observer deadline has an independent epoch and is never
subtracted from native timestamps. Phase operations reserve cleanup slack within
the unchanged two-second child, three-second Supervisor and five-second external
guards. Unexpected C stops are killed through the owned tracing relationship,
never continued into work for additional evidence.

`basicCompatibilityObserved` and `tracedExecCompatibilityObserved` are separate
booleans. The latter needs the complete C stop, external identity, successful
continue, S4, inherited controls, guard and actual successful exit record.
Refusal, regression and unavailable evidence remain independently retained.
`workerExecPerformed` requires fresh externally validated Worker identity;
intent alone is insufficient. `nativeLauncherAdmitted=false`, managed death is
unperformed, and `allVMProtectionsPreserved=unknown`. This fixed diagnostic does
not establish hostile replacement/setup-window race safety, production transport
authentication, all VM protection equivalence or macOS 14/distribution support.

## First Worker progress localization (C0c)

Phase-C and phase-U Worker startup and their first S4 self-query emit `workerProgress`.
`mainEntry/reached` is written immediately after the inherited guard and sequence
are parsed and validated, using the already validated phase/nonce and the original
PID. It precedes any CF/Security call. Fixed point names identify before/after
boundaries for CFStringCreateWithFormat, SecCodeCopySelf,
SecRequirementCreateWithString, SecCodeCheckValidity,
SecCodeCopySigningInformation and extraction of the returned signing fields.
Returned Security calls carry their actual `apiStatus`; skipped calls emit no
before/after pair or invented status. CF string return records report `created`;
field extraction reports `fieldsAvailable`. A returned call is not necessarily a
successful call: read its actual status separately from its last milestone.

Markers use the existing fixed atomic record buffers, nonce, inherited per-PID
sequence and CLOCK_MONOTONIC timestamp. The observer checks an explicit native
clock and finite positive numeric time for this new kind, as well as the existing
role/nonce/phase/sequence/owned-PID protocol. Markers remain ancillary and never
satisfy S4, signing/protection evidence, inherited controls or completion gates.
A malformed marker invalidates the record protocol. Missing main entry means
“not localized past startup”; a before marker without its after marker only
bounds the last observed section. Missing or partial records do not prove where
execution stopped or whether a call completed.

The successful child path emits 7 Stub records, 1 main-entry marker, 10 API
markers, 2 extraction markers and the original S4/inherited-guard/controls records:
23 total, within the unchanged 32-record per-process cap. The 96-record / 256-KiB
case caps and 4-KiB line cap are unchanged. There is one startup PT_CONTINUE only;
no marker requests another continue, timer, sleep or grant. The original inherited
2-second child, 3-second Supervisor and external 5-second deadlines remain intact.
`signalStop` now names its actual `ptraceOperation` (PT_KILL in C, PT_CONTINUE in
A/B) and `ptraceResult`; its legacy `continueResult` is retained only as an alias
of that syscall result. A PT_KILL cleanup record is never execution or exit proof.

Changed signed bytes require exactly one same-build A-Stub/A-Worker/B-Stub
progression, followed by at most one C case. Native evidence is retained under a
fresh diagnostic directory; no retry follows this result. C0u may add the one conditional matched control below.
The causal report distinguishes the earliest/last marker from the last observed
successful returned API. No marker changes native admission, managed-death or
all-VM-protection conclusions.

## Matched untraced replacement control (C0u)

The trusted observer may dispatch one U-Stub case only when the same-build C
prefix has accepted A/A/B controls, authenticated the owned Worker exec stop and
matching fresh S3, issued its sole successful continue, retained a valid protocol
and actual Supervisor/child exit observations, and emitted no Worker record or S4.
Normal C completion, any Worker progress, malformed records, failed startup gates
or unknown cleanup stop progression before U. This is a changed-build causal
control, not a repeat seeking successful tracing.

U uses exactly the same signed products, baselines, native nonce/sequence startup
checks, fixed Worker path, inherited environment/stdio and closed control
descriptors, sandbox-only child profiles, NPROC hard zero and two-second inherited
alarm. U omits PT_TRACE_ME, the exec-stop wait/S3 inspection and PT_CONTINUE.
Supervisor grants the fixed exec after its matching S2, then observes and reaps
its directly spawned child. A fatal untraced SIGTRAP is an observed signaled exit,
not a traced stop. An ordinary stopped U child is killed by its owning parent
without ptrace; the request remains separate from the actual wait record.

The same Worker main/S4 milestone, self-public-fields, inherited-guard and control
path runs in C and U without rearming the timer. U compatibility requires explicit
false guardrailUsed, complete valid same-build protocol, actual main and S4,
matching owned Worker self identity/public fields, inherited controls and normal
observed exits. It never substitutes self reports for C external authentication.
The top-level C result, basicCompatibilityObserved and workerExecPerformed remain
independent when U is appended; untracedControl retains its own actual terminations,
refusals, regressions and unavailable evidence. A new U success is neither C
compatibility nor native admission, death qualification or proof of sandbox before
arbitrary provider initializers. Missing U markers leave exec unconfirmed: an
execIntent record alone never proves replacement or a platform refusal.

All guards and record caps are unchanged. A successful U child emits six Stub
records (no ptrace record) plus sixteen Worker records: 22 versus C's 23, both
below32. U Supervisor emits seven records on the normal path, so a successful U
case totals29, below96; the same 4096-byte atomic line and256KiB total bounds apply.
Failure/cleanup paths remain bounded and cannot loop beyond the existing12-event
limits or32-record process cap. There are at most five cases/ten created fixture
processes. Use `python3 -m unittest discover -s Prototypes/AddonPlatform/Tests -p
'Tracing*Tests.py' -v` for all offline evidence tests, including the real observer
progression with only native OS endpoints replaced. No native retries, alternate
profile, guard extension or subsequent phase is part of this diagnostic.

## Separate finite owner-bootstrap diagnostic (C0o)

`zsh scripts/test-addon-owner-bootstrap.sh` builds one trusted hardened Supervisor
and fixed A/B Stubs with sandbox-only entitlements, plus distinct A/B Workers with
exactly sandbox+inherit. A generated run namespace and compiled identity/path table
bind all five products to the existing development signer. Signed Info, strict
requirements, exact entitlements, dependencies and hashes are retained. This is
fixed-fixture byte documentation, not a production template-equivalence validator.

The separate `owner_run.py` observer uses the shared finite `run_case` transport
with an immutable launch/record specification. It runs O1 A seed, O2 B seed and A
cross-check, O3 A continuity and B cross-check, then O4 the matched traced A case.
Each requires its predecessor's actual normal exits and accepted evidence. O4
validates the owned exec stop's fresh A Worker S3 against O3 S4 before the sole
continue. S4 signing identity is Worker; the Foundation sandbox home must remain
that owner's Stub container. The original 5/3/2-second guards, 1.5-second work
window, inherited guard slack, NPROC zero and record caps remain unchanged.

Only fixed Worker code after S4 creates or reopens a 64-byte owner specimen and
opens the prior owner's exact positively established path without reading or
writing it. EACCES/EPERM alone is denial. A third 64-byte synthetic control is
exclusively created by the observer in its fresh non-container Application Support
directory. The observer never reads existing user content or another container.
Two owner specimens remain listed diagnostic residue; OS container metadata and
framework allocations are unmeasured. No TCC grant or prompt interaction is part
of the fixture. Blocked syscalls remain unknown, stop progression and retain owned
cleanup observations under the same deadlines. No native retries or extra cases.

The separate `owner-report.json` schema retains partial observations and actual
terminations. Even complete O1–O4 results never admit a native launcher, certify a
production template verifier, qualify managed death/races or imply universal VM
protection, macOS 14 runtime or distribution support. Historical A/B/C/U reducers,
profiles, tests and frozen results remain unchanged, including C/U unknown and the
separately correlated U startup crash. Offline verification:
`python3 -m unittest discover -s Prototypes/AddonPlatform/Tests -p '*EvidenceTests.py' -v`.

## Separate finite managed-death diagnostic (C0d)

`death_run.py` uses a separate immutable `DeathRecordSpec` in the existing
`run_case` observer loop. **Native execution is on HOLD:** the pre-trace
parent-selection safety gate is unresolved. `zsh scripts/test-addon-managed-death.sh`
unconditionally explains this hold and exits **78 before mktemp, preflight,
compilation, signing or any fixture launch**. There is no flag/environment bypass;
removing the guard requires a separately reviewed source/design change. Offline
tests do not release this gate, and the underlying observer is not an alternate
execution entry point. The preserved, unreachable native body is prepared for one
fresh build, three fixed products (Supervisor, A Stub, A Worker) and at most four
sequential cases/eight participants, two at once. Every successor needs its exact
same-build predecessor's accepted evidence. Failure stops the sequence; no fifth
case, retry, alternate signer/profile or longer guard is allowed.

D0 is the untraced inherited Worker baseline. D1 requires the traced owned SIGTRAP
exec stop, fresh matching Worker S3 and sole successful continue/S4. Both need
normal native child wait, child proc status, Supervisor proc status and direct
Supervisor wait, with matching statuses. D2 authenticates S3, enters a terminal
Supervisor input hold **before** any continue, and requests SIGKILL only for the
owned Supervisor. Every hold return—including EOF, timeout or an unexpected
token—takes the failure/owned-cleanup path and cannot continue. D3 performs the
D1 path plus inherited guards and denial controls, emits one idle-ready marker,
then executes a single terminal `pause`. It neither polls nor rearms the alarm.
The marker identifies a fixed code path, not an observed scheduler state.

All four Supervisor launches use `start_new_session=True`. Fixed native records
include self PID/PGID/SID; the Stub and its in-place Worker must remain in the
Supervisor's private session/group. These fixed roles never call setsid/setpgid,
change credentials or create more descendants. The direct Popen Supervisor stays
strongly referenced and unreaped while cleanup authority is reserved. No early
Popen poll/wait/send_signal/kill/terminate/communicate is permitted: CPython's
signal helpers may reap. Injection uses one `os.kill` on the frozen direct PID.
Failure may request one `os.killpg` on its reserved group before the final reap;
any such request disqualifies a managed-death success. This fallback is scoped
to fixed non-escaping fixture code, not arbitrary addons or production cleanup.

Proc registrations request NOTE_EXIT and NOTE_EXITSTATUS before the start token.
A unique typed spawn and any provisional Stub guard are checked before child
registration/release. The original registration survives exec. The shared loop
processes every delivered notification and complete buffered line before any
injection, retains bounded raw output after protocol failure, and continues exit
observation while the original queue remains usable. A refused initial proc
attachment retains the already registered stdout filter: admission stays failed,
one fallback is requested, output drains without any later registration or start
token, and missing exact child exit remains unknown. It never re-registers a late
PID. Registration/receipt errors, invalid flags/statuses and contradictions fail
closed. Status-less exact exit can establish exit occurrence but not death cause.
Child kqueue status is never relabeled as native child wait.

Success needs both exact exit statuses and complete stdout/EOF. D2/D3 require
SIGKILL for both participants, no native cleanup/guard/fallback, and both event
receipts plus the final direct wait strictly before the observer timestamp taken
immediately before Popen plus 1.5 seconds. This conservative bound excludes the
unchanged two-second child alarm without comparing foreign clock epochs. Native
records retain CLOCK_MONOTONIC and the original 1.5-second work/guard-minus-0.4
limits. External five-second, Supervisor three-second and child two-second guards
remain unchanged; the one fallback cutoff is four seconds. There is still a gap
between observed events and signal delivery: status alone cannot identify its
sender or exclude external interference. Missing exact exit observation remains
unknown, including when a group signal succeeded or a stopped child has an alarm.

The generated three-role identity/path table, exact profiles, signed Info, strict
signature requirement, existing development signer, dependency set and hashes are
verified before launch. Native DEATH_FIXTURE routing leaves historical and owner
routing intact. A small generated Objective-C linkage unit retains Foundation and
libobjc startup; it performs no owner-storage calls. Only an exclusive 64-byte
synthetic non-container control and loopback positive control are used. The
observer removes only its successfully created control; it never traverses or
cleans OS containers. OS metadata is unmeasured. Raw logs remain bounded to 4096
bytes per line, 32 records per PID, 96 records/256 KiB per case, 1 MiB across four
cases. Native event loops retain their existing 12-event bounds.

The unconditional separate `death-report.json` records partial evidence,
refusals/regressions, injection and fallback requests separately from observed
terminations. Setup/build failure stays unknown. A complete fixed diagnostic may
report `fixedManagedDeathObserved`; `nativeLauncherAdmitted`,
`productionTemplateVerifierQualified`, `hostDeathQualified` and
`startupRaceQualified` remain false; `allVMProtectionsPreserved` remains unknown.
It does not qualify actual Cascade death, pre-TRACE_ME startup, arbitrary code,
escaped process groups, macOS 14 runtime, other signers/distribution or universal
VM protections. No earlier C0 report is reinterpreted.

Offline only:
`python3 Prototypes/AddonPlatform/Tests/ManagedDeathEvidenceTests.py`.
The tests replace OS endpoints around the real observer/reducer/four-case driver;
they create no native fixture participants. The build script pins the reviewed
Python 3.14.6 subprocess lifecycle source hash before native setup. The native
command remains unconditionally blocked until a separately reviewed source/design
change resolves the safety gate; no native measurement is authorized by these tests.
