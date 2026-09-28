# Verificare la gestione della durata tramite launchd

ID: 68
Parent: cascade-product
Type: research
Labels: wayfinder:research
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

La pista launchd/ServiceManagement lasciata aperta nell’indagine del18settembre offre un vincolo verificabile dalla creazione del bootstrap fino all’uscita dopo la perdita del supervisore/host, sotto i requisiti già approvati? Controllare fonti Apple correnti e sorgenti primari, distinguendo process-group cleanup, possibilità di uscire dal gruppo, identità e durata del job. Nessuna installazione di job, avvio di provider/prototipi, modifica a entitlement o gate, né nuova eccezione. Produrre soltanto un esito documentato che alimenti la prova dei processi gestiti.

## Contesto

La [decisione di mantenere il launcher bloccato](22-managed-process-exit-proof.md) resta vincolante. La continuazione dell’utente autorizza questa ricerca tecnica, senza riaprire la policy. [Indagine precedente](../../codex-addon/20260918-continuation/managed-process-design.md).

## Answer

Ricerca Sol medium e verifica root concluse: i contratti pubblici esaminati non stabiliscono la garanzia richiesta. La registrazione ServiceManagement persiste oltre l’app, mentre il cleanup launchd riguarda il gruppo al decesso del job; appartenenza non dimostrata inescapabile e uscita fisica non provata. [Rapporto con fonti e limiti](../../../docs/wayfinder/research/2026-09-23-launchd-managed-lifetime.md). Nessuna prova nativa o modifica al prodotto. Il ticket della prova dei processi gestiti resta aperto; launcher bloccato, nessuna nuova scelta di policy richiesta.
