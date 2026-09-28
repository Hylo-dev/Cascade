# Definire e implementare i messaggi dedicati alle invocazioni dei servizi

ID: 30
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 28

## Question

Implementare DTO e codec limitati per richiesta, risposta correlata e invocazione al provider, conservando i limiti esistenti e senza abilitare un nuovo protocollo nel runtime.

## Context

[Piano esecutivo e limiti](../../../docs/superpowers/plans/2026-09-18-addon-service-invocation-frames.md). Tranche tecnica C3 autorizzata dalla prosecuzione dell’utente; distinta dal ciclo SDK in revisione. La prima implementazione usa una copia isolata; integrazione nel package e consegna seguono la chiusura della tranche precedente.

## Progress

Presa in carico con Codex. Nessun handler, adapter, bootstrap o nuova negoziazione attivata.

## Answer

Cinque file importati dall’harness isolata e revisionati PASS. 990 test / 90 suite, build firmata e riavvio verificato. [Evidenze e confini di correlazione](../../../docs/superpowers/verification/2026-09-18-addon-service-invocation-frames.md). Profilo di sola sintassi, negoziazione invariata; handler e client completi restano separati.
