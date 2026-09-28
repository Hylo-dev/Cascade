# ExtensionFoundation notification and kernel-observed exit

Isolated check of `AppExtensionProcess.Configuration.onInterruption`, configured
before the initializer and correlated with a local launch nonce. It reuses the host,
provider, signatures, guards and kqueue observation of the [Recovery](../Recovery/README.md) fixture.
It does not change Cascade's launcher.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/Interruption -p 'test_*.py'
python3 Prototypes/AddonPlatform/Interruption/run_interruption.py --build-only
python3 Prototypes/AddonPlatform/Interruption/run_interruption.py --run /absolute/build/path
```

Five cases with the host alive: voluntary provider exit, provider crash,
invalidation with a cooperative provider, release without explicit invalidation
of the AppExtensionProcess, invalidation with the provider's callback blocked.
In the two release cases the XPC channels and the listener are still invalidated.

Kernel registration happens between two authenticated responses from the same
incarnation. The two signals (callback and NOTE_EXIT) remain distinct observations:
no notification on its own is proof of exit. The window lasts six seconds;
the cutoff precedes a final kernel drain and the IPC snapshot. A kernel event
observed in the final drain after the cutoff yields UNKNOWN; later notifications remain separate.
Cleanup is not part of the window's result.

The callback retains only a nonce, never the process or the channels. The host's strong
properties and weak references to the channel, bootstrap, listener and delegate
make it possible to verify the visible release. `AppExtensionProcess` is a struct:
there is no claim to observe all of the framework's internal references.

Independent guards: provider 25 s, host 35 s. The runner stops at UNKNOWN or
incomplete cleanup. Its exit 0 indicates complete collection, **not** five successful
stops or launcher admission. No pre-main proof.

[Report](../../../docs/superpowers/verification/2026-09-24-addon-interruption.md).
