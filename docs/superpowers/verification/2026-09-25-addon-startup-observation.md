# Provider exit during startup: 25 September 2026

## Result and limit

15 native scenarios PASS, spread over three variants of the same fixture, plus three
successful negative authentication checks. The provider is identified
while it is blocked inside `AppExtension.init`, then in a C constructor that precedes
the entry point, and finally in the same constructor with SIGTERM ignored. Broker
stop/crash and root exit/crash make the observed provider terminate. In the
resistant profile the kernel status is SIGKILL, with no intervention by the runner on the PID.

**This is not yet the admission of the launcher.** The interval between
process creation and entry into the first diagnostic code remains unproven. The initialization
of dyld and of the dependencies precedes the C constructor. This is not a demonstration of
impossibility, but neither is it a reason to depart from the user's decision of
20 September. C0d gate unchanged: exit 78, SHA256
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Local test on macOS 27 beta 26A5425a arm64, SDK 27, minimum target 14 unchanged.
The fixture's provider and host belong to the same publisher; compatibility with
other systems/publishers and integration into the product are not qualified by this
matrix. The code of the real Cascade app was not modified.

## Authorization and method

The user authorized continuing the tests autonomously until their intervention
is needed. The already enabled external fixture was kept; no new
consent in Settings, TCC grant, permanent service or contact with Apple.
The skills systematic-debugging, ponytail, research, test-driven-development,
requesting-code-review and verification-before-completion guided the investigation.

The observer is a direct child kept by the runner and outlives the root under
test. A Mach HELLO message carries an audit token attached by the kernel.
Security verifies identifier, leaf certificate, **CDHash of the exact build** and
bundle path. The runner registers EVFILT_PROC with EV_RECEIPT and NOTE_EXEC/EXIT;
only after the positive receipt does the observer send an unpredictable challenge.
The ACK must come from the same complete token, UUID, deadline and phase. No
PID declared by the target is accepted without that confirmation.

The observer registers a unique Mach name with `bootstrap_register`, a public
but deprecated API, limited to diagnostics. Only the provider fixture adds
`com.apple.security.temporary-exception.mach-lookup.global-name` for that name;
App Sandbox stays active. This **profile differs from the product** and does not decide
the future SDK transport. At the end of each case the name must come back as UNKNOWN_SERVICE.
The primary sources and the API limits are in the [research](../../wayfinder/research/2026-09-25-addon-startup-observer.md).

The independent guards are 25 s in the provider, 35 in the broker, 40 in the observer,
45 in the root. The measurement window is 8 s, entirely before the guards.
The verdict uses the snapshot of the exits taken before the cleanup: neither SIGALRM nor a
later cleanup kill can produce PASS. The only processes the runner can terminate
directly are kept Popen children; no kill on a discovered PID.

## Observed matrix

| Case | AppExtension.init | C constructor | C constructor with SIGTERM ignored |
|---|---|---|---|
| Unblock and ordinary channel of the same instance | PASS | PASS | PASS |
| Broker stop, root still responsive | PASS | PASS | PASS |
| Broker SIGKILL, root still responsive | PASS | PASS | PASS |
| Normal root exit | PASS | PASS | PASS |
| Root SIGKILL | PASS | PASS | PASS |
| Sender with a different signature/identity rejected | yes | yes | yes |

The unblock check verifies the same PID/UUID/deadline through the
normal XPC channel, then stops the chain. In the other four cases the block is not released.
All ordinary providers exit with SIGTERM; all those configured to ignore it
exit with SIGKILL. This proves the observed forced exit, **not** a
SIGTERM → SIGKILL signal sequence, which the test does not trace.

Provider latency from the trigger, checks included: 1.849–3.321 ms in the init;
1.712–3.928 ms in the constructor; 2.600–10.564 ms in the resistant profile. These are individual
local observations, not a guaranteed time bound. All cleanups confirm
the exit of root, broker and provider; observer alive during the measurement, orderly
exit of the observer and Mach name absent after every case.

In **all** variants the broker reports `process-ready` while the provider is
still stopped. So the return from `AppExtensionProcess(configuration:)` does not imply
that `AppExtension.init` has finished or that the application channel is ready. The test
is not described as a host initializer still pending: the phase is established
in the provider's exact code, not inferred from the host state alone.

For the constructor, `otool -l`, `nm -nm`, `__init_offsets` and the indirect
symbol table are preserved. The initializer's offset corresponds to
`startup_before_entry`; LC_MAIN leads to the `_NSExtensionMain` stub, as in the
ordinary Xcode build. The guard and the C UUID are reused by Swift after the unblock.
The timer starts when it is armed, not at process creation.

## Preserved unqualified attempts

- AF_UNIX, `probe-860_n5b0`: bind EPERM in the container, before launching any
  provider. TCC attributes Codex as responsible; no permission widened to
  get around the denial. Transport abandoned for this fixture.
- `probe-or1q_x20`: compilation error from the use of the deprecated `mach_port_destroy`;
  replaced with an explicit release of the rights, no native test run.
- `probe-7na4sb1w`: build stopped because the codesign output level did not expose
  the required CDHash; correct reading with `-dvvv`, no native test run.
- `probe-xbuwn_k1`: negative rejected and authenticated observation succeeded, but
  release-control UNKNOWN. The provider exited with SIGTRAP inside ExtensionFoundation.
  The manual link lacked the `_NSExtensionMain` entry point and the
  `-application-extension` profile used by Xcode. Those flags were restored, along with
  the normal packaging without an embedded CLI Info.plist. The subsequent check passes.
  The crash report of the observed PID and the full cleanup are archived.

The review also found that the classifier accepted SIGTERM even
for the broker into which SIGKILL was injected. Corrected: it requires status 9 in that
case. The regression was observed to fail before and pass after the change. A similar
check for the resistant provider and for the diagnostic phase label.

## Evidence and checks

Archive: [evidence/2026-09-25-addon-startup-observation](evidence/2026-09-25-addon-startup-observation).

- `final-init`: `probe-4g99x6ye`, five PASS + negative.
- `final-constructor`: `probe-h_9kxqgb`, five PASS + negative.
- `final-resistant`: `probe-izxg04jl`, five PASS + negative.
- `unix-preflight`, `c-build-error`, `cdhash-build-error`, `wrong-extension-entry`:
  earlier attempts, without reinterpreting them as successes.
- Manifest, source snapshots, source/runner/binary hashes, commands, entitlements,
  kernel receipts, audit tokens, timestamps and logs preserved for every final build.
  Integrity verified before the later changes; the old results must be
  recomputed with the classifier of their own snapshot.
- 33 green Python tests: StartupObservation 8, BrokerRecovery 11, Recovery 4,
  Interruption 3, XPCLifetime 7. Evidence in `unit-tests.json`.
- Independent review of the sources, classifier and native results.
- The production gate remains exit 78 (`gate.json`). No production adapter enabled.

## Remaining frontier

The diagnostic transport allowed an independent test in phases previously
inaccessible to the normal handshake. It does not make a stall that precedes any
fixture code observable from outside, and it does not create a public
termination handle valid from the birth of the process. Moving a callback even earlier
would not, on its own, eliminate this gap. No new policy choice is
requested: the decision to keep the launcher blocked remains applied.

## App relaunch

Cascade closed and relaunched from the build already linked at `/Applications/Cascade.app`,
with new PID 63292 verified stable for three seconds. No change to the
app's code, so no new product build required. The actual path
and commands are in `restart.json`.
