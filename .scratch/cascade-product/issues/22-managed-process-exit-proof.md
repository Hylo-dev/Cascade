# Define a safe exit proof for managed processes

ID: 22
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: none

## Question

Which proof design can verify the actual exit of the worker after the supervisor's death, even when that death precedes the tracing attach, without involving a process unrelated to the proof? Define verifiable conditions for revisiting the C0d gate; if no compliant mechanism exists, record the limit without enabling the launcher.

## Verified context: 14 September 2026

The [offline C0d diagnostics](../../../docs/superpowers/verification/2026-09-12-addon-managed-death.md) are implemented and reviewed. The driver exits with code 78 before compiling or starting the participants; the native test remains unrun. The documentation identifies the race between the supervisor's death and tracing as a still-open obstacle. The parent's before/after checks have not been qualified as an atomic constraint.

The acceptance of the risk of work delegated to macOS, documented in the [control policy](../../../docs/superpowers/specs/2026-09-10-addon-control-policy.md), is already acquired and does not resolve this separate requirement on managed processes. The tests of the pure runtime and of storage do not qualify the launcher.

This ticket prepares a decision on the design and on the necessary proofs. It does not authorize native runs, changes to the gate or new exceptions. The [external SwiftUI UI probe](19-extension-host-probe.md) remains a separate investigation. The outcome will feed [extension installation and isolation](05-extension-distribution.md).

## Update: 18 September 2026

Codex Astra high investigation completed read-only: [analysis of the mechanisms and of the missing proofs](../../codex-addon/20260918-continuation/managed-process-design.md). No demonstrated solution yet covers the worker's entire lifetime window. Attach from the supervisor and management through launchd require separate qualifications; the bootstrap abort protocol alone does not demonstrate the process's exit in every phase. No native test run, no change to the C0d gate; ticket open.

## Offline preparation completed

The subsequent [finite model of the bootstrap](39-bootstrap-abort-offline.md) is verified with 31 tests and an independent review. It reproduces parsing, deadlines and the rejection of inconsistent evidence using only synthetic observations. It does not demonstrate physical exit or coverage from creation to attach/exec; this ticket remains open, without authorizing a native experiment or changing the gate.

## Decision point: 20 September 2026

The current continuation authorizes several increments up to a necessary design decision or the margin of the weekly 20% cap. The [C bootstrap](40-bootstrap-abort-c.md) concludes the offline preparation: main compiled, logic verified in memory, no native test process run. No other equivalent parser or model is needed.

The step to the launcher runs into a guarantee that still has no qualified mechanism: actual exit even when the supervisor dies between the creation of the process and the bootstrap's entry into main. EOF reading and deadlines start working only when the trusted code runs; they do not prove exit during an earlier stall. Attach/stop under the current signing and sandbox profiles also remains to be qualified. This is a limit of the available proofs, not a demonstration that the platform makes it impossible.

**Choice presented to the user (resolved below):** keep the managed-process exit requirement in full, leaving the launcher disabled until a qualified solution exists (recommended), or open an explicit revision of the requirement limited to the trusted bootstrap before the attach. The second path would accept that that process may stay alive if it fails to perform the abort; it is not equivalent to a guaranteed timeout and does not extend the exception to the addon's arbitrary code. It is not approved by this continuation and does not automatically enable any launcher.

The [already approved policy](../../../docs/superpowers/specs/2026-09-10-addon-control-policy.md) states: "It does not make an orphaned managed process acceptable". The exception on work delegated to macOS remains separate and must not be requested again. The decision concerns this precise guarantee, not a generic authorization to continue.

A future bounded proof without tracing is already described: baseline and loss of the supervisor, two fixed participants per case, preserved identities, observation of the actual exit and stop at the first incomplete result. Even a positive outcome would demonstrate the abort only in the observed runs; it would not close the pre-main window. The [existing design](../../codex-addon/20260918-continuation/managed-process-design.md) remains an unexecuted proposal. No gate, entitlement or requirement changed.

Stop required at the decision: no new ticket closed, no agent launched and no new product test run in this survey. Last observed counter 1% weekly, below 20%; the budget is not the cause of the stop.

## User decision: 20 September 2026

"We keep the launcher blocked". The guarantee of actual exit of managed processes is kept in full, including the trusted bootstrap before the attach. No exception for a stall before main. The policy choice is resolved and must not be proposed again without new directions from the user.

