# Collegare il client storage SDK al percorso a messaggi

ID: 28
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 23

## Question

Implementare un client SDK concreto read/write/remove con canale a messaggi iniettato, preservando correlazione, cancellazione, esiti incerti e attesa della pulizia fisica. Verificare il collegamento al runtime e al backend storage reali con un bridge di test e risorse preammesse.

## Context

Incremento storage/SDK della prosecuzione autorizzata il 18 settembre. [Piano e matrice di accettazione](../../../docs/superpowers/plans/2026-09-18-addon-storage-message-client.md). Nessun nuovo protocollo o launcher; i test non qualificano il trasporto OS.

## Progress

Disegno esaminato; implementazione presa in carico con Codex Sol high.

## Answer

Client concreto e bridge interno implementati e revisionati: 955 test / 87 suite, esempi esterni 37 + 16 test, build firmata e riavvio verificato. [Evidenze e limiti](../../../docs/superpowers/verification/2026-09-18-addon-storage-message-client.md). Nessun requisito nativo chiuso; P3 facoltativi e copertura finita dichiarati.
