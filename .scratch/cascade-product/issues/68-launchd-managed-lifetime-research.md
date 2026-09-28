# Verify lifetime management through launchd

ID: 68
Parent: cascade-product
Type: research
Labels: wayfinder:research
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

Does the launchd/ServiceManagement lead left open in the 18 September investigation offer a verifiable constraint from the creation of the bootstrap until the exit after the loss of the supervisor/host, under the requirements already approved? Check current Apple sources and primary source code, distinguishing process-group cleanup, the possibility of leaving the group, identity and job lifetime. No job installation, no start of providers/prototypes, no change to entitlements or gates, and no new exception. Produce only a documented outcome that feeds the managed process proof.

## Context

The [decision to keep the launcher blocked](22-managed-process-exit-proof.md) remains binding. The user's continuation authorizes this technical research, without reopening the policy. [Previous investigation](../../codex-addon/20260918-continuation/managed-process-design.md).

## Answer

Sol medium research and root verification concluded: the public contracts examined do not establish the required guarantee. The ServiceManagement registration persists beyond the app, while the launchd cleanup concerns the group at the job's death; membership not shown to be inescapable and physical exit not proven. [Report with sources and limits](../../../docs/wayfinder/research/2026-09-23-launchd-managed-lifetime.md). No native test and no product change. The managed process proof ticket stays open; launcher blocked, no new policy choice required.
