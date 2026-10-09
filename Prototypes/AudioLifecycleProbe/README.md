# Audio lifecycle probe

Run `Prototypes/AudioLifecycleProbe/run-probe.sh` from the repository root. It
compiles `main.swift` with `swiftc -O` against the configured Xcode SDK into a
temporary directory and is not linked into Cascade. Someone has to listen and
answer y/n at each step.

It plays a quiet tone with `afplay`, then answers three questions about a
process that dies with SIGKILL:

- A: does a private aggregate holding a process tap disappear with its creator?
- B: does the tapped app stay muted (`mutedWhenTapped`) after the kill?
- C: does a public stacked aggregate survive its creator?

A and B are read from what the listener hears, not from `inspect`: a private tap or
aggregate is visible only to the process that created it, so a fresh process
reports it absent whether or not it survived. The script asks "audible?" three times: (a) before `create-private`, the tone playing natively;
(b) after `create-private` printed its JSON and before the kill; (c) after the
kill. The IOProc reads the tap (`mutedWhenTapped` mutes only while a client reads
the tap) and writes silence to the output, so at (b) the tone must be SILENT:

- (b) silent, (c) audible: the tap, its muting and the aggregate died with the
  process (A yes, B no).
- (b) silent, (c) silent: the muting tap outlived the process (A no, B yes).
- (b) audible: the tap never muted, the run is invalid.

The script waits up to 30 s for `create-private` to print its JSON before it asks
about (b), so the System Audio Recording prompt can be answered first. The
paste block ends with a `Reading:` line applying the rule above.

## Modes

`create-private <pid>` taps `<pid>` with `mutedWhenTapped`, builds the private
aggregate and runs an IOProc that reads the tap and writes zeros.
`create-public` builds a public stacked aggregate over the default output.
`inspect [--destroy] <uid>...` reports whether each UID is still in the device
or tap list as JSON, and with `--destroy` removes it, together with any
`Cascade-probe-*` or `cascade.multi-output.probe-*` leftover of an earlier run.

The probe needs the System Audio Recording permission for the terminal that
runs it. A tap that fails to create prints the exact OSStatus and exits; it does
not try to work around the permission. An observed absence is a result, not a
probe failure. The script destroys what it created on exit.
