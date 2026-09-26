# Completare client servizi, sottoscrizioni e aggiornamenti

ID: 34
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 31, 33

## Question

Collegare acquisizione e sottoscrizioni, sorgenti aggiornabili e consegna degli eventi al runtime e al client SDK completo, preservando autorità, quote, ricevute e compatibilità. Attivare il protocollo 1.4 soltanto per l'assemblaggio canonico completo.

## Context

[Piano esecutivo](../../../docs/superpowers/plans/2026-09-18-addon-service-subscriptions-host-sdk.md), con preflight tecnico e decisioni interne già esplicite. Le invocazioni e i contratti sono consegnati e revisionati; il gate nativo resta invariato. Prosecuzione esecutiva solo Codex e deroga alla riserva del 35% autorizzate dall'utente.

## Progress — storico precedente alla consegna

Presa in carico. Baseline consegnata: 1048 test / 94 suite, 469 input sorgente/config e 439 input della build firmata; app verificata con PID20946. Il ticket si chiude soltanto con client completo, prove e revisione indipendente, build firmata e riavvio verificato.

L’implementazione iniziale supera1076 test/96 suite e la compilazione Release, ma la revisione completa rileva tre difetti ulteriori. La correzione SDK è verificata con RED/GREEN e revisione indipendente PASS, inclusi64 alias, overflow, quarantena e riuso; attende l’import dopo il rilascio dei sorgenti host. Le due correzioni host e le prove finite restano in lavorazione. La [verifica corrente](../../../docs/superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md) distingue gli esiti preliminari dalla futura consegna.

## Answer

Client pubblico completo e percorso host controlli/sorgenti/eventi consegnati. Protocollo1.4 condizionato all’assemblaggio canonico completo; default1.0 e legacy preservati. Revisione finale PASS dopo le correzioni di recupero condiviso, latest-event SDK e proprietà delle ricevute.1084 test/96 suite e Release PASS; build Apple Development con controllo SDK obbligatorio, collegamento Applications e riavvio verificato PID85871. [Verifica e limiti](../../../docs/superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md). Il gate nativo resta chiuso.