The launcher remains disabled and the C0d gate unchanged. This ticket remains open for the separate technical problem of the compliant proof; the launcher is not declared qualified and the activities that require it are not implicitly unblocked. The offline tests already delivered keep their scope. Any independent activities remain subject to their own requirements and to the weekly 20% cap.

## Subsequent research: 23 September 2026

[Verify lifetime management through launchd](68-launchd-managed-lifetime-research.md) is concluded with Apple sources and a check of the corresponding SDK: that avenue does not establish the full guarantee already required. It is neither a proof of general impossibility nor a native experiment. The choice to keep the launcher blocked remains acquired; this technical ticket remains open.

## Continuation of point 1: 24 September 2026

The request "let's proceed with point 1" resumes the research on the launcher and the authenticated transport without changing the requirements. The [examination of spawn/exec/fork](../../../docs/wayfinder/research/2026-09-24-spawn-managed-lifetime.md) finds no public primitive for lifetime ownership from creation: suspended launch, image replacement and tracing inheritance do not close the known window. The [launcher/transport link](../../../docs/wayfinder/research/2026-09-24-launcher-transport-frontier.md) distinguishes the avenue of the client-bound XPC service from the earlier LaunchAgent/Daemon ones, and records the requirements still unqualified and the limit of the XPC checks on outgoing messages. It includes a technical question for Apple DTS, not sent. No native test, gate change or production admission; ticket still open because of a technical obstacle, without proposing the policy choice again.

## XPC test authorized afterwards: 24 September 2026

The subsequent instruction "ok, proceed with the targeted XPC test" authorizes only the
isolated experiment, now [run and documented](../../../docs/superpowers/verification/2026-09-24-addon-xpc-lifetime.md).
The fixed service included in the bundle exits when the client exits normally or
with SIGKILL, even with a retained callback. Cancelling the connection while the client
is alive produces no exit within the two seconds observed. Cooperative baseline positive;
final exit of all participants confirmed, without using the SIGALRM guard.
Still unqualified: stop while the host is alive, coverage before main and external
packages. No change to gate, policy or admission; ticket still open.

## Dedicated XPC intermediary: subsequent test of 24 September 2026

On the request "explore and run tests for this avenue", the [fixture with two nested XPC chains](../../../docs/superpowers/verification/2026-09-24-addon-xpc-broker.md)
passes four scenarios in the final run: ordinary exit and SIGKILL of broker A
terminate its blocked worker while the app and chain B stay active; ordinary exit
and SIGKILL of the app terminate both brokers and workers. A first crash simulation
produced an error code and was kept as FAIL, then fixed and rerun.
The result qualifies only the fixture after main on this macOS version.
Still remaining: launch before main, support for nested packaging, external packages and
shutdown if the trusted broker also does not respond. Ticket open and gate unchanged;
no new policy decision required.

## Blocked broker callback: continuation of 24 September 2026

The [subsequent test](../../../docs/superpowers/verification/2026-09-24-addon-xpc-broker-blocked.md)
confirms that stop and cancellation on the channel with a blocked callback do not make A exit
within the two seconds observed; the app's death still terminates all the services. A second
authenticated channel to the same broker incarnation instead allows stopping A
while leaving the app and B active. This resolves the stall of the tested callback, not a hang
of the whole broker. Pre-main guarantee and external addons not qualified; gate unchanged.

## XPC frontier: further continuation of 24 September 2026

The request to continue autonomously up to a design choice produced
[new signed tests](../../../docs/superpowers/verification/2026-09-24-addon-xpc-frontier.md).
With all the broker's command callbacks blocked, the second channel does not stop A;
normal exit/crash of the root terminate the four services in the dedicated tests. In the cleanup
after a pending stop, A takes about five seconds after the root: the fast timing
of every sequence is not guaranteed. No test of suspension of the whole process or pre-main.

The new discovery fixture finds the external provider from the app, but from the broker
it reports an empty list and unapproved=1. No target error when building the modern
point. Diagnostic browser not inspected because the Mac is locked; no consent
changed, no provider started. The libproc APIs with audit tokens are not admitted
as supported public APIs. The new choice, still pending, concerns a possible
global emergency restart, not the acceptance of orphans. Gate still exit 78 and
unchanged; policy and production admission remain unchanged.

## Global recovery accepted and external addon: 24 September 2026

To the previous proposal the user replies "accepted, go on". The decision
`native-addon-global-recovery` is now closed in the policy: global restart admitted
as a last resort, verified exit and absence of orphans still mandatory.
The subsequent consent concerns only the local extension CascadeAddonProbeContainer.

