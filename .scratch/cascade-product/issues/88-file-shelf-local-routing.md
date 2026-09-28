# Instradare il ripiano locale e riconoscere il drag in ingresso

ID: 88
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 80, 87

## Question

Eseguire la fase B del [piano locale approvato](../../../docs/superpowers/plans/2026-09-26-local-file-shelf.md): slot di pagina dedicato nel motore, default all'apertura quando occupato e navigazione manuale preservata. `NSDraggingDestination` riconosce file correnti, batte una sola volta e mostra il bersaglio; testo, annullamento e pasteboard stantia non acquisiscono. Verificare cambio display/proprietario, chiusura e Riduci movimento. Nessuna attività fittizia, fallback Musica o apertura del launcher. Test mirati, review root e commit selettivo.

## Answer

Implementato in `ec14e70` e accettato dopo review root: slot contestuale dedicato, selezione predefinita del ripiano occupato senza cancellare la scelta manuale, riconoscimento del drag file e battito/preview finiti con gestione di annullamento e Riduci movimento. Verifica indipendente root: 71/71 test mirati passati (`root-task88-tests.log`). Il filtro combinato ha passato 139/140 test; l'unico errore è il test intermittente preesistente del drag già documentato, quindi la suite combinata non è dichiarata verde. Composizione app, consegna in uscita e QA nel notch reale seguono nei ticket locali; nessuna qualifica del launcher addon.
