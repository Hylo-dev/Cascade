# Addon broker: verifiable restart and isolation

Authorized continuation of the 10 September completion plan; the specification and
policy for direct control and global recovery remain binding.

1. Prove the exit of the broker/provider chain and its re-creation with the same
   host still alive; authenticated kernel observation before every stop, no
   new launch while a previous exit is unknown.
2. Prove two concurrent hosts of the same provider: identify any
   reuse, stop the first chain and verify the other. This proof is not equivalent
   to the isolation of two different addons in the same host.
3. Evaluate from public sources a trusted container that loads the addon code
   after bootstrap; make explicit every format/security choice this requires.
4. Keep results, review and limits; continue on the parts that have been proven,
   stopping only at a necessary design decision. Gate unchanged.

## Log

- Work happens on the current authorized checkout, which contains the entire
  implementation not yet committed. No cleanup or commit of pre-existing changes.
- The new proofs extend the BrokerRecovery fixture, without enabling a production
  launcher. The pre-main windows and the unavailable OSes remain open.
- Classifier: test written before the logic, including false restart,
  guard exit and shared session. Native proofs and cleanup kept separate.
- 1 and 2 completed in the fixture: broker replacement and two hosts PASS. First
  attempt RED due to a missing command; the next one UNKNOWN due to a startup window of
  2 s, kept with an incomplete cleanup verification. Diagnostic window extended to
  15 s after evidence of a request still pending: about 10 s observed, not an SLA.
- Extension required for usability: normal work terminates only the provider;
  two successive providers with the same broker PASS, new start about 66 ms.
  No provider stays alive only to show content. This is a result
  of the fixture, not an integration into the product runtime.
- 3 completed: the late loader does not close the pre-main of the trusted container and
  adds ABI/storage/signing constraints. It is not adopted nor submitted as a
  decisive choice: there is no evidence that it resolves the blocker that would justify changing the architecture.
- 4: three new cases and three native regressions PASS; 25 Python tests PASS; independent
  review with no P1/P2. C0 remains open, according to the decision already taken, without
  proposing the rejected exception again. No commit of pre-existing changes.
