# Creare l’esempio Focus con il solo SDK pubblico

ID: 26
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 24

## Question

Creare una libreria sorgente indipendente Focus con countdown dichiarativo, azioni correlate, revisioni e stato persistente usando esclusivamente i prodotti SDK pubblici. Verificare ricreazione del provider senza dichiarare già qualificato il contenitore nativo.

## Context

Incremento C7/C12 autorizzato dalla prosecuzione del18settembre. [Piano](../../../docs/superpowers/plans/2026-09-18-standalone-focus-source.md). Nessun builtin Focus verificato da migrare; comportamento d’esempio dichiarato. Parità e controllo dei processi reali restano aperti.

## Progress

Disegno esaminato; implementazione e verifiche in corso.

Revisione indipendente sul primo handoff: [tre correzioni P2 richieste](../../codex-addon/20260918-continuation/focus-independent-review.md), relative a esiti delle ricevute con storage indisponibile o snapshot incerto e chiusura dello schema degli errori persistiti.31test precedenti passati non chiudono questi casi; implementer riattivato per regressioni e correzioni. Consegna non ancora approvata.

## Answer

Libreria sorgente indipendente implementata e revisionata PASS dopo la risoluzione di tutti i rilievi.37test passati e build esterna riuscita, dipendenze soltanto SDK pubbliche. Persistenza, revisioni e ricevute verificate anche con cronologia non utilizzabile e commit incerti. [Verifica finale e limiti](../../../docs/superpowers/verification/2026-09-18-standalone-focus-source.md). La qualifica del contenitore nativo e la parità C7/C12 restano aperte.
