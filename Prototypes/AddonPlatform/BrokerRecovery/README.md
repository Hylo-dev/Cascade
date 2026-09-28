# XPC broker with an external provider

Fixture app → sandboxed XPC broker embedded in the app → sandboxed provider in an
external container. It reuses the protocol, guard and provider build of the
[Recovery](../Recovery/README.md) test. Discovery uses the API available since macOS 14;
the delivered native test was run exclusively on macOS 27 beta.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/BrokerRecovery -p 'test_*.py'
python3 Prototypes/AddonPlatform/BrokerRecovery/run_broker_recovery.py --build-only
python3 Prototypes/AddonPlatform/BrokerRecovery/run_broker_recovery.py --run /absolute/path/from/build
```

Three scenarios: ordinary broker exit leaving the app responsive; normal app exit;
app crash. The provider's callback stays blocked after a second authenticated
response. Before the stop, invalidating the provider's references does not terminate
it within the two observed seconds. Exact signature, nonce, per-incarnation UUID,
bundle path and kqueue make it possible to attribute the observations. Exits caused by
a timing guard do not count as PASS, and cleanup does not change the verdict.

The runner stops at UNKNOWN or incomplete cleanup. The LaunchServices error -10814
during removal of old copies is retained: the subsequent discovery must still find a
single identity, and the expected path must authenticate.
No automatic change of system permissions.

It does not cover the phase before authentication, a completely blocked broker,
two different concurrent addons, or a different publisher.
A fresh start without quitting the app is verified by the additional runner below.
The product gate stays disabled.

[Report and immutable evidence](../../../docs/superpowers/verification/2026-09-24-addon-global-recovery.md).

## Ordinary replacement, broker restart and two hosts

```sh
python3 Prototypes/AddonPlatform/BrokerRecovery/run_sessions.py --build-only
python3 Prototypes/AddonPlatform/BrokerRecovery/run_sessions.py --run /absolute/path/from/build
```

Three additional cases, all PASS on 25 September:

- `restart`: blocked provider, broker and provider exit, re-creation of the connection
  and new incarnations with the same app alive; the exit of the new ones is observed too.
- `two-hosts`: two concurrent apps of the same addon get distinct processes;
  stopping the first chain leaves the second authenticated and responsive.
- `provider-cycle`: cooperative provider exit, release of the references and a new
  provider with the same broker still alive; second exit observed before cleanup.

The first handshake after re-creation has a 15-second diagnostic window:
the broker restart took about 10 seconds, the new provider alone about
66 ms in the final run. These are not guarantees or benchmarks. A single pending
request, no retry loop; stop windows and guards unchanged. The runner authorizes the
`restart` and `release` commands only after the respective kernel exits;
the cooperative-exit command attests only that it was sent, not the exit.

[Report, incomplete attempts and final results](../../../docs/superpowers/verification/2026-09-25-addon-broker-sessions.md).
