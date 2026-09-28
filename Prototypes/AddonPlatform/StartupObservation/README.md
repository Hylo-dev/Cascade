# Observing a provider during startup

Isolated fixture: root process → sandboxed XPC broker → external extension.
A separate observer authenticates the provider before the application channel is
ready, then the runner registers the exit with kqueue and requests a new challenge.
Only after the confirmation is the stop/crash injected. No production launcher.

Two variants of the same test:

- `--build-only`: block inside `AppExtension.init`.
- `--build-premain`: block in a C constructor of the main image, before
  the extension's entry point. The guard and the UUID are reused by the Swift code.
  It does not cover the interval between process creation and that constructor.
- `--build-premain-resistant`: same phase, with SIGTERM ignored; the classifier
  requires the SIGKILL exit, distinct from the SIGALRM guard.

The runner produces a signed bundle and an observer in a unique DerivedData
directory; then `python3 run_startup.py --run PRODUCTS` runs the negative control,
the unblock to the normal channel and four faults: broker stop/crash, root quit/crash.
Stop at the first non-PASS result or incomplete cleanup. Measurement deadline 8 seconds;
the independent guards expire later and cannot produce a PASS.

The diagnostic transport uses Mach messages with the kernel's audit trailer, a signing
requirement of leaf + identifier + CDHash of the exact build, the bundle path and a fresh
nonce after EV_RECEIPT. The observer registers a unique name through the public
but deprecated `bootstrap_register` API; only the test provider adds the exact
lookup for that name. App Sandbox stays active. It is not the product profile and it is not
a decision on the future SDK transport. Teardown verifies that the name is no longer
resolvable, without deleting other parties' services.

The initial AF_UNIX attempt in the container did not get past the bind: EPERM before
the provider was launched. No TCC grant was modified to work around it.

Results, builds, entitlements, hashes, failed attempts and limits are retained
in `docs/superpowers/verification/2026-09-25-addon-startup-observation.md`.
