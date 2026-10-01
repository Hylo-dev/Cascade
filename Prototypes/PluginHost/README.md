# PluginHost spikes

**Throwaway fixture for spikes S1 and S2 of the [plugin engine design](../../docs/superpowers/specs/2026-09-29-plugin-engine-design.md). Not built, linked or launched by Cascade.**

`Host/` stands in for Cascade, `Service/` for the bundled PluginHost XPC service, and `Shared/` holds their XPC protocol and the Apple Events helpers. Both sides are Swift and use `NSXPCConnection`, authenticated with code signing requirements on bundle identifier and team. The results are in [the verification record](../../docs/superpowers/verification/2026-10-01-plugin-host-spikes.md).

## Run

Requires Xcode-beta, the Apple Development identity of team 8KZQJ4JUGS and a logged-in desktop. Products go to `~/Library/Developer/Xcode/DerivedData/CascadePluginHostSpike/`, never into the repository.

```sh
python3 Prototypes/PluginHost/run_spike.py --build
python3 Prototypes/PluginHost/run_spike.py --s1 PRODUCTS
python3 Prototypes/PluginHost/run_spike.py --s2 PRODUCTS
python3 Prototypes/PluginHost/run_spike.py --custom PRODUCTS hello kill hello-wait 20
```

S1 runs unattended. S2 raises up to three system prompts (Automation of Finder twice, Bluetooth once) that the user answers; the grants stay under "PluginHost Spike A" and "PluginHost Spike B" in System Settings until removed there. The host is always launched through `open`, so TCC sees it as its own responsible process.

Host commands, run in order: `hello`, `hello-wait SECONDS`, `hang`, `kill`, `kill-raw`, `kill-stale`, `reconnect`, `foreign`, `exit`, `automation BUNDLE 0|1`, `host-automation BUNDLE 0|1`, `send BUNDLE`, `host-send BUNDLE`, `bluetooth 0|1`, `host-bluetooth`, `pause SECONDS`.