The [new test](../../../docs/superpowers/verification/2026-09-24-addon-global-recovery.md)
confirms five scenarios after authentication: direct recovery after normal exit
and crash of the host, with a new chain only after the exits; broker stop with the
external provider terminated and the app responsive; normal exit and crash of the root with
broker/provider terminated. Complete cleanups, guards not involved in the PASSes. After the consent
action the broker finds and starts the provider with legacy discovery; the modern one
keeps reporting unapproved=1. The AX state of the toggle is not proof of enablement.

External packaging therefore has a positive composition proof, limited to the
fixture signed by the same publisher on macOS 27 beta. Still remaining: pre-main, independent
observation of the exit during a pending launch, reuse across hosts, isolation between
simultaneous external addons, other publishers/OSes and integration. The updated technical question
for Apple is a local draft, not sent. No product adapter admitted, gate
exit 78 unchanged; ticket still open for an unqualified technical requirement.

## Deeper look at public sources: 24 September 2026

The user rules out contacting Apple and asks to search the documentation.
The draft question is archived, not sent; a private answer is not a
prerequisite for continuing. The [updated research](../../../docs/wayfinder/research/2026-09-24-extension-startup-documentation.md)
finds an already public Apple DTS answer: the host controls the
ExtensionFoundation lifecycle through AppExtensionProcess and invalidate, distinct from the
lifecycle of XPC services. The APIs document the release of the last connection
and onInterruption, which can be configured already in the launch request.

The fixtures do not set that callback yet. Comparing the notification with the kernel
exit, with correlation to the request and a check of the references, is a concrete
next test derived from the public APIs. It was not run in this
deeper look; pending startup and host death remain distinct. No evidence
about orphans inferred from the documentation's silence, no new admission.

## onInterruption verification run: 24 September 2026

On the request "proceed with the verification", [five native scenarios](../../../docs/superpowers/verification/2026-09-24-addon-interruption.md)
compare the callback configured before the initializer with kernel events
recorded after authentication. Voluntary exit and crash of the provider both produce
an exit and the callback with the same nonce. Cooperative invalidation, cooperative
release and invalidation with a blocked callback produce neither of the two
within the six seconds observed, even with strong properties and four weak nil. Complete
cleanups through host shutdown; no guard expired.

The review fixed a timing edge and the final build repeated all
the cases. The notification is usable as an observation, not as a forced stop nor
as coverage when its host dies. The absence of all the framework's internal references
is not inferred. Requested test concluded, general ticket still open,
gate unchanged, no request to Apple.

## Ordinary turnover and recovery with a live host: 25 September 2026

The [broker verification](../../../docs/superpowers/verification/2026-09-25-addon-broker-sessions.md)
adds three native PASSes: a new chain in the same host after a verified exit,
two simultaneous hosts with distinct processes and the second session preserved, two
successive cooperative providers in the same broker. The broker restart takes
about 10.15 s; the turnover of the provider alone about 66 ms in the final test.
The three previous regressions (broker stop, host quit, host crash) remain PASS.

25 Python tests and a review with no P1/P2; final cleanups complete. Also kept
are the first attempt without the restart command and the one with a too-short startup
timeout, the latter with an unidentified second chain and an unqualified cleanup.
Late loading into a trusted container was evaluated in the sources:
it adds a format/ABI and does not resolve the container's pre-main. It is not adopted.

The post-handshake part now has an ordinary path and a recovery that can concretely
be run in the fixture. C0 remains open and the gate unchanged: the
system is not declared usable in the app while the required startup guarantee has no proof.


## Independently observed startup: 25 September 2026

With the authorized autonomous continuation, [15 native scenarios](../../../docs/superpowers/verification/2026-09-25-addon-startup-observation.md)
were run, PASS, plus three rejections of unrelated senders: provider stuck in AppExtension.init,
in a C constructor before the entry point and in the same constructor with SIGTERM
ignored. In each variant: unblock check, broker stop/crash and root quit/crash;
the resistant profile exits with SIGKILL, cleanups complete and the observer alive.
33 unit tests green. Also kept: the failed AF_UNIX preflight and the crash due
to the wrong entry point of the first manual build, later fixed.

The identity is verified by a Mach audit trailer, a requirement with the exact CDHash,
EV_RECEIPT and a challenge after registration. The fixture adds only the lookup
of the unique diagnostic name; profile separate from the product, service absent at the end
of each case. The broker is already process-ready while the fixture is parked: the return
of the host initializer does not prove that the provider has finished its own init.

