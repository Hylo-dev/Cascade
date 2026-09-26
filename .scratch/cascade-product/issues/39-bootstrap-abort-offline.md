# Verificare offline l’interruzione del bootstrap prima del tracing

ID: 39
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

Implementare il modello finito già proposto dall’indagine sui processi gestiti: parsing limitato del canale del bootstrap fidato, perdita terminale dell’autorità e valutazione conservativa delle osservazioni. Distinguere sempre previsione del modello da uscita fisica osservata; nessuna operazione nativa o apertura del gate.

## Context

L’[indagine sul disegno](../../codex-addon/20260918-continuation/managed-process-design.md#smallest-implementation-ready-next-increment-bootstrap-abort-entirely-offline-first) identifica questo passo come preparazione concreta per la decisione sui processi. Il [ticket sui processi gestiti](22-managed-process-exit-proof.md) resta HITL e aperto; il presente incremento non lo risolve. L’audit dei residui cercava ulteriori componenti produttivi: qui si prepara soltanto la diagnostica offline già specificata, senza inventare un nuovo sottosistema di prodotto.

Prosecuzione Codex autorizzata nelle Notes della mappa; stop massimo00:00 italiane del19settembre. Specifica, test RED/GREEN, revisione indipendente e documentazione delle prove finite sono richiesti. Nessun tracing, exec, spawn, segnale o osservatore OS nel nuovo modello; nessuna modifica ai driver, agli entitlement, ai record storici o al runtime/app.

## Progress — storico

Presa in carico dopo la consegna verificata del client servizi e della build con controllo SDK obbligatorio. [Piano esecutivo](../../../docs/superpowers/plans/2026-09-18-addon-bootstrap-abort-offline.md).

## Answer

Modello finito e valutatore sintetico implementati nei due nuovi file Python:31 test PASS, RED comportamentali archiviati, replay root e revisione indipendente PASS. Framing e memoria parziale limitati, deadline assoluta, stati terminali e rifiuto di osservazioni incoerenti verificati; tutti i flag di successo nativo rimangono false. [Guida riproducibile](../../../Prototypes/AddonPlatform/Tracing/BootstrapAbortModel.md) e [verifica completa](../../../docs/superpowers/verification/2026-09-18-addon-bootstrap-abort-offline.md).

Gli11 input originali della diagnostica/driver e i484 input consegnati dell’app sono invariati. Riavvio normale dell’app richiesto dal progetto verificato con PID96743, senza attribuirlo alla prova offline. Il ticket sui processi gestiti e il gate C0d restano aperti/chiusi rispettivamente: nessuna prova fisica, tracing, segnale o launcher è stato eseguito.
