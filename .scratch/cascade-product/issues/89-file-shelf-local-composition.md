# Comporre la pagina locale e il drag in uscita per elemento

ID: 89
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 87, 88

## Question

Eseguire la fase C del [piano locale approvato](../../../docs/superpowers/plans/2026-09-26-local-file-shelf.md): collegare facade app, host, motore e renderer condiviso per mazzo quattro carte +N ed elenco animato persistenti. Accettare URL regolari in ingresso e rifiutare chiaramente promise in ingresso nella prima tranche. Provider nativi in uscita copiano per elemento; rimuovere solo dopo successo individuale, conservando originali e voci non consegnate. Converti resta disabilitato con spiegazione, senza capacità simulata. Test mirati e drag reali, review root e commit selettivo.

## Answer

Implementato in `e25e75c` e accettato dopo review e correzioni root: facade app, renderer condiviso, ingresso URL regolari, rifiuto visibile per ingressi non supportati, stato persistente degli errori parziali e uscita per elemento. Il completamento del drag da solo non prova una copia: solo il callback di scrittura riuscita della singola promise, anche tardivo, rimuove quella voce; originali e voci fallite restano. Converti è disabilitato con spiegazione. Test app firmati indipendenti root: 6/6 passati con override da riga di comando del team Apple Development (`root-local-app-tests-signed.log`); suite SwiftPM precedente 1.416/1.416 passata, renderer non modificato dopo. Build finale, riavvio e QA Finder restano nel ticket di consegna; launcher addon e conversione completa non sono qualificati.
