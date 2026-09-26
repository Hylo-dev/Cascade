# Disegnare stati e superfici del notch

ID: 07
Parent: cascade-product
Type: prototype
Labels: wayfinder:prototype
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 03, 04

## Question

Quali presentazioni e transizioni definiscono notch a riposo, compatto sui lati, attività espansa, pagina widget, notifica, ricerca e impostazioni? Produrre un prototipo economico per concordare nero e glass, allineamento fisico, sporgenza sui display senza notch e feedback aptico dopo l'apertura. Rendere preciso il riferimento alla Dynamic Island: attività contemporanee, lati occupati e passaggio dal compatto all'espanso. Il prototipo è un supporto alla decisione, non codice di produzione.

## Ricognizione e scelta residua — 20 settembre 2026

La policy pubblica è risolta. Il [confronto delle superfici e della ricerca](../../../docs/wayfinder/context/2026-09-20-notch-surfaces-checkpoint.md) separa i contratti già approvati dalla scelta visibile ancora necessaria: accettare nella prima tranche il campo originale di Spotlight con dimensioni proprie, oppure richiedere subito un campo ridisegnato dentro il notch. È raccomandata la prima tranche nativa, coerente con la preferenza già espressa per il vero Spotlight. Non si chiede nuovamente la policy delle API.

La ricognizione corregge anche la lettura del requisito aptico storico: la specifica approvata del 4 settembre lo colloca all'inizio dell'hover. Nero/glass, attività compatte e avvisi hanno già contratti implementati e non devono essere ridisegnati da zero. Nessun prototipo nuovo o uso live di Spotlight è dichiarato; il documento è una preparazione alla decisione, e il ticket resta aperto.

## Decisione dell’utente — 20 settembre 2026

«Sì esatto»: approvata per la prima tranche la ricerca con il campo originale di Spotlight e le sue dimensioni native. La scelta sul risultato visibile è risolta. Il seguito è il prototipo di raccordo e ripristino già proposto, conservando input e risultati di sistema; nessuna nuova API privata approvata. La verifica locale e le restanti superfici mantengono aperto questo ticket.

## Riallineamento del codice e pausa

La ricognizione successiva alla conferma ha trovato l’integrazione Spotlight già implementata e documentata nel [piano del9settembre](../../../docs/superpowers/plans/2026-09-09-spotlight-droplet.md): la precedente descrizione «solo prova locale» era incompleta e non va usata per duplicare il coordinatore. Riconfermati oggi i check handoff/scorciatoia/cancellazione AX e i6 comportamenti droplet. Nessuna modifica al codice app.

La [revisione del ripristino](../../codex-addon/20260920-spotlight-native/restore-review.md) identifica una perdita dello stato originale quando stop non trova una finestra o il move fallisce; la frequenza e l’effetto reale richiedono una prova nativa, non superata oggi. La proposta di anticipare il restore a clearTarget deve ancora essere valutata dal root rispetto agli usi di clearTarget durante la decisione dopo Escape: non è una correzione approvata.

[Esiti e limite dello strumento UI](../../codex-addon/20260920-spotlight-native/checks.json). Nessun nuovo prototipo, build app o riavvio effettuato in questa prosecuzione; il processo locale esistente è stato verificato al PID34140. Dopo il messaggio ambiguo «sett» sono sospese ulteriori azioni UI in attesa di chiarimento. Agente chiuso, claim rilasciato, ticket aperto.

## Ripresa dopo il refuso

L’utente chiarisce «un refuso, continua». Ripresa la verifica dell’integrazione esistente. La build puntata da Applications è stata trovata rimossa dal filesystem (il vecchio processo continua a esistere); è in corso la ricompilazione tramite script ufficiale prima della prova UI. La cancellazione della build non viene attribuita senza evidenze a una causa specifica. Nessun nuovo codice Spotlight ancora scritto.

## Impedimento di consegna — 20 settembre 2026

La ripresa incontra un input non disponibile localmente: Config/Cascade-Info.plist (378byte, SF_DATALESS) va in timeout in lettura. Il download tramite API pubblica Foundation è stato richiesto con successo, ma il contenuto non è arrivato. Xcode attendeva la lettura coordinata; il processo della build è stato fermato dal root con SIGTERM (exit143), senza modificare servizi iCloud. Nessun errore di compilazione viene dedotto dall’attesa.

Preparata una copia temporanea dei sorgenti locali con hash identici; manca soltanto il plist, la cui copia vuota prodotta dal timeout è stata rimossa. [Checkpoint e istruzioni di ripresa](../../codex-addon/20260920-spotlight-native/checkpoint.json). Materializzare il file originale prima di eseguire la build; non sintetizzarlo né sostituire il checkout. La build precedente in DerivedData è stata rimossa da una causa non determinata: /Applications/Cascade.app rimane un link verso un target mancante. Nessun riavvio eseguito: si conserva il processo già attivo.

La [valutazione root](../../codex-addon/20260920-spotlight-native/root-restore-review.md) non adotta il restore generalizzato in clearTarget; la qualifica del ciclo nativo resta aperta. I check preesistenti passano, nessun nuovo codice app e nessun agente attivo. Claim rilasciato in attesa del file.

## Ripresa dopo disponibilità del file

