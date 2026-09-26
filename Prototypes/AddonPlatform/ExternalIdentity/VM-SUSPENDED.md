# Disposable macOS guest: suspended second launch

`run_vm_suspended.py` is a diagnostic runner, not a launcher implementation. It
uses the existing signed fixture and `TaskObserver` without recompiling or
changing entitlements. It has not yet been exercised against a native guest.

The external VM manager must first demonstrate that it can stop this disposable
VM without guest cooperation and retain logs outside the VM. Only then create a
qualification file, copied into the guest, with this schema:

```json
{
  "managerCleanupQualified": true,
  "vmIdentifier": "the-exact-qualified-vm-identifier",
  "stopEvidenceSHA256": "the-64-lowercase-hex-sha256-of-the-host-stop-evidence"
}
```

The marker is an explicit operator attestation backed by host evidence, not
self-qualification by the guest. The runner also requires
`CASCADE_DISPOSABLE_VM=1`, a `VirtualMacN,N` hardware model, and a nonroot UID.
Never fabricate the marker to bypass an untested host stop operation.

Import the archived signed fixture into a fresh local directory in the guest,
preserving its original product-relative layout. Include its original
`build.json` and entire original `Sources` tree. `--products` is the directory
containing `TaskObserver` and `BrokerRecovery.app`. Absolute build paths are
rebased in memory only; the original manifest stays unchanged. All recorded
source and executable hashes are checked, followed by strict code-signature
validation. No signing key or build toolchain is needed in the guest. Python
3.9 or later is required.

The fixture extension must be enabled for the guest user. Registration/opening
of its container is performed before root/broker launch; an ordinary first
HELLO must complete before suspension is armed. If that prerequisite fails,
fix the guest setup and use a fresh output directory. Do not extend fixture
alarm guards or infer success from a process-list entry.

Run one mode per invocation, capturing stdout on the host as JSONL:

```sh
CASCADE_DISPOSABLE_VM=1 python3 run_vm_suspended.py \
  --manifest /Users/admin/probe/build.json \
  --products /Users/admin/probe \
  --cleanup-qualification /Users/admin/cleanup-qualified.json \
  --vm-identifier the-exact-qualified-vm-identifier \
  --output /Users/admin/results/release-control \
  --mode release-control
```

Start with `release-control`; only after that passes, run `broker-stop`,
`broker-crash`, `root-quit`, and `root-crash`, each in a new output directory.
The fixture runs as the normal user. Only `sudo -n launchctl debug` for the exact
inactive fixture job uses administrative privilege; the release control also
uses `sudo -n launchctl kill SIGCONT` on that same job. No discovered PID is
signalled. `launchctl print` is deliberately used only as fail-closed diagnostic
setup and is not a stable discovery API.

The measured sequence is: authenticated ordinary HELLO → external kernel token
and signature binding → observed cooperative provider exit → release references
→ prearm the same inactive provider job → second ordinary EF request → externally
bind the suspended provider image → register kernel exit → recheck full token
and positive suspend count → inject the selected fault. The broker's asynchronous
command dispatcher remains responsive while second HELLO waits. A candidate PID
from `ps` never establishes identity by itself. `TaskObserver` rejects xpcproxy
because the original provider signature, CDHash and exact bundle path must match.

Every mode emits incremental events, records the guest OS version/build and kernel,
and writes `result.json`. Exit times are observer dequeue times, not kernel death
timestamps; confirmation and the later fault are not one atomic operation. Its classification
is frozen before later cleanup; the runner never promotes failure because a
subsequent quit or VM stop worked. Provider/root/broker exits must be observed
before guards, and the observer must remain alive. `release-control` additionally
requires the same full audit token and ordinary HELLO from the resumed instance.
Unknown identity, missing suspend count, early guard, missing exit, wrong crash
status, or incomplete cleanup cannot pass. A nonzero result requests external
whole-VM stop; the guest does not attempt PID-based emergency cleanup. Retain host
JSONL and the guest result before stopping the VM.

A PASS is limited to this diagnostic **second EF launch**, original provider
image, specific guest build and injected event. It does not cover first launch,
the preceding xpcproxy interval, every macOS version, or production launcher
admission. The production managed-death gate remains unchanged.

Pure classifier and environment-guard checks, safe on the host:

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/ExternalIdentity -p test_vm_suspended.py
```

## Optional stackshot after the baseline

The default remains unchanged. Only a later `release-control` invocation may add
`--stackshot`; other modes reject the flag before starting any subprocess. Do not
replace an already packaged baseline runner or its immutable fixture. Package a
separate copy of this runner for the optional diagnostic.

Before launching the fixture, the runner verifies the stock
`/usr/sbin/spindump` Apple signature and its guest manual's required options.
When available, it invokes exactly:

```text
sudo -n /usr/sbin/spindump PID 1 100 -onlyTarget -timeline -timelimit 8 -o OUTPUT/provider.spindump.txt
```

The external command timeout is 10 seconds. Sampling starts only if at least
that timeout plus the existing 9-second observation budget and a 2-second margin
remain before every live guard. The retained observer confirms the full audit
token, authenticated provider image, and identical positive suspend count
immediately before and after. Its confirm also rejects queued EXEC or EXIT.
Any HELLO, changed state, insufficient budget, or command timeout fails the case
and requires host VM stop. Neither ordinary cleanup nor a saved report repairs it.

An unavailable stock tool, rejected access, nonzero command status, or missing
readable report is recorded as inconclusive. Release control may continue only
if the identity, suspension and remaining guard checks still pass. A retained
report has path, byte count and SHA-256 recorded; it remains unreviewed evidence.
The runner does not parse frames into a first-instruction or PC claim, and always
records `phaseQualified: false` for this optional diagnostic.

The stock spindump manual documents suspended thread reporting. That does not
by itself establish the tool's behavior on this particular guest build. Before/
after equality also cannot rule out a transient observer effect between checks.
This is a separate diagnostic qualification, not an uninstrumented lifetime
measurement. No debugger attach, `sample`, entitlement change or provider rebuild
is added.
