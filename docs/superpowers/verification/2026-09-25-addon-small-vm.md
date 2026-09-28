# Small macOS lab for the suspended test

Preparation started on 25 September 2026, authorized by the user after freeing
space. **On 26 September the small VM is bootable, SIP has been restored
and the complete stop from the host is qualified. The suspended test remains blocked
before the first HELLO: the broker does not obtain the extension's identity on this guest.**
No suspension was armed and the production gate remains unchanged (exit 78).

The observed guest is macOS **14.3, build 23D56**, not version 14.1 indicated by the
chosen tag. The cause of the tag discrepancy is not established; the conclusions
refer to the system actually measured. At the native checkpoint: 2 CPUs, 4 GiB of RAM and allocated disk
17,855,008,768 bytes (16.63 GiB). **Subsequently, at the user's explicit
request, the VM was deleted and the VM path suspended.** Also removed:
portable Tart, cache/state and SSH credentials created for the guest; evidence preserved
in the repository. About 18 GB freed, with 21,872,640,000 bytes free at the check.

## Chosen configuration

- A single vanilla Sonoma guest, selected by the 14.1 tag but observed as 14.3,
  without Xcode, 2 CPUs and 4 GiB of RAM.
- Image pinned to
  `ghcr.io/cirruslabs/macos-sonoma-vanilla@sha256:a6dc5a325aae43a90244953af0a85091fbe93e8f58583138c5ac96dd707fd700`.
  Compressed download 14.76 GiB; the 50 GB virtual disk is sparse. The space
  actually occupied must be measured, not inferred from the virtual capacity.
- Portable Tart 2.38.0 verified with strict codesign and Gatekeeper, in
  `/private/tmp/cascade-addon-vm`; cache and clone confined to the same directory.
  No installation of Tart in Applications, Homebrew or toolchain in the guest.
- Free-space check during download and boot. The first limit of
  4.5 GiB interrupted the transfer at 99%; the next attempt reserves
  3 GiB during the download and initially 3.5 GiB for the boot. After the first
  stop in Recovery for lack of space, the boot also uses a 3 GiB reservation.
  No deletion of personal data; the controller keeps the partial data.
- Standard NAT network; after the first SSH login, removal of the default routes
  in the guest only and IPv4/IPv6 check. It is not a host-only network.
- Same signed fixture already archived in the external test: no change
  to the provider's entitlements and no signing key transferred.

The choice of image, the provenance and the retry behavior are
documented in the [research](../../wayfinder/research/2026-09-25-small-macos-vm.md).

## Preparation carried out

The extracted payload measures about 32 MB and contains the fixture, observer, runner
and a minimal Python runtime already available on the host. The transfer archive
measures 10,743,365 bytes, SHA256
`4da64e8ea598e196ab32ce727f1f128713a5ca5b1d0f9211f9c4f73aae9d2333`.
The hashes of the fixture's sources and binaries match the original
manifest; the signatures of the extracted bundles were verified.

The [runner](../../../Prototypes/AddonPlatform/ExternalIdentity/run_vm_suspended.py)
refuses to run outside an explicitly declared VirtualMac guest,
requires the attestation of the already proven external stop, authenticates the suspended
process and freezes the classification before cleanup. Eight automated checks
pass; this result concerns the runner, not native macOS behavior.
The [procedure](../../../Prototypes/AddonPlatform/ExternalIdentity/VM-SUSPENDED.md)
specifies checks and limits.

The later runner adds an optional `--stackshot` diagnostic, allowed
only after the baseline check and only in `release-control` mode. The twelve
tests of the updated runner pass. The baseline payload remains the original one:
the optional diagnostic was neither included in the archive nor run. A spindump
report, by itself, does not demonstrate the first-instruction phase.

The real refusal on the host was also verified: even with the diagnostic variable
set, the runner terminates with exit 78 before creating the results directory
or starting a fixture, because the hardware model is not VirtualMac.

## Measured space limit

The initial transfer reached 99%, then the controller terminated its
own Tart process with SIGTERM at the configured threshold: 4,813,242,368 bytes
free, against a reservation of 4,831,838,208 bytes. It removed only its own
incomplete `state` directory, bringing free space back to 22,428,499,968 bytes.
The VM had been neither created nor started. It is not an ExtensionFoundation failure.

