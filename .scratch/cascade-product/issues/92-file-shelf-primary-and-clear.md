# Rendere il ripiano la pagina principale e semplificarne le carte

ID: 92
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 89

## Question

Revisione esplicita del 27 settembre: trattare il ripiano come una live activity. Finché occupato è la pagina principale, ma **non forza il notch aperto**. Dimensioni entro il notch standard e il riferimento Musica; utilizzare lo spazio superiore laterale lasciando libero il centro fisico. Impeccable e Taste guidano il design nativo, con bagliori contenuti e colore del notch.

Il drop mostra una grande icona centrale e un titolo centrato sotto. Dopo un'aggiunta riuscita compare il primo file al centro, scivola a sinistra e apre il ventaglio di massimo quattro icone senza sfondo. Click o scroll a due dita distendono il mazzo in un elenco **orizzontale**: i pulsanti Converti/Svuota scompaiono e una freccia riporta alla vista del mazzo. Converti e Svuota restano sovrapposti nella vista del mazzo; gli originali non vengono cancellati.

Accettazione: nessuna apertura permanente al ripristino; riapertura sul ripiano mentre occupato; ritorno ordinario solo a svuotamento. Layout entro la misura standard con esclusione del taglio, nome sotto ogni icona, transizioni interrotte/cancellate in modo sicuro e alternativa con Riduci movimento. Conservare drag in uscita e controlli accessibili. Test, review root, build firmata e riavvio; distinguere preview renderizzate da prova Finder reale. La correzione del drag rapido prima dell'animazione è tracciata nel ticket 91. Nessuna attivazione anticipata di Converti o modifica al launcher.

Questa richiesta sostituisce la precedente apertura permanente e i pulsanti nell'elenco. Le verifiche seguenti descrivono la build precedente, non qualificano il nuovo design.

## Avanzamento — implementazione verificata, prova manuale pendente

La parte app/renderer è stata revisionata dal root: sette test app e un test renderer passati. L'integrazione finale è in `5d852e7`; review root dei dodici file di codice e correzioni di ownership asincrona, cache pagina e preview concluse. Test app firmati indipendenti 7/7 (`root-shelf-clear-app-tests.log`), suite SwiftPM 1.443/1.443 (`root-receiver-persistent-tests.log`) e build firmata exit 0 (`root-receiver-persistent-build.log`). I test verificano che Svuota conservi gli originali; il manifest conserva una voce dopo il riavvio al PID 74874. Screenshot CUA della finestra ricevente trasparente non prova la resa del ripiano: pagina principale, Svuota, carte e animazioni attendono conferma manuale dell'utente sulla build finale. Ticket aperto/non assegnato per QA nativa, distinto dalla [regressione del drag in ingresso](91-file-shelf-native-drop-regression.md).

## Redesign — 27 settembre

Implementato in `48e682c`, con review e correzioni root. Misura standard 440×144 pt, contenuto 400×124 pt; pagina prioritaria ma richiudibile, glow nativo, drop centrato, ingresso in due fasi e fila orizzontale con freccia di ritorno. Preview del renderer esaminate, inclusi overflow e Riduci movimento; test finali 1.447/1.447 e app 9/9, build firmata e riavvio PID 97319 verificati. [Dettagli e limiti della verifica](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md). Regole permanenti in PRODUCT.md. La prova nel notch fisico resta pendente per il limite CUA e il ticket rimane aperto/non assegnato.

## Rifinitura ventaglio e preview — 27 settembre

Icone Finder sovrapposte con passo 16 pt e rotazioni +4/−4/−8/−12°. Il gesto di apertura memorizza la direzione inversa; il ritorno esegue la stessa azione della freccia. Lo scorrimento orizzontale sfoglia fino all’inizio prima di richiudere; momentum e coda della gesture precedente non navigano. Preview nativa `FileShelfDesignPreview.swift`, Canvas «Ripiano», dati solo in memoria e controlli 0/1/4/8 file, ingresso e Riduci movimento.

Review root e correzioni completate: routing comune, isolamento Swift dei tipi puri, compilazione del corpo della preview e contrasto sul fondo scuro. Test renderer 8/8 e app 12/12; build firmata riuscita e riavvio verificato PID 5063. La preview compila, ma il Canvas non è stato eseguito: Xcode richiede l’installazione iniziale dei componenti di sistema. Prova del trackpad fisico pendente; ticket aperto per QA nativa. [Verifica dettagliata](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).

## Interazioni e azioni colorate — 27 settembre

Nuova richiesta implementata: primo file a 1,75°, icone native più grandi (68 pt nel mazzo, 60 pt nell’elenco), nessun nome nel mazzo e +N sotto. Testi «converti», «rename», «svuota» a destra con blu/arancio/rosso e bagliori; in lista si raccolgono come icone nella spalla superiore destra, sostituendo la precedente decisione di nasconderli. Il notch resta entro le misure standard.

Scroll orizzontale a passi di focus; clic toggle e Shift per intervalli, frecce/Shift+frecce e Cmd+A nella pagina visibile. Delete rimuove i selezionati o il file a fuoco, preservando gli originali; dissolvenza a frammenti, compreso l’ultimo file, con alternativa Riduci movimento. Il focus tastiera viene acquisito solo interagendo coi file e mantenuto da un contenitore stabile fino all’uscita dal ripiano.

Drag dal mazzo: tutti i file, anche oltre le prime dodici voci. Dalla lista: selezionati; trascinare una voce non selezionata la seleziona prima del drag. Nessuna rimozione al semplice avvio/cancellazione del drag: i receipt del runtime rimuovono solo i file copiati con successo. La risposta esplicita dell’utente autorizza «rename» anche sull’originale Finder: rinomina singola, collisioni senza sovrascrittura, bookmark e nome aggiornati, rollback prima del commit se il salvataggio fallisce.

Review root con correzioni di clipping, focus nativo, selezione aggiornata al drag, paginazione, metadata a ID invariato e durata della dissolvenza finale. Suite SwiftPM 1.452/1.452 e test app 17/17 passati; preview aggiornate e verificate. Build/riavvio finali e limiti nella [verifica runtime](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md). Il ticket resta aperto per QA fisica nel notch.
