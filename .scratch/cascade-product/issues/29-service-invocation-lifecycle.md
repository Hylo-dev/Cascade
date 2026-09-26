# Gestire il ciclo SDK delle invocazioni ai servizi

ID: 29
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 28

## Question

Implementare il ciclo interno di correlazione, cancellazione ed esiti incerti delle invocazioni SDK e verificarlo attraverso runtime e broker reali, conservando separate le autorità delle sessioni. Nessun nuovo client pubblico, messaggio o semantica di sottoscrizione.

## Context

Prosecuzione autorizzata del piano C3. [Piano e limiti](../../../docs/superpowers/plans/2026-09-18-addon-service-invocation-lifecycle.md). [Disegno e contratti ancora da definire](../../codex-addon/20260918-continuation/service-client-design.md).

## Progress

Disegno esaminato e tranche presa in carico con Codex; verifica e consegna ancora da eseguire.

## Answer

Componente interno e bridge canonico implementati, correzione del test di replay rivalutata PASS; 978 test / 89 suite, build firmata e riavvio verificato. [Evidenze e limiti](../../../docs/superpowers/verification/2026-09-18-addon-service-invocation-lifecycle.md). Client pubblico completo, sottoscrizioni e prove native restano aperti.
