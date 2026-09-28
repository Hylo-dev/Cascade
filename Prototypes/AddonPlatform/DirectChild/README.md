# Direct-child native supervision probe

**Experimental. Native direct-child control works in the cases below; the strict
process-containment profile still FAILS. Nothing here is imported or launched by
Cascade. This does not approve a production launcher.**

The unresolved counterexample is real: a sandboxed worker with `RLIMIT_NPROC` soft
and hard limits of zero can ask Launch Services to launch a readable embedded app.
That app runs under PID 1, outside the supervisor's owned child tree. A process quota
on the worker therefore does not govern every process it can cause to run.

## Run

```sh
/bin/zsh scripts/test-addon-direct-child.sh
```

Requires a logged-in macOS desktop, Xcode and the configured Apple Development
identity. `CASCADE_PROBE_SIGN_IDENTITY`, `CASCADE_DIRECT_CHILD_PRODUCTS` and
`DEVELOPER_DIR` override the defaults. Products are built in
`~/Library/Developer/Xcode/DerivedData/CascadeAddonDirectChild/Products`, not iCloud.
Each of the three cases has a five-second external deadline and the native
supervisor also has a three-second guard. The default script currently exits **1**
because delegated-launch containment fails. It never substitutes a simulated PASS.

Only the fixture processes, their newly created nonsensitive sentinel, loopback
listener, and marker are used. The delegated target is a newly built signed app
inside `DirectWorker.app/Contents/Resources/LaunchFixture.app`; it writes one marker
outside its own bundle and exits immediately. No installed third-party/system app
is launched as the delegated target. The source app and Cascade are not required
for these standalone fixtures.

`Results/latest.jsonl` and `Results/signature.txt` are ignored run artifacts.
The recorded final run is also available locally at
`/private/tmp/cascade-direct-child-final.log`. The result table below preserves the
important evidence independently of those disposable files.

## What the native prototype implements

1. `DirectHost` creates a pipe and owns its only write end. It starts a trusted,
   separate `DirectSupervisor` with the read end.
2. The single-threaded supervisor forks its direct worker child. In that child,
   **before exec enters addon code**, it lowers `RLIMIT_NPROC` soft and hard limits
   to zero. A failed limit installation aborts launch. Neither host nor supervisor
   has its process limits changed.
3. The signed worker app has only `com.apple.security.app-sandbox = true`, with
   hardened runtime and no network/file exceptions. Direct exec activates this
   signed App Sandbox configuration on the tested machine.
4. The supervisor retains the child without reaping it. `waitid` with `WNOWAIT`
   observes exits while preserving the direct child's PID identity. It has no
   automatic SIGCHLD reaper or competing wait thread. Consequently a concurrent
   child exit cannot reuse that PID between observation and `kill`.
5. An explicit stop byte, or EOF when the host exits or is killed, makes the
   supervisor send SIGKILL and reap that exact child once using `wait4`. After the
   reap it never samples or signals that numeric PID again. Detection and stop are
   outside the untrusted worker; its spin loop does not cooperate.
6. The supervisor samples its live child's physical footprint and CPU with public
   `proc_pid_rusage`. CPU counters are Mach time units, converted using
   `mach_timebase_info`; the external harness cross-checks against `wait4` CPU time.

The pipe carrying the worker's bounded diagnostic line is a test transport. There
is **no authenticated XPC session**, manifest admission, publisher verification,
production service protocol, or claim that the worker's own report authenticates
anything. Runtime signing-admission and inherited-descriptor hardening still need
their own implementation and hostile-peer tests.

## Recorded verification, 9 September 2026

macOS 27 beta, build `26A5425a`; Apple silicon; Xcode beta SDK 27; deployment target
14.0. All four fixture binaries are development-signed, worker team
`A6A5HQL6K4`, identifier `hylo.Cascade.AddonDirectChildProbe.Worker`.
`codesign --verify --deep --strict` passed for the worker including its nested app.
Other OS releases, Intel, distribution signing and another publisher were not run.

| Case | Host / supervisor / direct worker | Actual direct-child outcome | Signal → reap | Overall profile |
| --- | --- | --- | --- | --- |
| Explicit stop | 51094 / 51095 / 51096 | SIGKILL and reap; host still alive afterward | 0.74 ms | FAIL: delegated launch |
| Host normal exit | 51098 / 51099 / 51100 | Pipe EOF, SIGKILL and reap | 0.76 ms | FAIL: delegated launch |
| Host SIGKILL | 51102 / 51103 / 51104 | Pipe EOF, SIGKILL and reap | 0.69 ms | FAIL: delegated launch |

These are observations, not performance guarantees. Whole external cases took
666.21, 361.23 and 361.98 ms respectively, including launch and a deliberate 300 ms
spin. Signal-to-reap excludes the pipe-detection interval.

All three final cases recorded:

- Host and supervisor process limits stayed at soft 2666 / hard 4000. Worker limits
  were 0 / 0; an attempt to raise them failed with `EPERM` (1).
- Direct `posix_spawn("/usr/bin/true")` failed with `EAGAIN` (35).
- Reading the new foreign sentinel, opening a loopback connection, and sending
  SIGUSR1 to the trusted supervisor failed with `EPERM` (1). A signal handler in
  the supervisor confirmed that no signal was delivered.
