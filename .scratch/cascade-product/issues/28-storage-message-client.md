# Connect the SDK storage client to the message path

ID: 28
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 23

## Question

Implement a concrete read/write/remove SDK client with an injected message channel, preserving correlation, cancellation, uncertain outcomes and waiting for physical cleanup. Verify the wiring to the real runtime and storage backend with a test bridge and pre-admitted resources.

## Context

Storage/SDK increment of the continuation authorized on 18 September. [Plan and acceptance matrix](../../../docs/superpowers/plans/2026-09-18-addon-storage-message-client.md). No new protocol or launcher; the tests do not qualify the OS transport.

## Progress

Design examined; implementation taken on with Codex Sol high.

## Answer

Concrete client and internal bridge implemented and reviewed: 955 tests / 87 suites, external examples 37 + 16 tests, signed build and restart verified. [Evidence and limits](../../../docs/superpowers/verification/2026-09-18-addon-storage-message-client.md). No native requirement closed; optional P3s and finite coverage declared.
