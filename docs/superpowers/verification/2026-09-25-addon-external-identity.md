# External identity and preparation of the suspended test: 25 September 2026

## Result

Two native runs verify the identity of the provider without using its HELLO
message. The profile remains Hardened Runtime and App Sandbox, with only the
`com.apple.security.app-sandbox` entitlement on the provider. No get-task-allow, debugger,
ptrace, private API or TCC grant added. The production launcher remains blocked.

| Check | Observed outcome |
| --- | --- |
| task-name port → kernel token → signature/CDHash/path → kqueue receipt → token unchanged | succeeded in both runs |
| A different process, signed by the same publisher | rejected by Security, status -67050, in both |
| Subsequent ordinary HELLO and new external confirmation | same provider |
| Cooperative exit of the first provider | kernel event, status 0, before the guard |
| New provider in the same broker | new instance, same domain and diagnostic label |
| Root close and exit of the broker/replacement provider | root 0, broker 9, provider 15; cleanup complete |
| Acquisition of the task control port | denied, status 5 in both |
| launchctl diagnostic configuration of the next invocation | denied: requires root |

Environment: macOS 27 beta 26A5425a arm64, SDK 27, deployment target 14 unchanged.
No runtime qualification of macOS 14/Intel or of different publishers.

## What it adds

The PID read from `ps` only provides a candidate. The C code keeps a name
port, reads `TASK_AUDIT_TOKEN`, authenticates the complete token with Security against
identifier, leaf, exact arm64 CDHash and bundle path, then registers EXIT/EXEC with
EV_RECEIPT. It rereads and authenticates the same token after registration. The first
HELLO request is sent only after this step; the broker must already
report `channel-ready`, avoiding two concurrent launches.

Before the stop, the absence of already queued events is verified, and the identity
again. The observer records the exit; the time is that of reading
the event, not the kernel timestamp. The test verifies an ordinary provider
already running: **it does not demonstrate that none of its instructions had been executed**.
Absence of HELLO is not confused with suspension or with absence of IPC internal to the framework.

The launchctl snapshots show the provider in the `pid/<brokerPID>` domain with
label `hylo.Cascade.AddonProbeContainer.Provider`. After the cooperative exit the
service remains inactive; the new EF request again uses the same domain
and label. These are local diagnostic observations, not a stable discovery API
nor a handle to the single incarnation.

The first preflight thus overcomes the dependency on collaborative code for
identification. The control port, instead, remains unavailable: the name port does not
confer the right to terminate the process. In the second case the command
`launchctl debug` only attempts to add the unused variable
`CASCADE_PROBE_DEBUG_PREFLIGHT=1`; exit 1 and message `requires root privileges`.
`--start-suspended` was never armed, nor was elevation requested through sudo.

## Next test: disposable macOS lab

The candidate solution to the recovery problem of the test is a dedicated VM.
The process stays signed with the ordinary profile and is launched normally
by ExtensionFoundation; the administrative privilege to configure only the test
job stays in the guest. A control on the host Mac can stop the VM if
the suspended provider survives the fault. Apple documents the stop also from the
Paused state without waiting for a cooperative shutdown of the guest.
[VZVirtualMachine.stop](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/stop(completionhandler:)).

Sequence to qualify, **not yet run**:

1. Prepare a VM without personal data, importing the already signed fixtures; the
   signing keys stay on the Mac. First qualify the forced stop of the VM and
   the acquisition of the logs from outside. No false PASS produced by the cleanup.
2. Repeat the ordinary preflight in the guest. Identify the exact job during
   the first run, verify its inactive state after the exit and keep
   root/broker alive. Only the launchctl diagnostic configuration uses root.
3. Arm a single suspended invocation and request it through EF. Verify token,
   signature, effective image and stop phase: provider and xpcproxy are distinct cases.
4. Inject loss of broker/root with an independent observer alive. Save
   result and events before any recovery. If necessary, stop the
   VM; the case remains FAIL/UNKNOWN according to the observations prior to the stop.

This changes the test environment, not the addon format or the architecture of the
product. A future PASS in the VM would not automatically cover first launch,
the xpcproxy interval or every macOS version. The related requirements remain explicit.
The get-task-allow/debugger variant was evaluated but not built because it
would prove a profile different from the one required.

No VM runtime found in the applications/CLIs and in the common paths checked.
The local data volume reports about 5.9 GiB available; the two mounted Asahi volumes
have about 1.4 GiB each. None is suitable for the preparation. The Tart guide
indicates about 25 GB for the ready image and defaults of 2 CPU/4 GB RAM; the proposal
to reserve at least 60 GB is an operating margin for image, disk and tests,
not a minimum requirement of the framework. A question on which volume to use was sent
to the user; no VM downloaded, no installation or deletion of personal data.
[Tart Quick Start](https://tart.run/quick-start/).

## Evidence

[Archive](evidence/2026-09-25-addon-external-identity): `ordinary` corresponds to
`probe-8zj1e_09`; `debug-permission` to `probe-veiyjfa3`. The exact manifests,
sources and runners, logs, tokens, receipts, launchctl snapshots and results are preserved.
The signed fixtures are in `signed-fixture.tar.gz`: loose .app copies in the iCloud
tree received Finder metadata that prevented strict verification. The archives
were extracted into a temporary directory, rechecked byte for byte and
verified with codesign; `integrity.json` records the hashes. No modification of the
executed binaries to archive the evidence.

The first build `probe-t779x3qs` was not run: before the launch the review identified
the race between begin-startup/hello, the missing observation of the
cleanup of the second chain and the missing verification of the pre-trigger events.
The two builds that were run include the fixes. An independent review confirms
the limited claims of the first run; the second result was verified
through manifest, tokens, event sequence and recorded exits.

Gate run: exit 78; SHA256 unchanged
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.
No code of the real Cascade app modified. The mandatory relaunch of the app
is recorded separately in `restart.json` in the archive.
