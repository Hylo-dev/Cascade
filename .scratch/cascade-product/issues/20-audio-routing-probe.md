# Probe per-app routing and simultaneous outputs

ID: 20
Parent: cascade-product
Type: prototype
Labels: wayfinder:prototype
Mode: HITL
Status: open
Assignee: none
Blocked by: 03, 04

## Question

On the candidate macOS versions and the available hardware, does a minimal path based on Core Audio taps satisfy per-app volume/mute, routing and two simultaneous outputs without costs or interruptions incompatible with Cascade? Use a prototype separate from the product, without EQ, with at least one browser source and one native source. Test denied consent, disconnection, sample rate, sleep/wake and process termination, verifying that the original audio is restored and that no orphaned aggregates remain; measure consumption, latency and dropouts. Record which device combinations are missing before generalizing the result. The source research demonstrated a mechanism, not that Cascade passes these tests.
