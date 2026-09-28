# Lifecycle of content, jobs and actions

The complete native runtime is not enabled yet. This document describes the components already implemented and their boundary; the connection to processes, authenticated transport, the service broker and the renderer remains in the [completion plan](../superpowers/plans/2026-09-10-addon-runtime-completion.md).

## Content and process have different lifetimes

`PublicationStore` keeps the published values, the revisions and the expiry dates. A normal close of the provider's connection deletes neither the content nor the revision history; it only releases its authority and the associated memory reservation. Disabling and revocation also remove future publications. The [session boundary](sessions.md) binds admission to a canonical host connection: it checks generation, sequence, assigned IDs, revisions and negotiated schemas before changing state. Native process verification still has to be connected; the ID contained in the message alone does not prove who sent it.

## Finite queues, no per-addon timers

`AddonScheduler` handles at most one running job per addon and two globally. Each addon can have four pending commands and sixteen distinct pending updates, within the component's memory budget. A hundred pending update requests for the same publication take a single slot; a command is not dropped to make room for a new one.

Actions normally come before updates. After five seconds a pending update gains priority to avoid indefinite postponement; every job stays subject to its own deadline, capped at thirty seconds from its admission into the scheduler. These values belong to the host policy, which is the same for every origin.

A job that expires before it starts is returned to the runtime so that the runtime reports the rejection. If it was already running, the scheduler requests a stop and keeps the slot occupied until the runtime confirms the actual end of the job or of the process. A stop request is not the same as an observed stop.

`DeadlineQueue` holds up to 1,024 deadlines, replaceable by ID. It distinguishes civil dates from elapsed durations; it removes a deadline exactly once and does not generate backlogged ticks after the Mac has been stopped. It installs no timer: it exposes the next wait to the future runtime, to be handled with a single shared wakeup. Finding the minimum is a bounded scan, without temporary arrays, that runs only on runtime events; it is not part of rendering.

## A lost result does not authorize repeating the command

`ActionJournal` distinguishes a command that is pending, sent, received by the provider, and completed. A receipt acknowledgement is not an execution acknowledgement. Before admitting the command it also reserves space for a 64 KiB result, so a full journal cannot prevent recording the outcome of an effect that has already happened.

The same request returns the known state without creating more work or extending retention. Reusing its ID with a changed input, publication or other field is rejected. The history keeps up to 128 requests per addon for ten minutes from admission, within the component's global budget. At full quota it rejects new requests without discarding the outcomes already known.

After sending, a timeout, a disconnection or a disable can leave the outcome unknown: the external effect may already have happened. The journal does not retry automatically. A late response, or one coming from another generation or another addon, cannot replace the terminal outcome. A command that has not been sent yet instead receives a definite rejection.

The request's civil date is converted into a monotonic deadline on admission into the journal. The scheduler keeps that deadline even if the user changes the Mac's clock. Monotonic durations are valid only for the current runtime instance and are not serialized for the next restart.

## Authorization before delivery

`ActionAuthorizer` checks the verified addon, the feature assigned by the host and the current dependency resolution. The action must appear in the content that is currently usable, with the same input as the request; a future timeline entry does not grant authorization yet. Expired, stale or privacy-redacted content does not authorize new commands. The normal absence of the provider does not prevent an action on content that is still valid.

`ActionDispatcher` composes the journal and the scheduler within a single local limit of 8 MiB, including metadata and the space for outcomes. It reserves a job and produces a single-use ticket; consuming the ticket rechecks the current state before recording the send. Two actions can wait on the same revision, but the revision must be verified again before the second delivery. An old ticket or an outcome from another generation cannot consume the new job.

The production coordinator will have to own these values and the authoritative state, serializing updates, revocations and delivery to the transport. This component does not launch processes, and its own local limit does not yet replace the shared quota of the whole runtime. The [actions contract](actions.md) details outcome recovery, deadlines and confirmation of the end of a job.

## Failures and bounded restarts

`AddonHealthStore` keeps the history of the verified version. Three moderate violations within five minutes put that version in quarantine; a severe violation requires an immediate stop. A crash while demand is still present allows at most three attempts, after 1, 5 and 30 seconds; the fourth crash with demand present puts the version in quarantine.

Each attempt has a ticket that can be consumed only once, bound to the failed session. The runtime must recheck demand and enablement when the deadline arrives. Disabling, revocation or replacement of the session invalidates the earlier tickets. Registering the same version again does not reset the history; resetting it is an explicit host operation. The history survives provider restarts if the host keeps the store, but it is not yet persisted across Cascade restarts.

These are state decisions: resource usage observation and the actual stop still have to be connected to the qualified launcher.

## Boundaries still to connect

The components are state values owned by the host. They do not run addon code in the Cascade process and do not, on their own, constitute authentication or a launcher. The [checkpoint store](storage.md) adds persistence for opaque values and prepared migrations; automatic restoration of publications remains to be connected. The [service broker](services.md) already implements permissions, interests and bounded decisions connected to ResourceGovernor; the coordinator still has to connect these decisions to the authenticated transport and to the real sources. The coordinator must connect the journal, queues and shared quotas without adding up independent budgets as if they were a single limit; the initializers already allow the local budgets to be reduced.

What remains to be connected to the coordinator is the action arbitration already implemented, the handling of stale content, and the publication evidence with a provider that is actually absent. The [native qualification](../superpowers/verification/2026-09-10-addon-direct-v1.md) contains an isolated positive proof of identity after an executable change, but the integrated launcher remains not admitted for the control on supervisor death.
