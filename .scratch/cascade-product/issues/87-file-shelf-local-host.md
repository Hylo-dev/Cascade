# Preparare l'host locale e le copie verificate del ripiano

ID: 87
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 78

## Question

Eseguire la fase A del [piano locale approvato](../../../docs/superpowers/plans/2026-09-26-local-file-shelf.md): un solo host/store/governor, snapshot 12 di default e massimo wire 32, add/remove/relink con ID stabili, preparazione opaca per elemento senza pin anticipato, copia FD verificata con creazione esclusiva senza overwrite e `fsync`. Persistenza e ricevuta precedono la rimozione della sola voce consegnata; originali, errori e annullamenti conservati. Test mirati, review root e commit selettivo. L'eccezione è solo per la pagina locale: grant, quote e gate addon non cambiano.

## Answer

Implementato in `a0508ef` e accettato dopo review e correzioni root: facade con store/governor condivisi, snapshot limitati, ID conservati, capability per voce/generazione, copia controllata senza overwrite e ricevuta solo dopo copia completata. La review ha verificato pulizia su annullamento, concorrenza, metadati, vita condivisa e gate della preview. Verifica indipendente root: 73 test passati (53 runtime, 9 presentazione, 11 contratti), log `.superpowers/sdd/2026-09-26-file-shelf/root-task87-tests.log`. Non costituisce ancora consegna app: pagina, drag e QA nativa seguono nei ticket locali successivi; launcher addon e gate nativo restano invariati.
