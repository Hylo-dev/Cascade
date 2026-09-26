# Small macOS VM for the addon lifetime probe

Research date: 2026-09-25; final laboratory checkpoint updated 2026-09-26 (Europe/Rome). **The user has paused the VM approach and requested its space back. The stopped VM, dedicated Tart runtime/state, copied payload, and guest SSH credentials have been removed. No replacement VM or OS download is underway.** Further work is to proceed without a VM while the approach is reconsidered.

The completed experiment ran macOS 14.3 (23D56), despite selection through the image tagged 14.1. SIP was restored and verified over two normal boots, and external VM stop was qualified for the measured run. Broker discovery still failed before the ordinary HELLO. No suspended-provider or fault case was armed, and the product gate remained blocked. All preparation and recovery procedures below are historical records, not instructions to recreate the removed VM.

## Current state — VM removed at the user's request

`/private/tmp/cascade-addon-vm/vm-removal.json` records the VM as stopped before deletion, successful deletion (exit 0), no remaining VMs, and no remaining disk images. Its raw disk had 17,855,008,768 allocated bytes. Host free space increased from 3,907,584,000 to 21,790,720,000 bytes during this step.

`/private/tmp/cascade-addon-vm/runtime-removal.json` records removal of the dedicated `tart.app`, `state`, copied `share/payload.tar.gz`, guest SSH private/public keys, askpass helper, and known-hosts file. Free space at the end of cleanup was **21,872,640,000 bytes**, approximately **18 GB more** than before VM deletion. Small evidence logs were retained; neither the runtime nor the disk is needed to read this report.

The later `cascade-restart-after-removal.json` confirms Cascade restarted and remained present after three seconds, with the VM disk and runtime absent. Its host-free-space measurement was **20,563,918,848 bytes**. Host availability changes independently; the cleanup checkpoint and subsequent measurement must not be presented as the same instant or as exact accounting of only VM blocks.

## Historical image selection