L’utente conferma il download del plist, ora leggibile e valido. La precedente copia temporanea non è più disponibile: ricreata da451 input verificati del checkout, senza modifiche al codice.

Build ufficiale completata con exit0 dalla copia locale verificata; firma Apple Development valida e collegamento Applications aggiornato. Riavvio normale tramite UI verificato: PID3835→3923, nuovo processo ancora attivo al controllo successivo. I451 input sono rimasti identici al checkout. [Consegna aggiornata](../../codex-addon/20260920-spotlight-native/delivery-resumed.json).

La ricognizione Terra e la [valutazione root](../../codex-addon/20260920-spotlight-native/root-surface-review.md) confermano l’esistenza delle impostazioni oltre all’integrazione Spotlight; corretto il contesto che chiedeva prototipi duplicati. Nessuna nuova modifica al codice app. Il controllo UI, recuperato dopo errori di avvio, espone per Campo la finestra delle conversazioni Siri e non il campo Spotlight; la scorciatoia delle impostazioni non cambia l’albero accessibile. Non è una prova negativa delle funzioni, ma impedisce di qualificarle con quel percorso. Richiesta all’utente la possibilità di usare CLI/AppleScript come metodo alternativo, imposta dalle istruzioni dello strumento UI; nessuna modifica a permessi o preferenze.

Claim rilasciato in attesa della risposta sul metodo alternativo. Nessun agente o build in esecuzione.27 ticket risolti su44; nessuna nuova chiusura. Consumo settimanale osservato5%, tetto20%.

L’utente autorizza CLI e AppleScript per completare le prove. Ripreso il claim; autorizzazione persistente per questi controlli, senza cambiare preferenze o permessi.

## Prova CLI e AppleScript

Verificata la finestra impostazioni `cascade.settings`:760×570 a(355,152), sidebar e controlli visibili, focus sul controllo `settings.size`. Il campo Spotlight nativo è stato individuato con identità `SpotlightSearchField`,520×87 a(475,65). La preferenza `spotlightEnabled` letta dal dominio dell’app è0: il toggle «Spotlight dal notch» esiste, mentre il distinto comando «Apri Spotlight dal notch» non compare con integrazione disattivata. Nessuna preferenza modificata. La prova del calcolo non è qualificata: i tentativi delimitati non hanno mantenuto il campo osservabile e non hanno inserito query.

[Evidenza parziale](../../codex-addon/20260920-spotlight-native/native-qualification-partial.json). Richiesta l’attivazione temporanea del toggle per verificare il raccordo e il ripristino, con ritorno allo stato iniziale; risposta ancora pendente. Il seguito dell’utente chiede di chiarire lo scopo del ticket: è progettazione/qualifica delle superfici, non una nuova tranche del motore addon. Nessuna chiusura globale dedotta dalla verifica delle impostazioni.

Riavvio normale conclusivo verificato PID7661→8144, firma valida e stabilità5s: [evidenza](../../codex-addon/20260920-spotlight-native/restart-evidence.json). Nessun agente attivo o codice app modificato. Claim rilasciato durante il chiarimento.

L’utente conferma «ok, continua» dopo il chiarimento. Ripresa la prova temporanea del toggle con ripristino dello stato iniziale, nuovamente osservato disattivato. Claim ripreso; launcher invariato.

## Answer

Le superfici della prima tranche sono definite dai contratti già approvati: riposo e chrome, hover con aptica all’ingresso, attività primaria compatta e seconda nel cerchio, apertura estesa e pagina widget, avvisi sulle ali, nero/glass e Reduce Motion. Il [riferimento consolidato](../../../docs/wayfinder/context/2026-09-20-notch-surfaces-checkpoint.md) collega le fonti. La scelta residua della ricerca è risolta dalla conferma dell’utente: vero Spotlight, campo e risultati originali con dimensioni native; nessuna nuova API privata. Le impostazioni conservano il linguaggio macOS e la posizione sotto il notch richiesti. Gli inventari funzionali rimangono nei propri ticket.

La [verifica locale](../../../docs/superpowers/verification/2026-09-20-spotlight-native-continuation.md) osserva campo520×87 con focus, calcolo nativo2+2=4 via AX, ripristino della posizione sia con campo aperto sia dopo chiusura/disattivazione/riapertura, oltre a geometria e focus delle impostazioni. Non riprodotto il difetto utente ipotizzato; nessuna modifica al codice app giustificata. Toggle ripristinato disattivato e riavvio verificato PID10620.

Revisione Terra valutata dal root: [rapporto](../../codex-addon/20260920-spotlight-native/ticket-closure-review.md). Accolta la chiusura come decisione/prototipo sulla base delle approvazioni, non della sola esistenza del codice. Tastiera/IME, VoiceOver, drag continuo, matrici display/OS e prestazioni restano qualifiche distinte, conservate nel rapporto di verifica e nei ticket di ricerca/interazione; questa chiusura non ne dichiara il PASS. Launcher invariato.

La proposta del reviewer di rimettere in discussione coda/timeout degli avvisi non è adottata: i contratti correnti scartano gli avvisi ricevuti durante espansione/blocco, senza riproporli. La decisione successiva riguarda l’arbitraggio tra intenzioni manuali e schermate contestuali.
