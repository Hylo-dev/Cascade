# Show consuming a service through the public SDK

ID: 27
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 24

## Question

Create an independent source example of a provider and a consumer of a synthetic service, with selection of the grants provided by the host, correlated requests and completions, bounded payloads and public tests. Distinguish the consumer's behavior from the real REQUIRES resolution and from native revocation.

## Context

C12 increment of the continuation authorized on 18 September. [Plan](../../../docs/superpowers/plans/2026-09-18-service-consumer-source.md). The service is a demonstration and is not attributed to the StandaloneFocus provider.

## Progress

Design examined; implementation to be completed.

## Answer

Source example with shared contract, synthetic provider and consumer implemented. Independent build, validated manifests and 16 tests passed; independent review PASS, including the improvements to the rendezvous and to the error assertions. [Verification and limits](../../../docs/superpowers/verification/2026-09-18-service-consumer-source.md). Grants and messages are exercised with public APIs; REQUIRES resolution, canonical revocation and native parity remain to be qualified.
