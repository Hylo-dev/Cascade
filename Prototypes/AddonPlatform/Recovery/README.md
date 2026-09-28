# Global recovery of an external extension

Fixture separate from Cascade: signed app → sandboxed ExtensionFoundation provider
in an external `.app` container. The provider responds, then holds the callback.
Invalidation is observed with the host alive; only afterwards is the host's normal
exit or crash triggered. A new chain starts **only after** the old one's exits,
with a new confirmed process identity.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/Recovery -p 'test_*.py'
python3 Prototypes/AddonPlatform/Recovery/run_recovery.py --build-only
python3 Prototypes/AddonPlatform/Recovery/run_recovery.py --run /absolute/path/from/build
```

Requires macOS, Xcode and the fixture's specific development identity.
Builds and signatures are in a new DerivedData directory. The runner verifies the hashes,
registers the exit via kqueue between two authenticated responses, and distinguishes
measurement from cleanup. The SIGALRM guards start in the fixture's code: they are not a
pre-main solution. The dedicated check also verifies an inherited, blocked SIGALRM.

Registration concerns only the copies of the test container with fixed signature and
identity. The runner does not enable system permissions. The LaunchServices error
-10814 on already removed copies is retained as in the broker test; discovery
must still be unique and the path must authenticate. The delivered runs
retain their own sources and manifests from before this correction.

The optional `build(broker_provider=True)` profile is reserved for the
[BrokerRecovery](../BrokerRecovery/README.md) composition: the provider accepts the exact broker
in place of the direct host. It does not widen the signing requirement.

[Results and limits](../../../docs/superpowers/verification/2026-09-24-addon-global-recovery.md).
No product adapter or launcher admission.
