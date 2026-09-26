# Classificare gli episodi di memoria dei provider

ID: 66
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 65

## Question

Implementare una macchina a stato costante per un processo canonico: <=64MiB recupero, oltre64 e fino96 moderato soltanto all’ingresso, oltre96 severo con precedenza, assenza di misura conserva stato. Nessun clock, owner, I/O, timer o policy UI. Terra medium implementa, root e revisore verificano.

## Answer

Implementazione Terra medium verificata da root e Sol indipendente: classificatore a stato costante per incarnazione, confini64/96MiB e continuità corretti.3 test mirati PASS; [revisione](../../codex-addon/20260923-provider-memory/task-66-independent-review.md).
