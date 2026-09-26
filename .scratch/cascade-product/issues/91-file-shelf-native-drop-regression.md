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

La prova Finder via CUA ripete ScreenCaptureKit `-3811` (cattura audio/video). La successiva prova manuale dell'utente sulla build `5718621`/PID 59537 ha ancora fallito acquisizione e Mission Control; l'area ampliata migliora però l'uso. Il log osservato contiene soltanto `phase begin`, senza `hover`, `drop` o `edgeGuard`; nello store risultano zero file persistenti. Questo restringe la diagnosi senza stabilire la causa: restano possibili eleggibilità tardiva della finestra e guardia silenziosa.

Una patch diagnostica limitata a tre sorgenti aggiunge log `.notice` una volta per readiness, entered, updated, panelReady, intakeReady e mouseUp; non è dichiarata una nuova correzione funzionale. Review root, compilazione target e build root exit 0 (`root-drag-diagnostic-build.log`) passate; collegamento Applications aggiornato e app riavviata al PID 61289 il 26 settembre 2026 alle 21:46:11. Readiness osservata: `enabled=true`, `registered=3`, `windowAttached=true`. Prima cattura salvata in `/private/tmp/cascade-file-drop-diagnostic.log`; stream terminato. I nuovi eventi `.notice` restano recuperabili dal log unificato.

La prova manuale «fatto» sul PID 61289 produce alle 21:56:24.969 `begin` con `panelReady` e `ignored=true`, `pointerInsidePanel=false`, `intake=false`; alle 21:56:25.579 `intakeWindowReady` con `ignoredPreviously=true`, `pointerInsidePanel=true`, `intake=true`. Al `mouseUp` delle 21:56:27.859 `nativeHoverHeld=false`. La seconda prova alle 21:56:29–30 mostra la stessa sequenza. Nessun `nativeEntered` o `rawUpdated`, nessuna consegna. L'attivazione tardiva della finestra è un candidato prossimo, non una causa dimostrata.

La cattura diagnostica senza `nativeEntered`/`rawUpdated` prima delle guardie esclude il parser silenzioso in quella cattura; l'eleggibilità tardiva della finestra resta un'ipotesi da provare, non una causa accertata. La nuova correzione `c43b7af` anticipa l'abilitazione del pannello a ogni gesto file riconosciuto; solo la consegna nativa `NSDraggingInfo` ammette voci. Il suggerimento globale stabile di 1–32 URL regolari serve soltanto alla UI precoce e alla guardia Mission Control, mai alla lettura/copia dei file. Il fallback di hover nativo resta attivo durante l'apertura; il `mouseUp` fisico impedisce l'armamento tardivo, e il rientro nello stesso gesto resta coperto dai test.

Review root PASS. Test mirati agente: 10/10 più 4/4 helper. Verifica indipendente root `swift test --package-path CascadeKit --no-parallel`: exit 0, 1.435/1.435 (885 runtime, 122 presentazione/SDK, 309 CascadeKit, 102 contratti, 17 CLI), log `root-early-intake-tests.log`. Build firmata `BUILD SUCCEEDED`, exit 0 (`root-early-intake-build.log`), confini SDK, codesign e collegamento Applications verificati. Dopo Quit CUA il vecchio processo è assente (`pgrep` exit 1); la nuova app è stata riaperta al PID 65199 il 26 settembre 2026 alle 22:14:03 dal binario `CascadeFileShelf/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade`. Readiness del nuovo processo alle 22:14:03: `enabled=true`, `registered=3`, `windowAttached=true`.

Limite noto: durante un drag di file la candidatura temporanea usa l'intera fascia superiore e può coprire altri bersagli di drop della barra menu; il normale mouse non cambia. La prova utente dopo questo riavvio è stata richiesta ed è pendente. Il ticket torna aperto/non assegnato; nessuna qualifica dell'ingresso o di Mission Control senza prova nativa. Ultima quota settimanale osservata: 8% usata, 92% residua.
