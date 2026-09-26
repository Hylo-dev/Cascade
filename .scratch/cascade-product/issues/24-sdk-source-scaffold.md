# Generare un progetto addon SDK compilabile

ID: 24
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 23

## Question

Completare il comando `cascade-addon init` con un progetto sorgente compilabile basato esclusivamente sui prodotti pubblici SDK, manifest validato, identità fornita dallo sviluppatore e protezione dei file esistenti. Verificare la compilazione indipendente senza dichiarare il pacchetto già installabile o il launcher qualificato.

## Context

La richiesta del 18 settembre di continuare il lavoro addon fino al limite Codex estende la prosecuzione alle tranche residue del piano approvato. Questo incremento C12 può procedere prima di C0/C1: [piano implementativo](../../../docs/superpowers/plans/2026-09-18-addon-sdk-scaffold.md). [Avanzamento Codex](../../codex-addon/20260918-continuation/plan.md).

## Progress

18 settembre: preso in carico, implementer Codex Sol high. Destinazione nuova, identificatore e SDK espliciti; pubblicazione atomica senza sovrascrittura; esempio provider e test da compilare esternamente. Revisione e consegna ancora da eseguire.

## Answer

Generatore sorgente implementato e revisionato PASS: manifest, provider e test basati sui prodotti SDK pubblici; percorsi espliciti, destinazione nuova e pubblicazione senza sostituzione.17 test mirati,5 test del progetto indipendente e896 test / 84 suite completi passati. Build firmata e riavvio verificati. [Consegna e limiti](../../../docs/superpowers/verification/2026-09-18-addon-sdk-scaffold.md). Il formato distribuibile, il bootstrap e la parità nativa restano aperti.
