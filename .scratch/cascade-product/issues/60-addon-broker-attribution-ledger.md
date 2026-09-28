# Connect the canonical interests to CPU accounting

ID: 60
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-root
Blocked by: 58

## Question

Hook the shared ledger into the broker's commits of new interests and its canonical removals, keeping interests beyond disconnect/exit. Validation before the commit, rollback without losses and an internal check on new interests of consumers whose quota is closed. Terra medium implements; the root and a reviewer verify.

## Answer

Minimal wiring implemented by Terra medium; the root and the independent reviewer had no findings on the frozen code. 39 tests/3 suites PASS. Canonical commits and the ledger share the linearization point without suspensions; exact removals/rollbacks, interests preserved beyond disconnect/exit. Paused consumers can reuse existing interests, but not create new ones. Tests strengthened to distinguish interval history from an interest that is still active. [Report](../../codex-addon/20260922-transitive-cpu/task-60-report.md).
