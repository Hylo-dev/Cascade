# Definire i messaggi di controllo e aggiornamento dei servizi

ID: 33
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 30

## Question

Implementare contratti a messaggi chiusi e limitati per acquisizione, sottoscrizione, avvio sorgente e aggiornamenti, distinguendo accettazione dell'intento da disponibilità del servizio e senza attivare funzionalità incomplete nel runtime.

## Context

[Piano esecutivo](../../../docs/superpowers/plans/2026-09-18-addon-service-subscription-frames.md). Sintassi pura realizzabile in un harness Contracts isolato mentre si completa la consegna del percorso di invocazione; integrazione e client completo restano successivi. Deroga del 35% e prosecuzione solo Codex restano attive.

## Progress

Presa in carico; sei file nuovi, senza modifica dei contratti esistenti o del protocollo negoziato. Importazione nel progetto dopo la consegna verificata del percorso di invocazione.

Implementazione isolata congelata e revisione indipendente PASS senza rilievi: 14 test mirati / 91 test Contracts in 10 suite. [Prove e limiti](../../../docs/superpowers/verification/2026-09-18-addon-service-subscription-frames.md). Sei file ancora fuori dal package reale; ticket non risolto fino all'integrazione e alla consegna.

## Resolution comment — 18 settembre 2026

Sei contratti/test importati dopo la consegna delle invocazioni; revisione indipendente PASS. Suite completa 1048 test / 94 suite, build firmata su 439 input e riavvio PID 18542 → 20946 verificato per 5 s. [Prove e limiti](../../../docs/superpowers/verification/2026-09-18-addon-service-subscription-frames.md). Il profilo 1.4 resta sintassi non attivata: host, client completo e consegna degli eventi sono il prossimo incremento.