- Actual footprint was 19,595,792 / 19,546,640 / 19,530,232 bytes, including a
  deliberate 16 MiB touched allocation. These numbers are not an idle addon budget.
- 14–15 CPU samples succeeded. Sampled total CPU converted with timebase 125 / 3
  was 0.317905 / 0.289870 / 0.307693 seconds; independent `wait4` totals were
  0.320487 / 0.310682 / 0.311162 seconds. Samples stop shortly before the final reap.
- Launch Services returned success (0). The external marker identified launched
  PIDs 51097 / 51101 / 51105, each with parent PID 1 and the exact embedded fixture
  bundle path. The embedded Info.plist was independently readable by the worker.

Unrestricted positive controls succeeded for direct spawn, reading the same
sentinel, connecting to the same live loopback listener, and launching the exact
embedded fixture. This excludes a blanket ambient test-tool restriction as the
explanation for the negative sandbox results. `open -W` occasionally prints that
the very short-lived fixture has already exited; the marker, its bundle path and
successful return are checked independently.

### Behavioral RED and stronger negative check

The initial native implementation deliberately had no pre-exec process limit.
The same three scenarios failed their process-limit and subprocess-denial checks:
the signed sandboxed worker successfully spawned `/usr/bin/true`. Installing the
limit only in the forked child made those checks pass. The original RED log is
`Results/red-no-process-limit.jsonl`; its early CPU fields were misleadingly named
nanoseconds and must be read as raw counters, corrected in the final source.

The first delegated-launch test used a sibling app outside the worker's readable
bundle. It returned error -54 and no marker. That was **insufficient evidence** of
Launch Services containment. Moving the target inside the signed, readable worker
bundle produced success and a real unowned process. The final harness keeps this
stronger negative check, so it fails instead of concealing the limitation.

## Remaining qualification

This proves a useful control primitive for a direct child and demonstrates why
`RLIMIT_NPROC = 0` alone is insufficient for the required complete resource policy.
Rejecting this particular nested app would not prove every other delegated launch
path is controlled. No supported general denial mechanism for that surface is
established here.

Still unqualified: authenticated host/provider IPC, cross-publisher admission,
exec replacement and session invalidation, delegated services and launches beyond
the observed example, trusted-supervisor crash recovery, inherited environment/FD
allowlists, hostile output/backpressure, races at scale, metrics-driven enforcement,
thread limits, runtime memory/CPU budgets, remote SwiftUI, energy and other OSes.
The fixture's 20 ms observation loop and one supervisor per active worker are test
choices, not the approved production scheduler or an efficiency benchmark.

The implementation uses public SDK APIs only. Reading Apple kernel source below
explains their counter representation; it is not a dependency on kernel-private APIs:

- [Apple XNU: rusage population](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c), `fill_task_rusage`.
- [Apple XNU: task CPU counters](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c), `task_power_info_locked` stores Mach-time counters.
- [Apple CPU accounting overview](https://github.com/apple-oss-distributions/xnu/blob/main/doc/observability/recount.md).

## C0 completion evidence, 10 September 2026

The default command now runs the three original cases, supervisor death, executable
replacement, 20 further start/stop sequences and 20 immediate versus 20 reused echo
requests. Each sequence retains its five-second external deadline; a three-second
worker alarm bounds diagnostic cleanup even if its supervisor dies. **That alarm
is addon cooperation, never evidence of runtime crash cleanup.** Allocations remain
16 MiB, below the 64 MiB guardrail. The replacement binary has the documented
App Sandbox inheritance profile; the ordinary worker's sandbox profile is unchanged.

The supervisor-death test observes the original worker's exact executable externally
under parent PID 1. The exec test executes a distinct signed binary with the same
PID and observes a message on the retained diagnostic pipe. It therefore fails
`sessionInvalidatedAfterExec`; no authenticated direct-child session is implemented.
Neither test signals an arbitrary discovered PID.

Each case emits `schemaVersion`, `scenario`, `checks`, `observations`, `unverified`.
`Results/launcher-admission.json` aggregates the observations and remains rejected by:

```sh
python3 scripts/assert-addon-evidence.py Prototypes/AddonPlatform/DirectChild/Results/launcher-admission.json launcher-admission managedStop hostExitCleanup hostCrashCleanup identitySafe cpuReadable footprintReadable delegatedWorkControlled
python3 -m unittest discover -s Prototypes/AddonPlatform/Tests -p CompletionEvidenceTests.py
```

The first command must fail until all admission evidence exists. The second tests
report completeness only. Missing files, malformed JSON and unverified records fail.
The [C0 decision](../../../docs/superpowers/verification/2026-09-10-addon-launcher-decision.md)
records measured costs and remaining guarantees. CPU values use the observed Mach
timebase. Host/supervisor footprint is sampled simultaneously; CPU is sampled before
teardown and does not include every final instruction. The echo comparison uses a
nominal 20 ms quiet interval, no polling in production and no production reuse policy.

C0 review correction: executable-image observation and diagnostic pipe survival are
separate evidence fields. Missing output (even after successful exec observation)
never means authenticated invalidation. `sessionInvalidatedAfterExec` stays false
and unverified because this prototype has no authentication/invalidation mechanism.
Pure regressions run with `python3 -m unittest discover -s Prototypes/AddonPlatform/Tests -p C0HarnessRegressionTests.py`;
these do not launch native fixtures or change their earlier recorded failures.
