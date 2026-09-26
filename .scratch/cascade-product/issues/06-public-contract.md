# Definire i contratti di widget e Live Activity

ID: 06
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 05

## Question

Quali contratti pubblici distinguono widget, istanza, contenuto compatto dell'attività, espansione, azioni e sorgente di dati? Definire versionamento e capability negotiation, dimensioni supportate, disponibilità, lifecycle della UI separato dalle attività in corso, aggiornamenti e comandi, identità dell'app sorgente e comportamento con estensione assente o non compatibile. Stabilire cosa rimane del NotchWidget esistente e cosa richiede un contratto distinto, senza vincolare un trasporto non ancora scelto.

## Avanzamento del 9 settembre 2026

Approvati SDK comune, descrizioni componibili in Swift e renderizzate con SwiftUI, pubblicazioni indipendenti dalla connessione, azioni tipizzate, REQUIRES per feature e scene remote per UI avanzata. NotchWidget e i protocolli di attività diventano il confine interno del bridge; tutti i futuri widget del team usano l'API addon pubblica.

[P1](../../../docs/superpowers/plans/2026-09-09-addon-runtime-01-contracts.md) definisce tipi, schema, resolver e renderer; [P3](../../../docs/superpowers/plans/2026-09-09-addon-runtime-03-adoption.md) migra i moduli del team. Il ticket resta aperto per stabilizzare le API sulle prove del launcher e dei consumatori reali; i contratti proposti non sono dichiarati già implementati.

## Riallineamento del 14 settembre 2026

I contratti non sono più soltanto proposti: Contracts, SDK di base, resolver, pubblicazioni, azioni e servizi hanno implementazioni e test. L'host interno dispone anche di ammissione e risposta storage autenticate; il nuovo componente SDK correla una sola richiesta pendente e gestisce cancellazione, risposte tardive e chiusura. Riferimenti: [handler host](../../../docs/superpowers/verification/2026-09-13-addon-authenticated-storage-handler.md), [ciclo SDK](../../../docs/superpowers/verification/2026-09-13-addon-sdk-storage-lifecycle.md).

La condivisione di immagini è stata approvata e implementata con alias indipendenti sullo stesso raster e partizioni controllate dall'host: [verifica della condivisione](../../../docs/superpowers/verification/2026-09-13-addon-asset-sharing.md). I frame dedicati e l’assemblatore interno sono implementati e revisionati; resta il collegamento al canale autenticato e al client concreto: [componente asset a blocchi](../../../docs/superpowers/verification/2026-09-14-addon-asset-chunks.md). La scelta del meccanismo di trasferimento è registrata separatamente in [Scegliere il trasferimento delle immagini tra addon e host](21-asset-transfer.md).

Il ticket resta aperto per la stabilizzazione sul canale autenticato reale, i client SDK concreti, i consumatori reali e la migrazione dei widget. Un contratto o un componente interno verificato non costituisce da solo un addon esterno operativo.
