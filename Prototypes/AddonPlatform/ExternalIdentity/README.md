# External identity preflight

Disposable diagnostic for the next preinstruction experiment. It does not admit
the addon launcher or start any process suspended.

`TaskObserver.c` obtains a task-name port from a candidate PID, reads the kernel
audit token, and authenticates identifier, signing leaf, exact arm64 CDHash and
bundle path through Security. It registers EXIT/EXEC observation with a kqueue
receipt and repeats authentication through the retained port. No provider HELLO
supplies this identity. A later ordinary XPC HELLO confirms the same provider PID;
the name-port token is checked again. This remains a diagnostic composition with
the compatibility limits described by Apple DTS, not a new production contract.

The observer also checks whether a task control port is obtainable. This check
does not attach a debugger, send a signal, change a task or add entitlements.
The provider retains its ordinary sandbox-only profile and Hardened Runtime.

Build and run on the authorized host:

```sh
python3 Prototypes/AddonPlatform/ExternalIdentity/run_identity.py --build-only
python3 Prototypes/AddonPlatform/ExternalIdentity/run_identity.py --run PRODUCTS
```

`--debug-preflight PRODUCTS` additionally tries to configure an unused environment
variable for the next invocation of the exact inactive provider job. It is a
bounded mutation attempt, not a read-only permission query. It does not request
suspension, change the launched program or invoke kickstart. The subsequent
invocation still goes through the normal ExtensionFoundation broker. On the
tested system launchctl rejects the operation because it requires root.

The runner copies and hashes build sources, runners and binaries; all future
inputs must still match the manifest. Archived runs use their own source/runner
snapshots. `launchctl print` is diagnostic-only and must not become a production
discovery or authentication API. Root/broker/provider exit evidence is recorded
separately; errors do not imply complete cleanup. PID-based signal cleanup is
restricted to directly retained Popen children.

Results, limitations and proposed VM test environment:
[verification](../../../docs/superpowers/verification/2026-09-25-addon-external-identity.md).