The automatic deletion made it necessary to repeat the download. In the second
controller this policy is corrected: even at the threshold or on timeout it keeps the
partial state. The new attempt uses the same pinned image, six transfers,
a 3 GiB reservation and a four-hour limit. The margin makes it plausible to complete
the transfer, but does not constitute a verification of the boot or of the space
needed during execution.

The six-stream attempt exhausts the retries of some segments and is stopped
with state preserved. The four-stream resumption finishes with exit 0 in
5,876.598 seconds. The local image is a regular file independent of the cache;
after removal of the OCI reference a single VM remains, stopped. Configuration
confirmed: 2 CPUs, memory 4,294,967,296 bytes, display 1024×768 pixels.

On 26 September the offline compaction of all-zero 64 KiB blocks
reduces the allocation from 17,812,783,104 to 17,584,783,360 bytes. Logical size
unchanged at 50,000,000,000 bytes; full SHA256 identical before and after:
`0c0d46984b170fe9f40bbcfc1ef3a490a878fbd95d8fdd3d6b051c677d085721`.
Also removed were only temporary copies of the payload and caches/intermediates
of the build run for this work. The built app and the immutable evidence archive
are preserved. The subsequent 4 KiB pass recovers another 77,402,112 bytes, bringing
the allocation to 17,507,381,248 bytes with the same full SHA256. The changes
in the host's free space are larger: they are not all attributed to the
compaction. After boots, import and logs, the disk reaches 17,855,008,768 bytes.

## Native tests of 26 September

The first boot answers over SSH as `VirtualMac2,1`, lab account
`admin`, SIP disabled and authenticated root enabled. No fixtures are started
in that profile. From the Recovery of the guest only,
`csrutil enable` is run; two subsequent normal boots confirm SIP and authenticated root
enabled. No host protection is changed.

The external stop is requested from the Tart process kept by the controller:
SIGINT, message `Stopping VM...`, exit 0 without SIGKILL fallback, state `stopped`.
The next boot of the same configuration changes UUID from
`FBA4BFDB-27B7-497E-86CA-315E8104ECE1` to
`70146061-7758-48BA-AB56-0CED74AE20F9`. The
[cleanup evidence](evidence/2026-09-25-addon-small-vm/cleanup-evidence.json)
precedes the creation of the marker required by the runner. This qualifies the
observed lab containment, not the death of addon processes or every
possible hung guest.

The default routes are removed inside the guest. The scoped IPv6 routes
require `-ifscope`: the first incomplete attempts are preserved; the checks
before the fixtures confirm the absence of both IPv4 and IPv6 defaults. The host
share remains read-only. The original 10.7 MB archive passes the SHA256
comparison in the guest; portable Python works without a toolchain.

The fixture's public browser enables `CascadeProbeProvider`. After the
registration of `BrokerRecovery.app`, System Settings → Extensions
→ BrokerRecovery also shows the same extension already selected. No
consent databases, private APIs or entitlement changes were used.

| Check | Observed outcome |
| --- | --- |
| Original baseline | FAIL before starting children: requirement with ARM CDHash implicitly verified on all architectures |
| ARM signing matrix | Complete original requirement PASS with `--arch arm64`; wrong pin and Intel slice rejected; no change to the fixture |
| Baseline with ARM selection | Signature/input PASS, root and broker authenticated; first HELLO times out after 10 s, before arming `launchctl debug` |
| Ordinary diagnosis | Five `broker-info` responses during HELLO show `startupPhase=idle`; root terminates with the `quit` command |
| Broker app registration | Same block after `lsregister -f` of the exact app |
| Launch through Launch Services | Same block with `open -W -n`, FIFO and the real root PID obtained from `ping` |
| Direct check from the GUI app | Discovery finds the provider, which reaches its own code; the connection is correctly rejected by the broker-only requirement (`-67050`) |

The preflight fix selects exclusively the ARM slice already pinned in the
manifest; the integrity check of all slices remains. It is applied to the runner
in the repository. A separate copy of the baseline with **only this fix** is
transferred to the guest, SHA256
`0f6fb4c590bb2647b1ee961917530d34bd168be7d1e64d0ba47e7ef3b1385522`.
Original archive, manifest, requirement, binaries, deadline and classifier are
unchanged. The stackshot diagnostic of the later runner is not run.

