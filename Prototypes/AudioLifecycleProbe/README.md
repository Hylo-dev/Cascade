# Audio lifecycle probe

Run `Prototypes/AudioLifecycleProbe/run-probe.sh` from the repository root, with
someone listening. It compiles `main.swift` with `swiftc -O` against the
configured Xcode SDK into a temporary directory and is not linked into Cascade.

It plays a quiet tone with `afplay`, then answers three questions about a
process that dies with SIGKILL:

- A: does a private aggregate holding a process tap disappear with its creator?
- B: does the tapped app stay muted (`mutedWhenTapped`) after the kill?
- C: does a public stacked aggregate survive its creator?

`create-private <pid>` taps `<pid>` with `mutedWhenTapped`, builds the private
aggregate and runs an IOProc that copies the tap to the output. `create-public`
builds a public stacked aggregate over the default output. `inspect [--destroy]
<uid>...` reports whether each UID is still in the device or tap list as JSON,
and with `--destroy` removes it, together with any `Cascade-probe-*` or
`cascade.multi-output.probe-*` leftover of an earlier run.

The probe needs the System Audio Recording permission for the terminal that
runs it. A tap that fails to create prints the exact OSStatus and exits; it does
not try to work around the permission. An observed absence is a result, not a
probe failure. The script destroys what it created on exit.
