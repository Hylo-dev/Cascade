# External extension: global recovery and stop through a broker

24 September 2026. macOS 27 beta, build 26A5425a, arm64, SDK 27.0.
Isolated experiments, following the approval of global recovery as a last
resort. **Launcher not admitted; gate unchanged.**

## Result

The composition app → XPC broker → external extension was observed: the exit
of the broker terminates the provider with a blocked callback while leaving the app responsive.
Normal exit and crash of the app terminate both. The direct app → extension test
also confirms a fresh start after the verified exit of the old chain.
These results concern processes already launched and authenticated.

| Fixture and scenario | Outcome | Provider exit observed from the trigger | Other observation |
| --- | --- | --- | --- |
| Direct app, normal exit | PASS | ~10.52 ms | New host/provider after both exits |
| Direct app, SIGKILL crash | PASS | ~9.78 ms | New host/provider after both exits |
| Broker, normal exit | PASS | ~6.25 ms | Root still alive and responsive |
| Broker's root, normal exit | PASS | ~11.31 ms | Broker terminated ~9.78 ms |
| Broker's root, SIGKILL crash | PASS | ~14.42 ms | Broker terminated ~11.25 ms |

These are individual observations, not guaranteed time bounds. The windows are eight
seconds long. In all cases the provider stayed alive for two seconds after invalidation
with the host still responsive. All measured exits and the cleanups are confirmed;
no PASS derives from the SIGALRM guard. The new chains in the direct test are
in turn authenticated, confirmed and terminated before their own guard.

## Consent and discovery

The user expressly authorized only the local test extension
"CascadeAddonProbeContainer". The action in the System panel was performed after
that consent. The AX reading of the toggle kept reporting off; it is not used
as proof of a change of state. After the action, the discovery test records:

- App: provider present in both the legacy and the modern discovery.
- Broker: provider present in the legacy one, modern one still empty with `unapproved=1`.
- The subsequent native test actually launches and authenticates the provider from the broker
  through the legacy API. The discrepancy with the modern discovery remains open.

The `.xpc` service is not an application that LaunchServices can open. The earlier
attempt to open it as an app was corrected; the test `.app` container and
Cascade are distinct entities. No general consent for other extensions was
requested or modified.

## Attribution and boundedness

Host, broker and provider are signed with the same development identity fixed
by the fixture, with hardened runtime; broker/provider have only app-sandbox. The
XPC requirements check identifier and leaf certificate. The
`BROKER_PROVIDER` profile admits the exact broker in place of the direct host.

The root authenticates broker, nonce and path; the broker authenticates the provider and
its response. The provider attests PID, UUID and path, correlated with the authenticated
connection. The kqueue registration with receipt happens between two responses of the
same incarnation. The last response precedes the held callback. The exit is
observed via NOTE_EXIT/NOTE_EXITSTATUS, not inferred from the XPC invalidation.

Separate native guards: provider 25 s, broker 35 s, broker's root 45 s. The direct
test uses root 35 s. SIGALRM is explicitly restored and unblocked;
the dedicated case confirms the -14 exit of a child with an inherited blocked SIGALRM.
The guard starts when the fixture's code runs, so it covers
neither creation nor an earlier stall. The cleanup keeps the
measurements separately; any forced termination concerns only the kept direct child,
never a process chosen by name or a PID discovered later.

## Preserved incomplete attempts

The first direct test ran into several registered copies of the same provider:
UNKNOWN, before launch. Only fixture copies with verified signature and identity
were removed from the registry, keeping the files. The expected path is then
verified in the handshake; ambiguous identities remain an error.

The first broker runner stopped before launching the chain because LaunchServices
returned -10814 while removing an old copy that was already unregistered. The final runner
records that outcome and proceeds to the strict discovery; no result of that
attempt is counted as lifetime evidence.

An independent review identified, in the first implementation of the guard,
the case of an inherited blocked SIGALRM. The correction and the dedicated test precede the final
direct tests. The review of the final broker found no P1/P2 in the fixture
or in the attribution of the results.

## What remains to be qualified

- Creation → startup/handshake, including host death with launch still pending.
- Independent observation of the exit of the specific incarnation in that phase.
- Reuse of the provider across clients, isolation of several simultaneous external addons and
  selective restart of the broker with the same app alive.
- Fully blocked broker: the earlier C tests concern blocked callbacks,
  not the suspension of the whole process nor this ExtensionFoundation composition.
- A distinct publisher, macOS 14 and the other supported systems, remote UI, state
  restoration and integration into the real runtime.

The [research on the public APIs](../../wayfinder/research/2026-09-24-extension-host-global-recovery.md)
does not yet find a sufficient contract for the pre-main guarantee. This is not proof
of impossibility on the platform. A marker in an initializer would explore a
phase after the first executed code and would not close the requirement.

The [approved policy](../specs/2026-09-10-addon-control-policy.md#emergency-global-recovery-decision-of-24-september-2026)
allows global recovery but neither orphans nor a relaunch with an unknown old chain.
There is no need to propose this decision again. The next technical prerequisite is a
verifiable public contract/API for lifetime and observation during startup;
an [updated question for Apple](../../wayfinder/research/2026-09-24-extension-lifetime-apple-question.md) had been prepared, never sent. The user then ruled out
this path: the draft is archived and work continues in the
[public documentation](../../wayfinder/research/2026-09-24-extension-startup-documentation.md),
without waiting for or requesting a private answer from Apple.

## Reproduction and evidence

- [Direct fixture](../../../Prototypes/AddonPlatform/Recovery/README.md).
- [Broker fixture](../../../Prototypes/AddonPlatform/BrokerRecovery/README.md).
- [Final direct results](evidence/2026-09-24-addon-global-recovery/final/results.json),
  [guard check](evidence/2026-09-24-addon-global-recovery/final/guard-check.json).
- [Ambiguous direct attempt](evidence/2026-09-24-addon-global-recovery/initial-ambiguous/results.json).
- [Discovery after consent](evidence/2026-09-24-addon-global-recovery/discovery-after-consent/stdout.jsonl).
- [Broker results](evidence/2026-09-24-addon-global-recovery/broker-external/broker-results.json).

Each group keeps a manifest with hashes, build log, copied sources and the runner of
its own run. Nine targeted Python tests verify the classifiers (four
direct, five broker); they are not proof of the operating system's behavior.
The typecheck of host and provider in the default Swift profile, without the flags
of the Recovery test, also passes after the helpers were moved into the shared file.
The gate still returns exit 78 with SHA-256
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.
The Cascade/CascadeKit product sources were not modified in this
work; no new completion percentage is inferred from the PASS results.