The broker's discovery logs report `-10814`, inability to resolve the
extension's record for its audit token, and queries with a null extension point.
The result remains unchanged after registration of the container and LS application
launch. This narrows the problem to the broker context on this image/OS;
**it does not prove general impossibility on every macOS 14**. The GUI check is neither a
successful HELLO nor a new provider defect: the original fixture admits
only `hylo.Cascade.AddonProbe.DiscoveryBroker` as a peer and rejects the GUI.

All native sequences end with the verified complete stop of the guest.
No process was suspended, no fault case was run; a successful cleanup
does not change the previous FAIL classification.

## Frontier still open

Obtaining the first authenticated HELLO from the broker in a representative guest remains
a prerequisite for the resume check and the four root/broker death cases.
The app's macOS 14 minimum is not implicitly raised and the guarantees on
managed processes are not relaxed. The declared availability of an API in the deployment
target does not qualify this composition at run time.

The [archived evidence](evidence/2026-09-25-addon-small-vm/integrity.json) includes
manifest, controller, hashes, logs and results, without operating system images,
private SSH keys or toolchains. The final gate returns exit 78 and keeps SHA256
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

A possible PASS concerns the second EF request and the authenticated provider
image. It does not automatically imply coverage of the first launch or of
the preceding interval with xpcproxy, nor admission of the launcher in production.

The contract of `POSIX_SPAWN_START_SUSPENDED` places the suspension before
user-space execution, dyld included; the manual indicates SIGCONT for resumption.
The help of `launchctl debug --start-suspended` does not specify as precisely
the exec step involved in the EF chain. Therefore signature, token,
`suspendCount > 0` and the subsequent HELLO of the same instance are direct
observations, but not a reading of the program counter. The “before the first
instruction” phase will not be declared proven by these data alone.
[Apple manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_spawnattr_getflags.3.html),
[XNU implementation of the macOS 14 family](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exec.c#L1862-L1873).


## Final app verification and review

The independent review finds no P1/P2 in the report and in the new section
of issue 22; the first 139 files of the manifest are compared with the originals.
After the ARM fix, 12 pure tests pass (transcript attestation, not a
new stdout log). The static matrix keeps the Intel and wrong-pin negatives.

The official Cascade build run during preparation succeeded and the
link `/Applications/Cascade.app` points to `CascadeDevelopment/Build/Products/Debug`.
The subsequent change modifies only the diagnostic runner and documentation.
In the final relaunch Cascade goes from PID 39220 to the new PID documented in
[cascade-restart-final.json](evidence/2026-09-25-addon-small-vm/cascade-restart-final.json),
stable after three seconds and with an executable matching the Applications link.


## Closing the lab at the user's request

The user asks to stop the VM path, free the space on the current machine
and re-examine the options without a VM. `tart delete cascade-addon-small` finishes
with exit 0 after the stopped check; the subsequent list is empty and no
`disk.img` remains in the state. Also removed: the portable runtime, state/cache,
the transfer archive and only the SSH credentials generated for this lab.
The test results and the original signed fixture already archived are
preserved. No new images are downloaded and no architecture/minimum-OS decisions
are changed. [VM removal](evidence/2026-09-25-addon-small-vm/vm-removal.json),
[residue removal](evidence/2026-09-25-addon-small-vm/runtime-removal.json).

Cascade is quit and reopened again after the removal: executable of the
current build verified and new PID stable after three seconds. The record
[cascade-restart-after-removal.json](evidence/2026-09-25-addon-small-vm/cascade-restart-after-removal.json)
also confirms the absence of the disk and of the VM runtime.

The next candidate test without a VM is a diagnostic recovery on the exact job of
an ordinary authenticated provider, with the broker still alive and the time guard
active. It has not yet been run. `launchctl kill` identifies a service, not a
capability of its specific incarnation; a possible PASS does not prove
recovery after root/broker death or the behavior before the first instruction.
SIGSTOP/SIGCONT remains a separate experiment: stopping the process can prevent
the time guard from intervening and is not equivalent to START_SUSPENDED.