The selected registry reference was tagged **Sonoma vanilla 14.1**, pinned to `ghcr.io/cirruslabs/macos-sonoma-vanilla@sha256:a6dc5a325aae43a90244953af0a85091fbe93e8f58583138c5ac96dd707fd700`. The final four-stream clone completed with exit 0 under the free-space watchdog. The historical 14.1 template references release build 23B74, but the booted guest actually reports **14.3 / 23D56**. The cause of this provenance discrepancy is not established; the runtime result supersedes the tag as the identity of the recorded tests. The initial selection avoided the slightly smaller `14` digest because it also carries `14-RC`. Cirrus distinguishes vanilla, base, and Xcode images in its [image templates](https://github.com/cirruslabs/macos-image-templates). Transfer only the existing signed fixture; no guest Xcode installation is needed.

The registry does **not** provide actual allocated size. The completed download and subsequent 64 KiB compaction now provide measured allocation, recorded below; they do not establish that boot will fit within its separate reserve. The later controller preserves partial state when its 3 GiB download guard stops the retained Tart child. The initial 3.5 GiB boot floor was later changed to a guarded 3 GiB floor after the first Recovery attempt stopped for space; see the recorded budget transition below. Do not shrink a raw disk by truncation.

## Metadata observed directly from GHCR

The initial metadata inspection used anonymous HTTPS requests for tokens and OCI manifests only. The subsequent completed disk transfer is recorded separately below. Values below sum manifest layer sizes, including the tiny config/NVRAM layers. All listed manifests declare a 50,000,000,000-byte logical disk.

| Image tag | Compressed bytes | Compressed GiB | Manifest digest |
| --- | ---: | ---: | --- |
| Sonoma vanilla `14` | 15,415,516,692 | 14.36 | `ce5f9cdb5fabffddf19ccfa66f16b3c8e8641d271e4edf9475488b86f061b852` |
| Sonoma vanilla `14.1` | 15,845,681,378 | 14.76 | `a6dc5a325aae43a90244953af0a85091fbe93e8f58583138c5ac96dd707fd700` |
| Sonoma vanilla `14.3` | 16,033,736,628 | 14.93 | `57db14ca8a50c992d9213f9c2ce6cca5de63e31f958227383bca17fe7f668b7e` |
| Sonoma vanilla `14.5` | 16,095,587,430 | 14.99 | `b4b6adc2598cd479e1cc9d58c289d8931749bd80a67e8332cce2216d0d813ca7` |
| Sonoma vanilla `latest` / `14.8.7` | 20,766,391,603 | 19.34 | `7ea0d508380b63f13c94ee72cd22ca3dd9ec5cdf4a5ae14b2ae2ce6a6603fba6` |
| Sonoma base `latest` | 22,563,882,329 | 21.01 | `e2ebdfc4d354b336fe00d729c11a8136a019b8046f41cc183a2fe51b85d18f49` |

Source endpoints: [vanilla manifests](https://ghcr.io/v2/cirruslabs/macos-sonoma-vanilla/manifests/14.5), [base manifest](https://ghcr.io/v2/cirruslabs/macos-sonoma-base/manifests/latest), [publisher's package page](https://github.com/cirruslabs/macos-image-templates/pkgs/container/macos-sonoma-vanilla). GHCR manifest endpoints require an anonymous bearer token. The package page associates the `14` digest with `14-RC`; its actual release/build must be recorded after boot, without representing an RC as a shipping-system guarantee.

## What consumes disk space

Tart 2.38.0 creates a sparse disk of logical size and skips all-zero chunks while decompressing. The manifest annotation `org.cirruslabs.tart.uncompressed-disk-size` comes from the disk file's logical `.size`, **not allocated blocks**. Therefore 50 GB virtual capacity does not require 50 GB initially, and compressed transfer size is not an adequate prediction of allocated size. [DiskV2 source](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/OCI/Layerizer/DiskV2.swift), [OCI push source](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/VMDirectory%2BOCI.swift).

In this exact release, `Fetcher.fetch` uses a URLSession data task and yields 16 MiB buffers. Its `viaFile` argument is unused. Downloaded disk data feeds the decompressor; it does not first retain a second complete compressed disk archive. The completed attempt used concurrency 4 with the external watchdog; it is no longer an active transfer. [Fetcher](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Fetcher.swift), [Registry](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/OCI/Registry.swift).

Remote cloning first reconstructs the OCI cached VM, then clones the disk with APFS copy-on-write. The local writable clone initially shares blocks; only later writes add allocation. Keep cache and clone on the same APFS volume. A task-specific `TART_HOME=/private/tmp/cascade-addon-vm/state` avoids user caches. `TART_NO_AUTO_PRUNE=1` disables automatic cache deletions; monitor the host volume's actual available bytes, not apparent file sizes or the sum of per-file `du` values for shared clones. [Clone implementation](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Commands/Clone.swift), [VMDirectory](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/VMDirectory.swift), [automatic pruning documentation](https://tart.run/faq/#automatic-pruning).

Installing from IPSW is less suitable for this space budget: Tart retrieves the complete IPSW into its cache before `VZMacOSInstaller` creates the guest contents, so the installer and growing guest disk coexist. This is a source-supported explanation of the peak, not a measured size for a specific IPSW. [VM installer source](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/VM.swift).

## Operating limits

- One VM, configured to 2 virtual CPUs and 4 GiB RAM after the clone completed; no added Xcode, Homebrew, snapshots, or duplicate backup disk. The small config layer for the exact `14.1` digest reports `cpuCountMin=2`, `memorySizeMin=4294967296`, `os=darwin`, `arch=arm64`; defaults are 4 CPUs/8 GiB.
- Guard download and later boot independently. The completed download used a 3 GiB floor and 14,400-second timeout. Subsequent boot/Recovery runs use a 3 GiB floor and finite 1,800-second manager timeout; 3.5 GiB was the earlier boot floor. A sparse disk can still grow during boot.
- Use the original publisher-provided `tart.app` executable in its bundle so the provisioning profile remains available. [Official quick start](https://tart.run/quick-start/).
- Qualify external VM stop before deliberately suspending the provider. Keep host fixture credentials and signing identities outside the guest; transfer only signed test artifacts.
- If the selected `14.1` image cannot fit within the watchdog, stop rather than consume the reserve. Larger compressed images cannot be assumed to rescue an allocation failure.

## Guest setup and security profile

The 14.1 template at commit `3e3e6818f376c6764d3e6c6d7c275e756fb897df` (2023-10-25) references Apple's `UniversalMac_14.1_23B74_Restore.ipsw`, enables SSH and screen sharing, and provisions the `admin/admin` lab account with auto-login and passwordless sudo. It does **not** install Command Line Tools or Xcode, and contains no SIP or authenticated-root disable command. It also enables Full Disk Access for Remote Login and Safari remote automation. This is a laboratory observer profile, not an OS security profile identical to the user's machine. Provider sandbox and signature must remain unchanged. The template is historical context, not byte-for-byte proof of the published disk: its disk-size setting differs from the manifest, and the first boot now contradicts its expected OS version and protection profile. [Historical template](https://github.com/cirruslabs/macos-image-templates/blob/3e3e6818f376c6764d3e6c6d7c275e756fb897df/templates/vanilla-sonoma.pkr.hcl).

The first boot recorded `sw_vers`, `csrutil status`, and `csrutil authenticated-root status`: macOS 14.3, SIP disabled, authenticated root enabled. Recovery subsequently restored SIP, and two normal boots verified SIP and authenticated root enabled before the ordinary baseline attempts. Keep the VM's virtual network unbridged and do not transfer personal credentials. The guest's administrative lab account is for controlling tests; it does not authorize weakening host protections or provider entitlements.

## Download retry behavior verified in Tart 2.38.0

Historically, `/private/tmp/cascade-addon-vm/download-result.json` recorded concurrency 1, exit -15 after 499.92 seconds, and a 4.5 GiB minimum-free-space threshold (`4831838208` bytes). The coordinator then resumed the same digest/reference and `TART_HOME` with concurrency 4. The intermediate snapshot of 18% at 940 seconds with 19.63 GiB free was only progress. It is superseded by the completed four-stream clone recorded below.

Within one layer, `rangeStart`, the LZ4 decoder, and the output offset survive all five retry attempts. The next HTTP request uses `Range: bytes=<rangeStart>-` and requires status 206; the counter advances only after data is delivered to the decoder. A network failure may discard the last unyielded buffer, which was not counted. Thus retries do not automatically inflate the percentage by counting a complete layer again. [DiskV2, lines 207–240](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/OCI/Layerizer/DiskV2.swift#L207), [Registry, lines 279–303](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/OCI/Registry.swift#L279).

If the whole-image retry starts, or the process is restarted, the deterministic temporary directory survives only if it was not removed by the cancellation handler. Complete layers are detected by hashing their uncompressed ranges and skipped. Incomplete layers restart from zero; a new percentage counter is created. Keep the exact same remote reference string, because the temporary directory key derives from that string. Frequent restarts would discard partial progress of multiple layers. [VMStorageOCI, lines 447–527](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/VMStorageOCI.swift#L447), [DiskV2, lines 94–167](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/OCI/Layerizer/DiskV2.swift#L94), [progress counter](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/VMDirectory%2BOCI.swift#L47).

Tart does not configure a five-minute request timeout. Its default URLSession configuration uses Apple's default request inactivity timeout, 60 seconds reset by new data, and resource timeout, 7 days. Those defaults were verified in the local SDK's `Foundation/NSURLSession.h`, lines 1317–1340. A logged “network connection lost” should not be relabeled as a configured five-minute timeout without further evidence. [Fetcher configuration](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Fetcher.swift#L3).

## Minimum first-access sequence — first boot observed, checks incomplete

**Network choice:** use the framework's standard shared NAT, then remove default routes inside the guest and verify both IPv4 and IPv6 tables. This is not host-only networking. Tart's `--net-host` uses a separate Softnet executable and its privileged setup; Softnet is absent from the portable bundle and the host PATH checked during this task. The coordinator chose to avoid that additional helper. Omit `--net-host`, `--net-softnet`, and `--net-bridged`. [NetworkShared](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Network/NetworkShared.swift), [network selection](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Commands/Run.swift#L684), [Softnet setup](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Network/Softnet.swift#L151).

1. After the clone succeeds and resource limits are set, retain the `Popen` for the original `tart run` process. Use `--no-graphics --no-audio --no-clipboard` and `--dir=payload:/private/tmp/cascade-addon-vm/payload:ro`. Do not request suspension or snapshots. Headless presentation does not imply the guest has no GUI login session; the image is configured for auto-login.
2. Resolve the candidate guest address with `tart ip cascade-addon-small --wait 30`, using the default DHCP resolver. This consults leases for the VM MAC; it does not prove that SSH is ready. Use bounded SSH connection attempts afterward. The `agent` resolver requires a guest agent that is not part of this historical vanilla setup. [IP command](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Commands/IP.swift).
3. Log in as `admin`, with the published lab password `admin`. Use a task-local SSH known-hosts file, `StrictHostKeyChecking=accept-new`, `ConnectTimeout=5`, one connection attempt, and no host credential or agent forwarding. Record the host key; do not silently accept a changed key. The first-boot preflight now records successful SSH execution as `admin` (UID 501); this no longer depends solely on the historical template. [Published credentials](https://tart.run/quick-start/), [14.1 template](https://github.com/cirruslabs/macos-image-templates/blob/3e3e6818f376c6764d3e6c6d7c275e756fb897df/templates/vanilla-sonoma.pkr.hcl).
4. Through SSH, record `sw_vers`, `uname -m`, `id`, `/usr/sbin/sysctl -n kern.bootsessionuuid`, `/usr/sbin/sysctl -n kern.boottime`, `csrutil status`, and `csrutil authenticated-root status`. Record failed commands as failures, not an inferred supported state. Verify the console account separately before ExtensionFoundation tests.
5. Inspect `netstat -rn -f inet` and `netstat -rn -f inet6`. Remove any default route only inside the guest (`sudo route -n delete default`, and the IPv6 equivalent when present), then record both tables again. Preserve the directly connected subnet used by SSH. Recheck before each test because later network configuration/DHCP events may restore a route. Absence of a default route is the measured condition, not a claim of firewall isolation.
6. Verify the read-only VirtioFS share at `/Volumes/My Shared Files/payload`, including a fixture manifest/hash. With the default automount tag, no manual mount is normally needed. If automount is absent, inspect existing mounts before trying `mkdir -p /Users/admin/cascade-shared` followed by `mount_virtiofs com.apple.virtio-fs.automount /Users/admin/cascade-shared`; the named payload is then beneath that mount point. Do not grant additional host/guest TCC permissions merely to repair a mount failure. Copy the signed extension bundle and test binaries into a local guest directory before registration/execution. [Directory-sharing contract and mount commands](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Commands/Run.swift#L160).

The historical 14.1 template does not disable automatic software updates. Do not describe them as already disabled. Guest-only read checks of `/Library/Preferences/com.apple.SoftwareUpdate` and `/Library/Preferences/com.apple.commerce` can record existing settings; missing keys are unspecified, not false. The selected no-default-route state prevents the ordinary Internet route during the bounded probe once verified; no host update settings are changed.

Tart's documented VirtioFS requirement is macOS 13 or newer on both host and guest. The observed 14.3 guest meets it. The first-boot preflight lists `/Volumes/My Shared Files/probe/payload.tar.gz`, establishing that the actual named share was visible; it does not prove the signed payload passed verification or executed. Host-side login-keychain/local-network access can also affect launch or SSH on newer macOS; the official FAQ describes those failure classes. Observe and report the actual error if one occurs, without automatically changing host security settings. [Sharing requirements](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Commands/Run.swift#L160), [Tart FAQ](https://tart.run/faq/).

## External stop preflight — qualified for the measured VM run

Start with a responsive guest, record its boot-session UUID, and issue `tart stop cascade-addon-small --timeout 5` from the host. In Tart 2.38.0 this sends SIGINT to the manager, whose cancellation path awaits `VZVirtualMachine.stop()`; this is the forceful VZ stop API, not the guest-cooperative `requestStop()`. After the timeout the stop command can instead send SIGKILL to the manager and return without waiting. [Stop](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Commands/Stop.swift), [signal handler](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/Commands/Run.swift#L603), [awaited VZ stop](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/VM.swift#L273), [Apple stop contract](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/stop(completionhandler:)).

Require the retained original manager's actual exit, the `Stopping VM...` log plus exit 0 for the completed VZ-stop path, then Tart state `stopped`. State alone only reflects the manager's PID lock and absence of a saved-state file. Finally cold-boot the same VM, reconnect, and record a different guest boot-session UUID. If the manager exits -9, report a separate fallback-kill result; do not label it successful completion of `VZ.stop()`. This qualifies the laboratory recovery mechanism for the measured run, not addon managed death or an untested hung-guest scenario. [Tart state implementation](https://github.com/cirruslabs/tart/blob/2.38.0/Sources/tart/VMDirectory.swift#L48).


`/private/tmp/cascade-addon-vm/cleanup-evidence.json` records the completed
qualification: a responsive guest, the retained Tart manager's actual exit 0,
`stopMessagePresent=true`, and a subsequent Tart listing with `State=stopped`.
The next normal boot responded over SSH with a different boot-session UUID:
`FBA4BFDB-27B7-497E-86CA-315E8104ECE1` →
`70146061-7758-48BA-AB56-0CED74AE20F9`. The record pins manager and VM-config
SHA256 values. This qualifies external VM stop and cold boot for this measured
run; it establishes neither addon managed death nor behavior of a hung guest.


## Measured retry and reduced budget

The first transfer reached 99%, then its 4.5 GiB watchdog terminated the retained
Tart child and removed this attempt's incomplete state. Free space rose from
4,813,242,368 to 22,428,499,968 bytes. This demonstrates the earlier guard was reached;
it is not a guest boot or an ExtensionFoundation result.

The subsequent bounded attempt used a 3 GiB download floor and an independent
3.5 GiB boot floor, preserving partial state on stops. Six simultaneous
transfers proved worse on the observed connection: per-layer retries were
exhausted and the whole-image counter restarted. The coordinator returned to
four streams. The first four reconstructed disk ranges were independently hashed
while transfer continued and matched the pinned uncompressed digests; this was a
read-only progress snapshot, not final image admission.

### Completed transfer and standalone image

`/private/tmp/cascade-addon-vm/download-compact-four-result.json` records the
pinned clone with concurrency 4, exit **0**, and 5,876.598 seconds elapsed. It
finished at **2026-09-25 22:26:36 UTC** with 3,497,390,080 bytes free (3.26 GiB).
The configured download floor was 3,221,225,472 bytes; the 14,400-second deadline
was not reached. These are completion measurements, replacing the earlier
percentage snapshots.

`/private/tmp/cascade-addon-vm/small-config-and-cache-removal.json` records
successful configuration to 2 CPUs, 4,294,967,296 bytes RAM, and a fixed 1024×768
display. The cached OCI reference was then deleted successfully. Tart listed one
local `cascade-addon-small` VM with `Running=false` and `State=stopped`; the
record confirms one standalone disk. This listing establishes the prepared VM's
recorded state, not a successful guest boot or a qualified external stop.

### Measured 64 KiB compaction

After the transfer stopped and the OCI cache clone was removed, the laboratory
helper scanned the standalone raw disk and used `F_PUNCHHOLE` only on completely
zero 64 KiB blocks. `/private/tmp/cascade-addon-vm/image-compaction.json` records
exit 0 and the following actual measurements:

| Measurement | Before | After |
| --- | ---: | ---: |
| Raw logical size | 50,000,000,000 bytes | 50,000,000,000 bytes |
| Allocated disk bytes | 17,812,783,104 | 17,584,783,360 |
| Host free bytes | 3,489,792,000 | 3,694,592,000 |

The disk allocation decreased by **227,999,744 bytes** (approximately 228 MB).
The helper's `punchedBytes=32,415,219,712` counts zero ranges submitted, including
already sparse ranges; it is **not** reclaimed storage. Host free-space change
is separately measured and can also reflect unrelated host activity.

Complete streaming reads before and after produced the same SHA256:
`0c0d46984b170fe9f40bbcfc1ef3a490a878fbd95d8fdd3d6b051c677d085721`.
The raw image was not resized or copied. The record pins helper binary SHA256
`30e3856e8bf7d43f4c50363dbb1c2ee9e6e99ae3008ada7d2280a175e4f06ecf`
and source SHA256
`4cbba931e5436c65da52c8860d0564170ece52811cf7befa77290d2f0ad18d96`.

At this checkpoint, **2026-09-25 22:29:35 UTC**, host free space was **3.44 GiB**,
still 63,504,384 bytes below the separate 3.5 GiB boot floor. Download completion
and unchanged image contents therefore did not yet admit a guest boot. Any later
space measurement, boot, or guest result belongs in a subsequent verification
record.

### Measured 4 KiB compaction and later boot budget

`/private/tmp/cascade-addon-vm/image-compaction-pages.json` records the second,
4 KiB pass using `SEEK_DATA`/`SEEK_HOLE` to skip existing holes. Disk allocation
fell from 17,584,783,360 to 17,507,381,248 bytes: **77,402,112 bytes recovered**.
Logical size remained 50,000,000,000 bytes, and full rereads retained the same
`0c0d46984b170fe9f40bbcfc1ef3a490a878fbd95d8fdd3d6b051c677d085721`
SHA256. The larger host-free-space rise in that record, from 4,423,680,000 to
6,307,840,000 bytes, must not be attributed to this 77 MB compaction; host-wide
free space includes other activity.

The first Recovery manager stopped on its **3.5 GiB** floor after 29.652 seconds
(`/private/tmp/cascade-addon-vm/sip-recovery-1/result.json`). The coordinator's
space observation at that point distinguished about 67 MB of raw-image growth
from a 1 GiB host swap allocation. The next Recovery run used a **3 GiB** floor
and a 1,800-second manager deadline
(`/private/tmp/cascade-addon-vm/sip-recovery-2/result.json`); later normal-boot
records retain that 3 GiB floor. This was a budget change, not a claim that the
compactor recovered the host's swap or several gigabytes of image data.

### Prepared fallback and unperformed checks

An alternative local downloader has also been prepared and reviewed, but has not
fetched an OS layer or modified the active disk. It uses curl continuation files,
checks compressed SHA256, and feeds a small Foundation/Compression helper. The
helper punches aligned zero ranges and verifies SHA256 by rereading the actual
destination interval; seven synthetic checks passed. Three loopback-only curl
checks cover disconnect/resume, an ignored Range request, and a wrong digest.
It never publishes a VM directory itself. Tart completed the transfer without
using this fallback; the alternative remains prepared and is not a second VM.

The earlier download/compaction checkpoint preceded boot. The later guest state
and the resolved security blocker are recorded below. Updated records live in the
[verification report](../../superpowers/verification/2026-09-25-addon-small-vm.md)
and its evidence directory.

## First boot observed — protection defect subsequently repaired

`/private/tmp/cascade-addon-vm/boot-1-preflight.json` finished at
**2026-09-26 09:40:04 UTC** with SSH command exit 0. The actual guest reported:

| Check | Observed value |
| --- | --- |
| macOS version / build | 14.3 / 23D56 |
| Hardware model | VirtualMac2,1 |
| Guest account | admin, UID 501 |
| SIP | disabled |
| Authenticated root | enabled |
| Boot-session UUID | FDD434DD-F26D-4FA6-B77C-EDBF37CFAF65 |

This was the first measured protection state; the laboratory did not disable
SIP to obtain it. The image tag and historical template are insufficient to
claim an unmodified protection profile. No native suspended-addon test should
be admitted from this state. Authenticated-root protection remains enabled and
does not substitute for SIP.

The IPv4 routing table had no default after the removal attempt. The IPv6 table
still contained default routes on `utun0` through `utun3`, so the intended
no-default-route condition was **not** achieved. Overall SSH exit 0 does not
convert those remaining routes into a successful network check. The later `qualified-boot-2-preflight.json` records both IPv4 and IPv6 default
routes successfully removed. Each new boot still requires its own route check.

## Recovery procedure — executed by the coordinator and verified

The local Tart 2.38.0 `run --help` lists `--recovery`. Tart's official FAQ says to
boot with that flag, select **Options**, and open Terminal in Recovery; it also
describes shutting down and starting Tart normally afterward. Its disk-resizing
instructions are unrelated to this repair and must not be performed.
[Tart Recovery UI procedure](https://tart.run/faq/#disk-resizing).

After the coordinator has confirmed the original VM process stopped, preserve
the same laboratory environment and its space watchdog, but use the graphical
window for Recovery:

```sh
TART_HOME=/private/tmp/cascade-addon-vm/state TART_NO_AUTO_PRUNE=1 \
  /private/tmp/cascade-addon-vm/tart.app/Contents/MacOS/tart \
  run --recovery --no-audio --no-clipboard cascade-addon-small
```

Inside **the guest Recovery Terminal**, run `csrutil enable`. Apple's procedure
requires Recovery, Terminal, that command, and a subsequent restart. Record the
actual result and any authentication prompt; do not infer success from merely
entering the command. [Apple: enabling SIP](https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection).

Shut down the Recovery guest and start the same VM normally, omitting
`--recovery`. After SSH is available, record `sw_vers`, `csrutil status`,
`csrutil authenticated-root status`, the new boot-session UUID, and both route
tables. Require SIP **enabled** before continuing; complete the external-stop
qualification and other outstanding preflight checks before any suspended
provider test.

`/private/tmp/cascade-addon-vm/sip-restoration.json` records `csrutil enable`
entered through the guest Recovery UI, followed by verification in
`qualified-boot-1-preflight.json` and `qualified-boot-2-preflight.json`. Both
normal boots report **SIP enabled** and **authenticated root enabled**. Host
security settings were not changed. Native fault tests had not started during
this restoration.

## Ordinary baseline and discovery controls — no fault injection

All following artifacts are under `/private/tmp/cascade-addon-vm/`. The original
signed fixture/archive and its provider requirement were retained.

| Control | Recorded outcome | Evidence |
| --- | --- | --- |
| Initial release baseline | FAIL during static CDHash preflight; no root PID was started | `case-baseline-release-1/guest-results.tar.gz` (`result.json`) |
| Architecture-specific static validation | Exact arm64 requirement passes; x86_64 against the arm64 pin and an incorrect arm64 pin fail as expected | `guest-signature-matrix.json`, `signature-host-matrix.json` |
| Corrected arm64 release baseline | Inputs verified; root and broker authenticated; first ordinary HELLO times out after 10 seconds | `case-arm64-release-1/events.jsonl` |
| Ordinary startup-phase control | Broker remains `idle` in the five polls after HELLO; no HELLO reply | `ordinary-startup-phase-1.json` |
| Explicit root-bundle registration | Registering BrokerRecovery.app does not resolve the same discovery failure | `registered-startup-phase-1.json`, `guest-registered-log.json` |
| LaunchServices root launch | `open -W -n` with FIFO/file I/O starts the actual root and broker, but discovery remains `idle`; no HELLO reply | `launchservices-startup-phase-1.json`, `guest-launchservices-log.json` |

The first baseline applied an arm64 CDHash requirement to a universal binary
without selecting its architecture. `baseline-architecture-correction.json`
records adding `--arch arm64` only to that exact static requirement check.
All-architecture integrity checking remains, and no provider requirement,
fixture binary, manifest, guard, or classification was weakened. The host
sandbox's earlier `CSSMERR_TP_NOT_TRUSTED` result is retained separately in
`signature-host-matrix-sandbox.json`; the successful static host matrix was run
outside that execution sandbox, not by changing the signature.

The phase controls correlate with `guest-discovery-log-2.json`,
`guest-registered-log.json`, and `guest-launchservices-log.json`: LaunchServices
fails to resolve the broker's bundle record from its audit token, reporting
`-10814`, and ExtensionFoundation creates a query with a null extension point
and platforms 0. The source advances from `idle` only after matching the
provider identity, before constructing `AppExtensionProcess`. These observations
place this blocker in discovery, not in an intentionally suspended provider.
They do not establish the precise internal cause of the bundle-resolution
failure.

The coordinator inspected the guest's System Settings → Extensions →
BrokerRecovery entry and observed CascadeProbeProvider already checked. No new
consent setting was changed. This UI observation is not proof that the broker's
discovery context resolved successfully. The archived root app does contain its
`Contents/Extensions/Probe.appextensionpoint`; registering it and launching it
through LaunchServices have now been tried without resolving this error.

### Direct-app negative control

`direct-app-control-1.json` contains an inner fixture exit 1 / FAIL even though
the SSH wrapper exited 0. It nevertheless records discovery of
`hylo.Cascade.AddonProbeContainer.Provider`. `direct-app-control-log.json`
records provider App Sandbox initialization, ExtensionFoundation launch, the
provider's initialization log, and its listener. It then records the provider
setting a peer code-signing requirement for
`hylo.Cascade.AddonProbe.DiscoveryBroker`, followed by rejection `-67050`.

The direct ProbeHost has identifier `hylo.Cascade.AddonProbe`, so this is the
expected rejection by the intentionally broker-only fixture. It confirms direct
app discovery and provider initialization on the observed 14.3 guest, but gives
no successful HELLO. It is not a second provider-loading bug, a dyld failure, or
a reason to remove peer authentication.

### Scope of the remaining blocker

The public SDK marks the legacy matching API, `AppExtensionProcess`, and
`makeXPCConnection` available from macOS 13; the source hashes match those in
the fixture manifest. That establishes API availability, not successful broker
hosting on every supported OS. The direct-app control now additionally rules
out a general inability to load and initialize this provider on this guest.

**No start-suspended action was armed, no native fault case ran, and no managed
addon-death result was obtained.** The production gate remains blocked;
`production-gate.json` records exit 78 / HOLD. The observed broker-discovery
failure applies to this fixture on **macOS 14.3 / 23D56**. It neither proves
that all macOS 14 implementations are impossible nor qualifies macOS 27 or a
production launcher. Subsequent results belong in the verification report and
must retain these failed controls as evidence.

## Final metadata-only comparison — no replacement downloaded

Before the user paused the VM approach, anonymous registry requests read the vanilla image tags, OCI manifests, and small configuration blobs. No OS layers were downloaded. The following values are retained from those tool outputs; **raw metadata JSON files were not saved**, so there are no separate manifest/config/tag-list artifact paths to preserve.

| Image | Compressed layer total (bytes) | Disk-size annotation (bytes) | Format |
| --- | ---: | ---: | --- |
| Tahoe vanilla `26.0` | 23,960,094,563 | 50,000,000,000 | raw |
| Tahoe vanilla `26.1`, smallest transfer among the nine returned tags | 23,121,995,388 | 50,000,000,000 | raw |
| Tahoe vanilla `latest` / `26.6.2` | 23,990,480,836 | 50,000,000,000 | raw |
| Golden Gate vanilla `latest` / `27.0` | 30,901,319,029 | 35,735,707,648 | ASIF |

The inspected Tahoe tag list was `latest`, `26.0`, `26.1`, `26.2`, `26.3`, `26.4`, `26.5`, `26.6.1`, `26.6.2`; Golden Gate returned `latest`, `27.0`. The selected comparison digests were:

- Tahoe `26.1`: `sha256:3d12c16147f3aef36401b7889fee87551a963be5c6ae30b1075d0c5f6b64c021`.
- Golden Gate `27.0`: `sha256:b78a521145ebef24e9916c0b3999e165bb12b587d11524c5fa3ba4fe7bf79bb9`.

Both small configurations identify `arm64` / `darwin`, minimum 2 CPUs and 4,294,967,296 bytes RAM, and defaults of 4 CPUs / 8 GiB. The vanilla templates do not install Xcode. The ASIF annotation describes the uploaded disk file's uncompressed length, not guest virtual capacity or physical allocation. [Tahoe manifest](https://ghcr.io/v2/cirruslabs/macos-tahoe-vanilla/manifests/26.1), [Golden Gate manifest](https://ghcr.io/v2/cirruslabs/macos-golden-gate-vanilla/manifests/27.0), [Tahoe template](https://github.com/cirruslabs/macos-image-templates/blob/main/templates/vanilla-tahoe.pkr.hcl), [Golden Gate template](https://github.com/cirruslabs/macos-image-templates/blob/main/templates/vanilla-golden-gate.pkr.hcl).

Actual allocated bytes are not published in these metadata. Compressed transfer size is **not a rigorous lower bound on sparse-file allocation**, and the disk-size annotation is not that allocation either. Consequently neither candidate was demonstrated to fit the then-estimated 18.3 GB allocation allowance while retaining the host reserve. These figures justified no automatic replacement or new download. The user's later instruction supersedes that comparison: the VM route is paused, and the app's minimum OS target is unchanged.
