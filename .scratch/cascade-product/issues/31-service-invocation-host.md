# Collegare le invocazioni dei servizi al runtime e allo scambio SDK

ID: 31
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 29, 30

## Question

Implementare il percorso interno completo a messaggi per le invocazioni dei servizi, con autorità canonica, risorse preammesse, receipt esatte e risultato SDK, mantenendo compatibilità con i protocolli precedenti.

## Context

[Piano esecutivo](../../../docs/superpowers/plans/2026-09-18-addon-service-invocation-host.md), che incorpora la revisione tecnica su composizione delle generazioni, completion raw, prenotazioni degli slot e drenaggio guidato dagli eventi. Tranche C3 autorizzata dalla prosecuzione dell’utente; nessuna modifica delle garanzie native o dei permessi di prodotto. Client pubblico completo e sottoscrizioni restano successivi.

## Progress

Presa in carico con Codex Sol high; modello e quote precedenti restano invariati fino alle verifiche e alla revisione indipendente.

## Resolution comment — 18 settembre 2026

Percorso interno completo consegnato con negoziazione canonica 1.3, generazione comune, executor SDK, quote e ricevute esatte. Due finestre di concorrenza e il primo tentativo dei nuovi rimborsi corretti con prove causali; revisione finale PASS. Suite completa 1034 test / 93 suite, Release Runtime e build firmata PASS; collegamento Applications aggiornato e riavvio PID 68582 → 18542 verificato per 5 s. [Verifica e limiti](../../../docs/superpowers/verification/2026-09-18-addon-service-invocation-host.md). Client pubblico completo, sottoscrizioni e trasporto nativo restano successivi.
