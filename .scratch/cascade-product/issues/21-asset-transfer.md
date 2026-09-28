# Scegliere il trasferimento delle immagini tra addon e host

ID: 21
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: codex-wayfinder-sync
Blocked by: none

## Question

Trasferire le immagini compresse in blocchi tramite messaggi, oppure introdurre una capacità nativa separata per grandi buffer? La scelta deve conservare i limiti approvati di immagini, messaggi, memoria e privacy, riusando le librerie disponibili.

## Answer

Risoluzione del 14 settembre 2026, basata sulla risposta esplicita dell'utente: «vanno bene i blocchi tramite messaggi» alla proposta di blocchi da 64 KiB.

Si adotta il trasferimento a blocchi da 64 KiB sul percorso dei messaggi, riusando Foundation. Restano i limiti già approvati: immagini compresse fino a 1 MiB / 1.000.000 pixel e messaggi ordinari fino a 512 KiB. L'alternativa dei grandi buffer nativi dedicati non è selezionata. Il documento di [analisi delle alternative](../../../docs/superpowers/plans/2026-09-13-addon-asset-transfer-decision.md) conserva il razionale e i vincoli da sviluppare nel piano esecutivo.

La decisione riguarda il meccanismo. Sono ora implementati e revisionati i frame dedicati e la primitiva interna di assemblaggio con quote protette e scadenza; il collegamento al trasporto autenticato e al client SDK resta da eseguire. Le evidenze finali sono nel [rapporto del componente](../../../docs/superpowers/verification/2026-09-14-addon-asset-chunks.md). Non modifica la qualificazione del launcher né il gate C0d. Il prerequisito host/SDK è consegnato nella [verifica del ciclo storage SDK](../../../docs/superpowers/verification/2026-09-13-addon-sdk-storage-lifecycle.md).

Il ticket è chiuso perché la scelta dell'utente è acquisita, non perché il trasferimento sia già operativo. Nessuna nuova scelta è stata attribuita all'utente durante il riallineamento della mappa.
