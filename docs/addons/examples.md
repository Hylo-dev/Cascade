# Source examples with the public SDK

The examples are standalone SwiftPM libraries. They build by pointing explicitly at the SDK package through `CASCADE_SDK_PATH`; each README shows how to copy them and verify them outside the checkout. They depend on the public `CascadeAddonSDK` and `CascadeContracts` products and on their public dependencies.

| Example | Behavior | Required state and authority |
| --- | --- | --- |
| [StandaloneClock](../../Examples/StandaloneClock/README.md) | Declarative hours and minutes, without provider ticks | Identity and previous revision assigned by the host; no storage or service |
| [StandaloneFocus](../../Examples/StandaloneFocus/README.md) | Start, pause, resume and end of a timer with a declarative countdown | Host-assigned identity, authoritative storage and a single writer; persistent revisions and receipts |
| [ServiceConsumer](../../Examples/ServiceConsumer/README.md) | Requesting a grant and reading a synthetic count from a demonstration provider | Grant and client supplied by the host; local revisions for a new assignment |

## Persistent timer

StandaloneFocus separates the timer's state from the actor's lifetime. The initial mode distinguishes a new assignment declared by the caller from the restoration of a previous one; data that is missing, corrupt or belongs to another assignment is not replaced with a new timer.

Every snapshot reserves a revision in the same record as the state. The receipts keep the recent outcomes of actions: an already known result stays distinct from the outcome of a later snapshot write. When the history is not usable, a valid request does not receive a false rejection confirmation. The details of the limits, recovery and deadlines are in the example's README.

The countdown is a declarative value drawn by the host. The example does not create a task that updates the publication every second. A persisted deadline token does not prove that the host admitted the corresponding scheduled event; a later request can reconcile a state that has already expired.

## Demonstration consumer and provider

ServiceConsumer includes an example contract, a provider that returns the synthetic value 3, and a consumer. The consumer depends on the shared contract without importing the provider's implementation. That value does not come from the StandaloneFocus timer's history.

The consumer selects a grant supplied in the context for the specific service, scope and generation. If it has no usable one, it emits a service request and waits for a later call from the host. It does not resolve versions on its own, does not obtain consent and does not automatically activate other processes. The tests check the public messages and the propagation of the outcomes supplied by the client; the actual REQUIRES resolution and canonical revocation remain with the host.

## From source to installed addon

The examples' manifests describe source contracts and do not provide a bootstrap executable, a signature or a distributable container. The standalone build and the provider tests do not prove native admission, bundled/external parity, process termination, or execution on every supported macOS version. That evidence remains in the [completion plan](../superpowers/plans/2026-09-10-addon-runtime-completion.md).

To create a simpler example, use the [generator guide](quickstart.md); to design the tests, see [Verifying an addon provider](testing.md).
