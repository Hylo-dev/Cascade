# Offline bootstrap model

`bootstrap_abort_model.py` checks the logic of a trusted bootstrap before tracing. It consumes synthetic bytes and observations and returns immutable predictions. It creates no processes, opens no pipes, sends no signals and does not observe the kernel. It does not import the directory's operational drivers.

From the checkout, run only the dedicated suite:

```sh
python3 -B -m unittest discover -s Prototypes/AddonPlatform/Tracing -p test_bootstrap_abort_model.py -v
```

This command does not run the native driver `scripts/test-addon-managed-death.sh`, which keeps its own gate. The verification environment is the one documented in the report; the suite does not qualify real systems or processes.

## Modeled protocol

Create the state with `BootstrapAbortModel.begin(nonce, start_ns)` and keep the value returned by each `observe(...)`. Do not use direct construction of the values to simulate a transition: it is not an authentication boundary.

A record contains a two-byte unsigned big-endian length and one of the following exact ASCII payloads:

```text
1|<nonce of 32 lowercase hex characters>|bootstrap|1|advance
1|<same nonce>|bootstrap|2|complete
```

`complete` is accepted only after `advance`. The nonce is a synthetic value, not a credential. Attach, tracing, exec and further commands are rejected. At most 96 bytes per payload, 196 bytes in total and two frames are accepted; at most 97 partial bytes remain between calls. These limits concern the model's state, without measuring Python allocations or RSS.

Time is an integer in nanoseconds supplied by the caller. The deadline is always start + 2 seconds; fragments, EINTR and valid advances do not renew it. The deadline is terminal even at equality. Boolean values in place of integers, a regressing clock and malformed input are rejected.

| Expected code | Modeled cause |
| --- | --- |
| 70 | Explicit EOF at the boundary between frames |
| 71 | Invalid protocol, field, order, or truncated frame |
| 72 | Absolute deadline reached |
| 73 | Local setup or read error |
| 0 | Normal completion of the baseline |

A HUP notification, EINTR or a batch without data is not equivalent to a zero-byte read: EOF must be indicated explicitly. The model considers all bytes of the batch before concluding successfully; adverse data in the same batch prevails. An already terminal state returns itself on subsequent calls. A token does not prove that its sender is still alive.

## Consistency of the synthetic observations

`evaluate_synthetic_fixture` accepts only the closed schema `cascade.bootstrap-abort.synthetic.v1`, labeled `simulated`. The `fixture()` function in the tests shows the complete record; it is not a format compatible with the historical native reports.

It requires distinct synthetic identities retained before the injection, matching receipts for observer/supervisor/child, an internally possible EOF 70 decision, and eight mandatory observations without duplicates. The modeled case describes a signal 9 injection and requires both of the supervisor's outcomes to be signal 9 and to agree; a normal exit 0 does not substitute for it. Code 9 is only a compared value, never an executed operation. The child's outcome must be 70; a normal-completion grant invalidates this case.

All receipts use a single time domain of the observer and stay within the interval strictly below 1.5 seconds. Model timestamps are not subtracted from the observer's. A missing exit, a log without a receipt, an invalid state, a different identity, a foreign clock, a timeout, guard, fallback, cleanup or any other contradiction makes the case inconsistent. The input can contain at most 16 records; the caller has already allocated its own data before the evaluation.

A positive outcome means exclusively `modelAbortEvidenceConsistent`. The fields `trustedBootstrapAbortObserved`, `supervisorDeathStopsWorker`, `nativeLauncherAdmitted` and `nativeSuccess` remain false. Even a consistent record and a model object can be constructed by the caller: they are not authenticated proofs.

## Limit of the proof

Predicting an abort does not demonstrate the physical exit of the bootstrap, its execution before main, the absence of orphans or the safety of the attach. The complete requirement from creation through exec and the loss of the supervisor remains open. The supervisor and observer guards, the signed identities and the system matrix require separate qualifications.

The [model verification](../../../docs/superpowers/verification/2026-09-18-addon-bootstrap-abort-offline.md) retains tests, review and limits. The [ticket on managed processes](../../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) remains separate from this offline increment.
