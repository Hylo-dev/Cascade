# Audio system capability probe

Run `python3 Prototypes/AudioSystemProbe/run-probe.py` from the repository root.
It compiles a standalone native process against the configured Xcode SDK and
terminates a stalled execution after 12 seconds. It is not linked into Cascade.

The process queues zero PCM for 200 ms, checks its own HAL process identity and
documented mute capability, round-trips only its own physical-output process mute
when supported, and restores the exact original value. It never changes hardware
master volume, selects devices, captures input, targets another app, or calls an
unknown private ABI. Framework loading and `dlsym` only report symbol visibility.

A readback is not proof of audible gain, cross-process authority, routing,
sleep/wake retention, or support on macOS 15. An unavailable property or symbol is
an observed result, not a probe failure. Any own-mute restoration or running queue
quiescence failure is a probe failure. Silence may still establish an output
session and wake the device briefly; use an explicit hardware fault session for
profile transitions and interruption tests.
