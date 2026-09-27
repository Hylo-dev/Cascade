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
