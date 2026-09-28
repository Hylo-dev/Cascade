# Verificare i confini pubblici dell'SDK e degli esempi

ID: 35
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 24, 26, 27

## Question

Implementare il boundary check previsto dal piano addon: verificare il grafo dei target pubblici SDK e gli import Swift degli esempi, rifiutando dipendenze dai moduli privati dell'host senza alterare il runtime.

## Context

Controllo previsto in C6/C12 del [piano di completamento](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md). I target pubblici esistenti sono CascadeAddonSDK, CascadeContracts e CascadePresentation; Runtime, CascadeKit e il tool host restano fuori da questa superficie. Gli esempi mantengono la dipendenza pubblica locale esplicita già approvata.

## Progress

Presa in carico dal task principale, in una directory temporanea isolata e con cache dedicate. Nessuna modifica dei sorgenti o delle cache posseduti dal worker delle sottoscrizioni. Il controllo userà i manifest valutati da SwiftPM e l'albero sintattico Swift; non sostituisce compilazione, sandbox o prove di parità nativa.

### Verifica isolata e revisione

Implementazione corretta congelata:20 test Python/parser/SwiftPM/CLI PASS; baseline immutabile3 package/9 target/85 sorgenti/126 import PASS. La revisione indipendente finale è PASS dopo quattro correzioni, documentate nella [verifica](../../../docs/superpowers/verification/2026-09-18-addon-sdk-boundary-check.md). I quattro script sono stati importati esattamente e il controllo del checkout con il client completo passa:3 package/9 target/88 sorgenti/132 import. Le verifiche del perimetro sorgente sono completate; la consegna app delle sottoscrizioni resta distinta. Il controllo è eseguibile esplicitamente; l’integrazione obbligatoria nello script di build è ancora un incremento distinto. Nessuna qualifica nativa dedotta.

## Answer

Controllo sorgente consegnato: quattro script importati esattamente,20 test con parser/SwiftPM reali e revisione indipendente PASS. L’ultimo audit del checkout corretto passa su3 package/9 target/88 sorgenti/132 import, senza variazioni dei483 input congelati. [Prove e limiti](../../../docs/superpowers/verification/2026-09-18-addon-sdk-boundary-check.md). Il perimetro di questo ticket non modifica codice app e non richiede un nuovo launcher: la consegna app delle sottoscrizioni prosegue separatamente. Il [collegamento obbligatorio alla build](37-required-sdk-build-check.md) resta un incremento distinto; C6/C12 e parità nativa non sono completati.