The interval creation → first diagnostic code remains unqualified; the
constructor runs after parts of dyld/libSystem and does not cover the whole pre-main. No
new waiver, no request to Apple, no launcher enabled. Gate exit 78
with unchanged hash. Ticket open for the technical frontier, without proposing again the
policy choice already closed.

## Identity without HELLO and suspended lab: 25 September 2026

The [external test](../../../docs/superpowers/verification/2026-09-25-addon-external-identity.md)
verifies, in two runs, task-name port, kernel token, signature/CDHash/path and kqueue
receipt before the first HELLO. Negatives rejected, turnover in the same job observed,
kernel exits and cleanups complete. Ordinary provider profile sandbox-only and HR.
`task_for_pid` remains denied; `launchctl debug` with only a diagnostic variable is
rejected because it requires root. No suspended launch performed.

The next avenue is the test in a disposable macOS VM: same signature, configuration
privileges in the guest and cleanup of the whole environment controlled by the host.
It is neither an already qualified production solution nor an exception on orphans. The VM
is not prepared yet: about 6 GB free on the current volume, against 25 GB stated
for the ready image alone. Asked for a volume with at least 60 GB
of operating margin. Gate and policy decision unchanged.

## Preparation with reduced space: 25 September 2026

After the user freed space and asked for a small VM, the
[preparation](../../../docs/superpowers/verification/2026-09-25-addon-small-vm.md)
selects a single vanilla Sonoma 14.1, without Xcode, 2 CPUs and 4 GiB of RAM.
The 50 GB disk is sparse: the previous 60 GB margin is not treated as
a demonstrated minimum requirement. The test reuses the original signed fixture
and a payload of about 32 MB.

The first download reaches 99% but is stopped by the configured reserve of
4.5 GiB; the controller deletes only the incomplete state of the attempt and
recovers about 16.4 GiB. A second attempt, in progress, reserves 3 GiB during
the download and 3.5 GiB at launch, keeping the partial data at every interruption.
No guest or suspended addon has been started yet: the measured obstacle is the
lab's space, not a negative result of the framework.

Twelve tests of the updated runner pass; real refusal on the host verified
before starting any fixture. The optional stackshot diagnostics remain
separate from the baseline payload. External VM shutdown, resume check and
death cases remain to be qualified. Gate exit 78 and hash unchanged.


## Small guest started and discovery limit: 26 September 2026

The [small VM verification](../../../docs/superpowers/verification/2026-09-25-addon-small-vm.md)
now contains real launches: 2 CPUs, 4 GiB RAM, allocated disk 16.63 GiB. The measured
guest is Sonoma 14.3/23D56, not the 14.1 of the tag. SIP was disabled in the image:
re-enabled through Recovery and verified before the fixtures. VZ shutdown from the host
qualified with exit 0 and restart with a different UUID; no SIGKILL fallback.

Fixed an error in the runner's preflight: codesign verified all slices
against the ARM64 CDHash. Explicit ARM selection passes with the original requirement;
negative checks rejected and 12 pure tests pass. Manifest and fixture unchanged.

The first HELLO from the broker on this guest times out: discovery stays `idle`, LS log
`-10814` and a null extension point. Neither registering the exact app nor launching it through
Launch Services changes the result. The fixture's consent is already
enabled in the system UI. The GUI finds and starts the provider, which rejects
that peer correctly because the fixture accepts only the broker.

No suspension is armed and no suspended-death case is run.
VM shut down, evidence kept on the host. The small lab is usable, but
this composition on the 14.3 guest does not pass the discovery prerequisite.
It is neither proof of a general impossibility on macOS 14 nor a decision to raise
the app's minimum. C0 and launcher admission remain open; gate exit 78 unchanged.


## VM pause and space returned: 26 September 2026

The user asks to stop the VM approach and look for an avenue without a VM.
The Sonoma machine is deleted with the Tart command, after confirming it was stopped;
VM list empty, disk absent. Runtime/cache and lab credentials removed.
About 18 GB returned; the evidence and the original fixture remain in the repository.
The 26/27 images were consulted only in their metadata, never downloaded.
No architecture decision or lowering of the guarantees is inferred
from this request. The host options must first qualify a safe recovery
without confusing controlled POSIX children with non-parental EF processes.

The [review without a VM](../../../docs/wayfinder/research/2026-09-26-addon-host-recovery-after-vm.md)
identifies as a candidate the recovery of the ordinary job with the broker still alive;
no new experiment run, no transfer of the result to
START_SUSPENDED or to the supervisor's death.
