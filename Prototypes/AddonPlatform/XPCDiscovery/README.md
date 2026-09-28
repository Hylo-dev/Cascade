# Discovery from the XPC broker: diagnostic fixture

Compares the lookup of the external P0 addon in the app and in the sandboxed broker.
It does not construct AppExtensionProcess, does not load addons and does not qualify a launcher.
It samples the legacy API and the modern Monitor for two seconds.

Requires Xcode-beta, the certificate pinned in the script and a registered P0 container.
It does not change enablement. Before interpreting a negative comparison, the app must
find `hylo.Cascade.AddonProbeContainer.Provider`.

```sh
python3 Prototypes/AddonPlatform/XPCDiscovery/run_discovery.py --build-only
python3 Prototypes/AddonPlatform/XPCDiscovery/run_discovery.py --run /path/printed
```

Exit 0 indicates only an authenticated response. Read legacy/modern/disabled/unapproved
for both callers. The runner verifies hashes and saves logs/manifests in a new
DerivedData folder on every build. Do not repeat a command in the same folder
if you want to preserve the logs.

`--run-browser` creates the Apple browser from the broker for manual inspection, with host exit
60 s after the response and a 90 s guard. It is not qualified consent. Requires an
unlocked desktop: first run not inspectable, no permission changes.

[Results](../../../docs/superpowers/verification/2026-09-24-addon-xpc-frontier.md):
the app finds the provider, the broker finds no identity and one unapproved element.
