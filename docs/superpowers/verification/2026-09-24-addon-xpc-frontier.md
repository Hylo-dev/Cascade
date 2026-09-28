# XPC: blocked commands and external addons

**Later update:** the user accepted the global relaunch as a last resort.
The [recorded decision](../specs/2026-09-10-addon-control-policy.md#emergency-global-recovery-decision-of-24-september-2026)
supersedes the references to a pending choice in the historical report below; the evidence
and its limits remain unchanged.

24 September 2026. **Launcher still disabled.** Continuation authorized with
isolated fixtures; no change to the product or the policy. The choice on the global
relaunch as a last resort is pending and does not reopen the already rejected exception for orphans.

## Command blocking

`hold-all` in the XPCBroker fixture atomically sets the block of every subsequent
A command callback, also on the second channel, and holds the initial callback.
The worker confirms its own block; the authenticated response goes through an
independent queue. For the stop, the second channel is authenticated on the same incarnation
before the block. Listeners, responses and signals remain operational: **it is not a
suspension of the whole process**, no SIGSTOP is sent, the guards are active.

macOS 27 beta 26A5425a, SDK 27.0, arm64, compiled target 14.0. Root: Hardened Runtime;
broker/worker: Hardened Runtime + App Sandbox, signatures pinned as in the previous tests.
Final build: `CascadeXPCBrokerProbe/nested-boa0k31m` in DerivedData.

| Scenario, 2 s window | Outcome | Evidence |
| --- | --- | --- |
| Stop A on the second channel, root and B alive | FAIL | No A exit; root and B responsive |
| Normal root exit | PASS | Four services SIGKILL, events within 1.95 ms |
| Root self-SIGKILL | PASS | Four services SIGKILL, events within 2.03 ms |

These are receipt times of the kernel events from the trigger, not guaranteed latencies.
The classifier admits status 9 or 15 for the services; the results are all 9.
Required root statuses 0/-9. The guard and accidental crashes do not produce PASS.

During the **cleanup of the FAIL**, root exits normally: B terminates immediately, A about
**5 seconds after the root**, before the guard. Observed in both cycles.
The case has a second channel and a pending stop; the cause of the difference
from host-normal was not isolated. The fast PASS is not extended to every sequence, nor
is the cleanup used to promote the FAIL. All tracked participants are shown to have
exited in the end. No signal to PIDs or groups identified by scanning.

Final runner **exit 1**, consistent with a valid FAIL. Preserved the
[initial cycle](evidence/2026-09-24-xpc-frontier/frozen-initial/results.json) and the
[final](evidence/2026-09-24-xpc-frontier/frozen-final/results.json) one, logs, manifests and
the corresponding sources. The second adds host-normal after the delay in the cleanup.

## Discovery of the external addon

New fixture [XPCDiscovery](../../../Prototypes/AddonPlatform/XPCDiscovery/README.md):
an app with the P0 ID/extension point and a sandboxed broker with a distinct ID. Recompiled and opened
the empty container of the P0 fixture to register its metadata. **No provider
launched**, no construction of AppExtensionProcess. 2 s sampling for both
APIs. Signature checked on both connections; response with nonce, bundle ID
and PID verified against the Foundation connection. No grant or user data.

| Caller | Legacy | Modern monitor |
| --- | --- | --- |
| App | Expected provider found | Same provider, disabled 0, unapproved 0 |
| Broker | Empty | Empty, disabled 0, unapproved 1 |

[Authenticated result](evidence/2026-09-24-xpc-frontier/discovery-final/stdout.jsonl).
**The extension point and the monitor do not reject the XPC target** in the test. `unapproved=1` is a
count, not the authenticated identity of that element: it suggests an approval
obstacle in the broker context, without isolating its cause. It does not demonstrate impossibility,
a launch right or lifetime ownership. Exit 0 of the runner means an authenticated
response, not qualification; the positive control of the app is verified here.

[First attempt](evidence/2026-09-24-xpc-frontier/discovery-initial/) inconclusive
because of a fixture defect: a signature setter on NSXPCListener.service, forbidden by the
Foundation header. Error 4097 and SIGSEGV in the setter, reduced log/crash preserved. Fix:
a requirement on the received NSXPCConnection before export/resume, without removing
the authentication. The preliminary check had not identified this error.

The [browser variant](evidence/2026-09-24-xpc-frontier/discovery-browser/) builds
EXAppExtensionBrowserViewController from the broker, keeps it 60 s after the response,
autonomous guard 90 s. Same counts. **Visual check blocked by the Mac on the
lock screen**: no window captured, no toggle or consent changed.
Creating the view without error does not demonstrate visibility or support of the UI path.

## Research and pending choice

[Audit token](../../wayfinder/research/2026-09-24-audit-token-termination.md): the kernel
verifies PID/version, but libproc does not satisfy the requirement of a supported public API
and presence in the SDK does not prove macOS 14.0. No private API introduced.
[DTS source](https://developer.apple.com/forums/thread/837541).

[Broker/ExtensionFoundation composition](../../wayfinder/research/2026-09-24-extension-broker-composition.md):
no public parameter identified to make the GUI approve an extension on
behalf of the broker. Browser and System Settings still require verification on an unlocked
desktop; internal databases are not modified. The [DTS answer on nested hosting](https://developer.apple.com/forums/thread/846017)
concerns an extension that hosts other extensions, not this precise XPC broker.

The product question put to the user is whether to allow **the relaunch of all of
Cascade as a last resort**, temporarily interrupting the other addons as well,
or to always require selective recovery. The second channel resolves a localized
stall, not the case just measured. The first path first needs proof
of the exit of the whole chain, timings and restoration; launching a second app is not enough.
The second needs another public primitive or a demonstrated architecture.

Both preserve: no orphaned managed process, sandbox/signature, absence of addon code
in the GUI and the macOS minimum. A yes to the relaunch **does not by itself enable the launcher**.
Remaining: consent and authenticated external launch, lifetime ownership, pre-main,
exact incarnation, another publisher, macOS 14/15/26, remote SwiftUI. A question to Apple
is prepared in the research, **not sent**.

## Checks

- Signed builds succeeded: C XPC, Swift discovery and the P0 container.
- 7 XPCLifetime + 11 XPCBroker tests passed; new expectations observed failing before
  the implementation. No new product suite claimed.
- Gate run: exit 78, without a C0d launch; SHA-256 unchanged
  `687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.
- Only prototypes/evidence changed: no new Cascade build needed.
- Final ordinary relaunch and app path recorded in
  [restart.json](evidence/2026-09-24-xpc-frontier/restart.json).
