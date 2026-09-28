# Implementare il credito CPU condiviso dell’addon

ID: 47
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 46

## Question

Implementare il valore interno del credito CPU approvato, con ricarica monotona, debito osservato conservato e aritmetica limitata. [Brief](../../codex-addon/20260920-cpu-credit/task-47-brief.md). Terra medium implementa, root revisiona prima del collegamento successivo. Nessuna qualifica o attivazione nativa.

## Answer

Valore interno `AddonCPUBudget` implementato da Terra medium e ricontrollato da root: 100 ms condivisi, ricarica 5 ms/s monotoni, debito conservato e overflow esplicito senza mutazione. 12 test mirati PASS; nessun reset per job. [Rapporto](../../codex-addon/20260920-cpu-credit/task-47-report.md). Revisione indipendente e consegna complessiva restano registrate nel rapporto della continuazione. Il componente non applica sanzioni o avvia processi.
