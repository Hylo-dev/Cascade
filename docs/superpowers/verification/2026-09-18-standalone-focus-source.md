# Verifica dell’esempio sorgente StandaloneFocus — 18 settembre 2026

**PASS nel perimetro della libreria sorgente.** Implementato un provider indipendente con avvio, pausa, ripresa e fine, countdown dichiarativo, identità assegnata dall’host e un record persistente limitato. Ricreare il provider non azzera revisioni o ricevute. [Esempio e contratto d’integrazione](../../../Examples/StandaloneFocus/README.md).

## Evidenze finali

- Build della libreria fuori dal checkout riuscita; **37 test Swift Testing passati**, più casi parametrizzati/matrici interni. Il riepilogo XCTest di zero test non è il conteggio della suite Swift Testing.
- Dipendenze dirette esclusivamente CascadeAddonSDK/CascadeContracts; CascadePresentation è una dipendenza pubblica transitiva. Package configurato con un percorso SDK assoluto esplicito, senza fallback nascosto o repository remoto inventato. Nove file nuovi verificati contro la copia esterna.
- Revisione indipendente Codex Sol high **PASS**, dopo tre rilievi P2 e il completamento della correzione sulla cronologia non utilizzabile. Ogni errore di comportamento è stato riprodotto in un RED compilabile; fallimenti e handoff precedenti sono conservati.

Una richiesta valida rimane outcomeUnknown quando non si riesce a leggere o interpretare la cronologia autorevole. Un esito già recuperato da una ricevuta esatta rimane invece noto anche se fallisce la scrittura del successivo snapshot; nessuna pubblicazione candidata viene restituita. Campi sconosciuti anche nell’errore annidato di una ricevuta causano rifiuto dello stato e conservazione dei byte. La cronologia valida mantiene il controllo delle revisioni dopo l’espulsione delle ricevute più vecchie: nessuna promessa di memoria storica illimitata.

[Review con addendum finale](../../../.scratch/codex-addon/20260918-continuation/focus-independent-review.md), [handoff finale](../../../.scratch/codex-addon/20260918-continuation/focus-history-fix-handoff.md), [freeze e hash](../../../.scratch/codex-addon/20260918-continuation/focus-history-fix-frozen-handoff.json), [37 test](../../../.scratch/codex-addon/20260918-continuation/focus-history-fix-green.log), [build libreria](../../../.scratch/codex-addon/20260918-continuation/focus-history-fix-library-build.log). Correzioni precedenti: [prima tranche](../../../.scratch/codex-addon/20260918-continuation/focus-review-fix-handoff.md); [primo handoff storico](../../../.scratch/codex-addon/20260918-continuation/focus-handoff.md).

## Perimetro e seguito

Le prove iniziali usano il package SDK congelato di 62 input. La [consegna del client storage](2026-09-18-addon-storage-message-client.md) ha poi verificato nuovamente questo esempio contro i 64 input pubblici aggiornati in una copia completa del package, con tutti i test passati. La medesima consegna include build firmata dell’app e riavvio verificato; l’esempio resta una libreria sorgente.

Sono richiesti storage autorevole e un unico writer per assegnazione. Persistenza e ammissione dell’output non sono una transazione unica; un token persistito non prova l’ammissione della scadenza. Il refresh può riconciliare lo stato, senza garantire una callback perduta. Nessun eseguibile, contenitore firmato, servizio Focus reale, migrazione di un builtin, avvio addon o parità nativa è dichiarato verificato. C7/C12 completi, macOS 14 a runtime e gate C0d restano distinti e aperti.
