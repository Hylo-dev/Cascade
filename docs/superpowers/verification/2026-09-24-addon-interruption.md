# onInterruption and extension release: native verification

24 September 2026, macOS 27 beta 26A5425a, arm64, SDK 27.0.
Verification authorized after the [documentation research](../../wayfinder/research/2026-09-24-extension-startup-documentation.md).
No contact with Apple. **No launcher admission.**

## Final outcome

`onInterruption` is delivered after the provider's voluntary exit and crash,
with the exit of the same incarnation observed independently from the kernel.
It is not delivered within the six seconds after invalidation/release; in those cases
the provider's exit is not observed either, including the cooperative case.

| Scenario with host still alive | Kernel exit within the window | onInterruption | References visible after release |
| --- | --- | --- | --- |
| Provider exits voluntarily | Yes, status 0 | Yes, same nonce | Intentionally kept as a control |
| Provider triggers its own crash | Yes, SIGKILL | Yes, same nonce | Intentionally kept as a control |
| Invalidation, cooperative provider | Not observed | Not observed | Strong properties nil and four weak nil |
| Release, cooperative provider | Not observed | Not observed | Strong properties nil and four weak nil |
| Invalidation, provider callback blocked | Not observed | Not observed | Strong properties nil and four weak nil |

In the controls, the notification is recorded about 3 ms after the kernel observation; this
is not a latency guarantee. In the three cases without an exit, cleanup closes the host
normally and then observes the provider's termination with SIGKILL. All cleanups are
complete; none of the five providers reaches its own SIGALRM guard.

The runner ends with exit0 because the observations are complete and attributed.
**It does not mean that five selective stops succeeded.** The three negative
results have a six-second bound: they do not prove indefinite survival.

## How the observations were separated

The callback is configured before `AppExtensionProcess(configuration:)` and captures
only a launch nonce, without retaining the process or channels. Notifications are
recorded with a monotonic clock under a lock and read from the fixture's snapshot.
Comparisons begin after startup: kqueue registration with a receipt between two
authenticated responses from the same incarnation, exact signature and path, UUID and
guard verified. The notification alone is never classified as an exit.

The common window closes before a last kernel drain and the IPC snapshot.
An exit observed in the final drain only after the cutoff makes the comparison UNKNOWN; later
notifications remain in `lateNotifications`. In the five final cases this list is
empty. Cleanup timings and exits are kept separately.

Independent post-launch guards: provider 25 s, host 35 s. No kill sent to PIDs
discovered or chosen by name. Provider crash requested on the authenticated channel and
carried out by the provider itself; cleanup limited to the retained host child and to the
subsequent kernel observation of the registered provider.

## What the reference check says

In the three release cases, the host's properties for AppExtensionProcess,
channel, bootstrap, listener and delegate are nil. The weak references to the four
Foundation/delegate objects are also nil. The asynchronous startup method has already
returned before the commands; the callback does not capture an owner of the process.

The `release-cooperative` case invalidates the channels and the listener, but releases
AppExtensionProcess without explicitly calling its `invalidate()`. The
`invalidate-cooperative` case also calls the latter. Neither one terminates the
provider within the observed window.

This weakens the hypothesis of a forgotten reference **in the fixture's checked
properties**. AppExtensionProcess is a struct: the verification does not observe all
of ExtensionFoundation's internal references, nor does it infer its implementation. It
therefore does not attribute the cause to a macOS bug, to ARC, or to the persistence of
a specific internal connection.

## Review and validation

The first run is kept in `initial-window-boundary`. An independent
review found a P2 in the window boundary: the IPC snapshot extended
the declared time without further kernel observation. The runner was corrected
and the five cases rerun in the final build `probe-ifxbuc_6`; the report uses only
these final results.

The final review confirms the P2 closed and finds no other material issues.

Three classifier tests verify notification/exit separation, negative
observations, and rejection of inconsistent nonces, guards or timings. Four Recovery tests and
five BrokerRecovery tests remain green. Swift typecheck of the ordinary host and
provider profile succeeded. The full CascadeKit suite was not rerun: the product
sources did not change.

## Practical consequence and limit

`onInterruption` is useful as a notification of a process that has terminated. The evidence
does not turn it into a command to force its stop, nor into an observer that keeps
working after the death of the host that receives it. [Recovery through the broker](2026-09-24-addon-global-recovery.md)
remains the path with positive evidence of stopping while leaving the app alive.

No coverage of the phase before the handshake, of cancellation with a pending
initializer, or of other operating systems. The gate remains unchanged and exit78. The
requested verification is concluded; the full launcher guarantee remains open.

## Evidence and reproduction

- [Fixture and commands](../../../Prototypes/AddonPlatform/Interruption/README.md).
- [Five final results](evidence/2026-09-24-addon-interruption/final/interruption-results.json).
- [Build manifest and hashes](evidence/2026-09-24-addon-interruption/final/build.json).
- [First run, with the boundary limitation](evidence/2026-09-24-addon-interruption/initial-window-boundary/interruption-results.json).

Each run preserves native sources, runner, hashes, build and registration logs,
authenticated identities, snapshots, kernel events and cleanup.
