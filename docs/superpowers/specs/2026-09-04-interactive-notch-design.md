# Notch interattivo: aptica, Bluetooth e base Live Activities

Stato: impostazione confermata dall'utente il 4 settembre 2026, con aptica all'inizio dell'hover. Accessibilità e integrazioni private ammesse con verifica delle capacità.

## Obiettivo della prima tranche

Rendere utilizzabili i controlli nel notch, aggiungere un impulso aptico all'inizio dell'hover e presentare gli eventi di collegamento Bluetooth. Introdurre il contratto e le superfici per attività persistenti, iniziando dalla predisposizione per musica e media. Conservare macOS 14 come minimo e il motore AppKit/Core Animation esistente.

La sostituzione degli avvisi Bluetooth nativi è un requisito esplicito. Il rilevamento di una connessione e la soppressione dell'avviso di macOS sono capacità separate: entrambe richiedono verifica, e il funzionamento della prima non dimostra il funzionamento della seconda.

## Riscontri sul progetto

- `NotchEngine` è il confine pubblico del package `CascadeKit`; i servizi delle integrazioni possono restare nell'app, con dipendenze iniettate attraverso protocolli.
- `NotchController` coordina hover, display, stato e molle. Le variazioni per frame non invalidano SwiftUI e il display link si ferma quando l'animazione si assesta.
- `NotchPanel.ignoresMouseEvents` è sempre `true`; `NotchHostView.hitTest` restituisce il contenitore invece dei controlli ospitati. I widget attuali non sono quindi una base già funzionante per pulsanti interattivi.
- `NotchState` descrive i lati aperti. Non rappresenta la distinzione fra attività compatta, attività espansa, pagina widget e avviso transitorio.
- `NotchGeometry` lega altezza ed estensione laterale allo stesso progresso: una Live Activity deve invece poter allargare il notch mantenendone l'altezza compatta.
- I widget seguono `activate`/`suspend`. Il futuro monitor degli eventi deve avere una durata indipendente dalla visibilità della pagina.
- L'app usa la configurazione rossa di debug e registra undici orologi dimostrativi. La tranche deve sostituire questa composizione dimostrativa con un esempio verificabile delle nuove capacità.

## Approcci valutati

1. **Estendere il motore attuale e introdurre un coordinatore delle attività — raccomandato.** Conserva geometria, finestra e animazione; separa i servizi di sistema dalla presentazione. Aggiunge soltanto i contratti necessari alla prima tranche.
2. **Implementare Bluetooth e musica come widget normali.** È più breve inizialmente, ma il loro ciclo di vita cesserebbe alla chiusura della pagina e non coprirebbe le superfici compatte persistenti.
3. **Portare il coordinatore di BoringNotch.** Offre esempi di comportamento, ma è accoppiato a numerosi manager e dipendenze. Non risolve direttamente l'override Bluetooth e richiederebbe anche una scelta esplicita sulla copia di sorgenti GPL-3.0.

## Comportamento proposto

### Interazioni e aptica

- L'hover conserva l'apertura attuale e l'isteresi contro le oscillazioni del puntatore.
- I click raggiungono i controlli SwiftUI soltanto dentro la sagoma effettivamente interattiva. Il resto della fascia lascia passare i click alla barra dei menu e alle altre app.
- Il pannello resta non attivante. Questa tranche non richiede la gestione della digitazione nei futuri campi di ricerca.
- Un solo impulso AppKit `.alignment` viene richiesto all'ingresso in hover, prima di avviare il morph. Una permanenza in hover non genera altri impulsi; gli aggiornamenti musicali e gli avvisi automatici non ripetono la vibrazione.
- L'aptica può essere disattivata. La disponibilità effettiva dipende da hardware e preferenze macOS.

### Attività e priorità

- Un contratto pubblico per Live Activities espone identità stabile, contenuti compatti leading/trailing, contenuto espanso e notifiche di cambiamento.
- Uno stato di presentazione separato decide il contenuto visibile; `NotchState` mantiene il significato esistente di apertura dei lati.
- Le attività persistenti restano registrate mentre un avviso transitorio occupa il notch. Alla scadenza torna l'attività corrente, senza ricreare il relativo provider.
- Una selezione manuale già aperta non viene sostituita improvvisamente da un evento: l'avviso resta una presentazione compatta o attende entro una scadenza limitata.
- La prima tranche mostra una sola attività persistente in primo piano. Identità e registrazione devono consentire più attività, ma la selezione visuale fra attività simultanee non entra implicitamente in questo rilascio.
- Per gli avvisi Bluetooth: durata proposta di quattro secondi, coalescenza per dispositivo e coda limitata. Nessuna riproduzione di vecchi eventi al ritorno dalla schermata bloccata.

### Bluetooth

