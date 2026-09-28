# Mostrare il consumo di un servizio tramite SDK pubblico

ID: 27
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 24

## Question

Creare un esempio sorgente indipendente di provider e consumer di un servizio sintetico, con selezione dei grant forniti dall’host, richieste e completamenti correlati, payload limitati e test pubblici. Distinguere il comportamento del consumer dalla vera risoluzione REQUIRES e dalla revoca nativa.

## Context

Incremento C12 della prosecuzione autorizzata il18settembre. [Piano](../../../docs/superpowers/plans/2026-09-18-service-consumer-source.md). Il servizio è dimostrativo e non viene attribuito al provider StandaloneFocus.

## Progress

Disegno esaminato; implementazione da completare.

## Answer

Esempio sorgente con contratto condiviso, provider sintetico e consumer implementato. Build indipendente, manifest validati e 16 test passati; revisione indipendente PASS, inclusi i miglioramenti del rendezvous e delle asserzioni degli errori. [Verifica e limiti](../../../docs/superpowers/verification/2026-09-18-service-consumer-source.md). Grant e messaggi sono esercitati con API pubbliche; risoluzione REQUIRES, revoca canonica e parità native restano da qualificare.
