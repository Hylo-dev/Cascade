# Correggere l'acquisizione file nel drag nativo del ripiano

ID: 91
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 88, 89

## Question

Correggere la regressione osservata dall'utente nella build locale del ripiano: trascinando file sotto il bordo del notch si vedono battito e apertura; al rilascio si sente il suono di rilascio, ma nessun file viene ammesso. Il suono non identifica la causa. Il selettore Ripiano/Attività è stato rimosso su richiesta dell'utente; non reintrodurlo. Verificare una superficie di drop più ampia solo durante il drag, il ciclo nativo di `NSDraggingDestination` fino al rilascio e una guardia circoscritta per Mission Control, senza catturare click ordinari o mutare la logica di consegna in uscita.

Accettazione: file URL validi rilasciati nell'area visibile entrano una volta nel ripiano; uscita, annullamento, testo, pasteboard stantia e drag non-file non creano voci. La pagina ordinaria e la navigazione manuale del motore restano disponibili tramite le API pubbliche. Test mirati, review root e prova nativa Finder dopo build firmata/riavvio. La sola heartbeat/apertura o un test sintetico non provano l'acquisizione; [la verifica finale](90-file-shelf-local-delivery.md) resta aperta fino alle prove complete. Nessun allentamento del launcher addon.

## Avanzamento — prova nativa ancora pendente

Review root della correzione sorgente `5718621` superata dopo i fix richiesti: hold nativo distinto dalla preview, hit testing dell'area di ingresso sull'intera altezza espansa con refresh dopo cambio pagina, registrazione opt-in, uscita stantia e pulizia della sorgente. Guardia Mission Control su Quartz pubblico limitata alla banda orizzontale del ripiano, con arretramento verticale di 2 punti dal bordo superiore, dopo la validazione degli URL file regolari; se il permesso necessario manca, fallisce aperta senza prompt. Questa è una misura circoscritta, non una garanzia di comportamento su macOS 27 senza prova nativa.

Test mirati agente 26/26 passati. Verifica indipendente root `swift test --package-path CascadeKit --no-parallel`: exit 0, 1.427/1.427 (885 runtime, 122 presentazione/SDK, 301 CascadeKit, 102 contratti, 17 CLI), log `.superpowers/sdd/2026-09-26-file-shelf/root-drag-regression-tests.log`. Build root della correzione `BUILD SUCCEEDED`, exit 0 (`root-drag-regression-build.log`); confini SDK, firma e collegamento Applications verificati. Dopo Quit CUA, assenza del vecchio processo confermata con `pgrep` exit 1; app riaperta via CUA dal collegamento Applications, PID 59537, avvio 26 settembre 2026 ore 21:36:32, eseguibile `/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade` aggiornato alle 21:36:01.

La prova Finder via CUA ripete ScreenCaptureKit `-3811` (cattura audio/video). È stata chiesta conferma manuale all'utente sulla nuova build; drag Finder, rilascio effettivo e Mission Control restano da osservare prima di risolvere il ticket. Ticket rilasciato aperto/non assegnato in attesa della prova, senza dichiarazione di successo nativo.