- Monitor tramite callback `IOBluetoothDevice` di connessione e disconnessione; lettura iniziale dei dispositivi già connessi senza mostrarli come nuovi collegamenti.
- Identità stabile del dispositivo per deduplicare le callback. Le riconnessioni rapide vanno accorpate senza ignorare una connessione successiva reale.
- Avviso con nome, categoria/icona e stato. Una batteria sconosciuta rimane assente; nessun valore inventato né scansione periodica con `system_profiler`.
- Un ciclo di vita esplicito rilascia le registrazioni a stop e ricostruisce lo stato dopo sleep/wake senza una raffica di avvisi arretrati.
- La copertura va distinta tra dispositivi Classic esposti da IOBluetooth e periferiche esclusivamente BLE; non si promette un inventario universale dal solo monitor Classic.

### Override degli avvisi nativi

- Definire un'interfaccia di soppressione separata dal monitor: disponibile, autorizzazione necessaria, non supportata, errore.
- Verificare prima la provenienza e il comportamento degli avvisi sul macOS locale, che è **27.0 beta**, poi sulle versioni di rilascio supportate.
- Una chiusura via Accessibilità dopo la comparsa può lasciare un breve lampo del banner: va chiamata chiusura, non soppressione preventiva.
- Privilegiare un intervento selettivo e reversibile sul solo avviso pertinente. Non disabilitare globalmente Notification Center, Focus o i servizi Bluetooth per simulare l'override.
- Quando non è disponibile una sostituzione verificata, esporre lo stato non supportato; non dichiarare il requisito completato. La tecnica esatta resta subordinata alla verifica sul sistema e alla scelta sulle integrazioni private.

### Predisposizione musica

- Definire snapshot immutabili per sorgente, titolo/artista, riproduzione, durata, posizione con timestamp e capacità dei comandi.
- Separare il provider musicale dal contenuto compatto/espanso: metadati e comandi arrivano attraverso il contratto, senza riferimenti al controller del notch.
- Verificare la presentazione con un provider dimostrativo deterministico, attivo soltanto in modalità demo/test e chiaramente identificato.
- La connessione reale a Apple Music, Spotify e browser costituisce il passaggio successivo: la richiesta corrente è interpretata come predisposizione. Il contratto deve consentire un adapter Now Playing senza modificare il renderer.

## Risorse e concorrenza

- Nessun polling periodico per connessioni o metadati, nessun display link attivo a riposo.
- Una sola scadenza cancellabile per l'avviso in primo piano; niente timer per elemento nella coda.
- UI e coordinamento sul main actor. IO, decodifica immagini e operazioni eventualmente bloccanti su worker dedicati.
- Conservare solo snapshot leggeri; creare e rilasciare le viste e le immagini in funzione della presentazione visibile.
- Pubblicare solo variazioni effettive. Separare il progresso musicale dai metadati; un'eventuale progress bar ha aggiornamenti gestiti dall'host e sospesi quando non visibile.
- Avvio e arresto idempotenti, annullamento dei task e nessuna callback capace di riattivare un servizio già fermato.

## Verifica prevista

- Test deterministici per transizioni di presentazione, preemption e ripristino, deduplicazione, scadenze, coda limitata e riavvio.
- Test aptici con performer iniettato: un impulso all'ingresso in hover, nessuno durante la permanenza, aggiornamento automatico o disattivazione.
- Test della geometria compatta e del passaggio fra compatto ed espanso senza perdita della posizione corrente delle molle.
- Test del passaggio degli eventi ai controlli e fuori sagoma, inclusi punti nella bounding box ma fuori dagli angoli arrotondati.
- Build di CascadeKit e dell'app con Xcode locale, mantenendo intatta la modifica preesistente al team di firma.
- Verifica manuale necessaria per vibrazione percepita, click sulla barra dei menu, dispositivi Bluetooth reali, override senza duplicati, sleep/wake, lock, Mission Control e più display.
- Misurare a riposo e durante transizioni: la sola assenza di timer nel codice non dimostra un budget energetico raggiunto.

## Riferimenti esaminati

- [BoringNotch, fork indicato](https://github.com/leekangmmin/boringNotch/tree/e15691026b577caeb721e4ec1865e5a9975e2db1): `ContentView.swift` usa sensory feedback; `NowPlayingController.swift` riceve uno stream da MediaRemoteAdapter e invia comandi tramite MediaRemote. Bluetooth compare ancora nella roadmap, senza un servizio Bluetooth nei sorgenti consultati.
- [BoringNotch originale](https://github.com/TheBoredTeam/boring.notch/tree/99900bf630a3d3e97fae079df2175993318d51f7): struttura analoga per i media; nessuna implementazione Bluetooth trovata nello snapshot consultato.
- [Licenza del fork BoringNotch](https://github.com/leekangmmin/boringNotch/blob/e15691026b577caeb721e4ec1865e5a9975e2db1/LICENSE): GPL-3.0. Questa ricognizione non incorpora sorgenti esterni.
- [Apple: callback di connessione IOBluetooth](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/register(forconnectnotifications:selector:)).
- [Apple: NSHapticFeedbackManager](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager).

## Decisione

L'utente ha confermato la prima tranche e corretto l'aptica all'inizio dell'hover. Le ricerche disponibili non dimostrano ancora una soppressione preventiva universale: l'implementazione deve rendere osservabili i limiti effettivi.
