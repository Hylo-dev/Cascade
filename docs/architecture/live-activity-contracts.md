# Contratti per attività e avvisi del notch

Riferimento di design: [Apple HIG — Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities), consultato l'8 settembre 2026.

Le indicazioni pertinenti sono presentazioni compatta/minima/estesa coerenti,
leggibilità, contenuti essenziali, privacy, interazioni dirette, aggiornamenti
discreti e conclusione del task. Cascade applica questi principi al proprio
overlay macOS. Le Live Activities native descritte da Apple su Mac provengono
da iPhone; questi protocolli non conformano ad ActivityKit.

## Evoluzione verso il sistema addon

Dal 9 settembre 2026 la destinazione approvata è il [sistema addon comune](../superpowers/specs/2026-09-09-addon-runtime-design.md), con [piano esecutivo e migrazione](../superpowers/plans/2026-09-09-addon-runtime.md). Tutti i futuri widget, avvisi e attività del team usano lo stesso SDK, manifest, servizi autorizzati, processi e budget degli addon esterni.

I protocolli descritti sotto documentano il motore e il comportamento attuali. Nella nuova architettura vengono implementati dal bridge generico dell'host, mentre gli addon pubblicano descrizioni e azioni attraverso l'SDK. Una pubblicazione valida può rimanere senza processo provider; la vista remota avanzata e i servizi hanno concessioni distinte. La migrazione preserva le regole visive, temporali, di privacy e accessibilità descritte qui. Questa nota non dichiara la migrazione già eseguita.

## Scelte del contratto Cascade

| Contratto | Responsabilità |
| --- | --- |
| `NotchActivity` | Identità della sessione/sorgente, revisione, etichetta accessibile, privacy, destinazione, dimensioni desiderate e factory compatte/minima. |
| `NotchLiveActivity` | Task in corso, `lifetime` finita, rilevanza relativa e factory estesa riservata alle attività. Pubblicazione con `present(_:)`, conclusione con `endActivity(id:)`. |
| `NotchTransientNotice` | Singolo cambio di stato; durata esplicita e pubblicazione con `showNotice(_:)`. Non può diventare persistente per un parametro dimenticato. |
| `NotchActivityViewContext` | Famiglia scelta, spazio utilizzabile in punti del Mac, indicazione di contenuto non aggiornato. |
| `LiveActivityContext` | Invalidazione della sola presentazione visibile. Il provider resta indipendente dalla vista. |

Le Live Activities implementano tutte le factory, compresa `makeMinimalView`.
Gli avvisi non espongono `makeExpandedView`: il protocollo riserva questa factory
alle attività in corso. Un avviso usa entrambe le ali compatte, temporaneamente
al posto delle Live Activities, e il più recente ha precedenza.
`sourceID` raggruppa una stessa integrazione. Con due sorgenti distinte e nessun
avviso, la principale mantiene il contenuto compatto sinistro e chiude l'ala destra.
La seconda usa la propria factory `makeCompactLeadingView` in un cerchio separato
a destra, con diametro pari all'altezza del notch e inset simmetrici. L'hover apre
la principale; il clic sul cerchio apre la seconda con un aggancio a goccia alla
sagoma. L'attivazione accessibile usa lo stesso percorso del clic. La factory
minima resta parte del contratto per le altre presentazioni.

Una revisione cambia soltanto con i dati visualizzati. Il coordinatore filtra le
ripubblicazioni della stessa istanza/revisione. Metadati e scadenze modificati
mentre la vista è sospesa devono comunque essere ripubblicati attraverso il motore.
Le invalidazioni provenienti da un vecchio contesto diventano inerti.

La durata massima di una sessione è otto ore e quella di un avviso dieci secondi:
sono politiche locali di Cascade. L'avviso Bluetooth usa quattro secondi.
Il limite della sessione si ancora alla prima ammissione/inizio, quello precedente:
aggiornare `startedAt` o la stima di fine non sposta il limite. Un task nuovo va
pubblicato come nuova sessione; non si rinnova automaticamente un task scaduto.
La sessione può diventare obsoleta prima della scadenza tramite `staleDate`; il
renderer lo segnala. Una sola scadenza cancellabile gestisce l'intera raccolta.
Il task concluso scompare subito anche se esteso. Un avviso scompare quando si
entra in hover: l'apertura mostra una Live Activity disponibile oppure i widget.
Gli avvisi ricevuti durante l'espansione o il blocco dello schermo vengono
scartati e non vengono riproposti alla chiusura o allo sblocco.

La chiusura di un pannello rilascia le sue viste estese e raggiunge esattamente
la sagoma base; non sospende da sola il provider condiviso. `LiveActivityHost`
attiva ciascuna istanza prima delle factory locali e la mantiene attiva finché
esiste almeno una presentazione valida, comprese le radici trattenute durante una
transizione. La sospensione avviene dopo l'ultima presentazione; conclusione,
scadenza o revoca invalidano anche le radici uscenti, senza risuscitare la sessione.
Al primo attraversamento della misura base, il frame successivo avvia le ali
compatte. Le molle superano leggermente la misura finale in apertura; il canvas
fisso riserva spazio al rimbalzo. Il display link si ferma dopo la transizione.
Un nuovo hover può interrompere una normale chiusura.

La sostituzione dell'identità principale o secondaria passa sempre dalla sagoma
base prima di costruire le nuove viste. Eventi e hover durante la chiusura
aggiornano la destinazione della successiva apertura senza anticiparla. Le
revisioni della stessa sessione non ripetono questa sequenza. Movimento ridotto
raggiunge direttamente lo stato finale e rilascia anche la vista della goccia.

Dopo un clic, l'area di permanenza cresce e tollera una breve uscita del puntatore.
I controlli che aprono un menu esterno usano `NotchPopoverPresenter`, registrando
l'interazione prima delle richieste asincrone e chiudendola in `dismantleNSView`.
Il popover conserva le dimensioni intrinseche; notch, finestra del popover e un
corridoio stretto fra i due mantengono aperta l'interazione. L'uscita completa
chiude il menu dopo una breve tolleranza cancellabile, anche a puntatore fermo.
Non sono necessari polling o ricerche globali delle finestre.

`privacy` va dichiarata esplicitamente. Se è `.sensitive`, il renderer usa un
contenuto innocuo prima ancora di invocare le factory, salvo consenso nelle
preferenze. Anche etichette accessibili e destinazioni devono rispettare questa
scelta. Il provider rimane responsabile della corretta classificazione dei dati.

`contentURL`, quando disponibile, porta ai dettagli reali della sessione ed è
unica per entrambi i lati compatti. L'anteprima musicale non inventa una
destinazione verso un player. L'altezza estesa deriva dal contenuto dichiarato e
viene limitata dal renderer; le viste rispettano `availableSize` e gli inset.
Le dimensioni predefinite e il fondo scuro appartengono al motore, non ai provider.
La larghezza estesa predefinita è 408 punti, con margini rispetto al display;
l'altezza include spazio per il taglio fisico e inset, fino a 180 punti. Il motore
applica il tema scuro anche quando macOS usa il tema chiaro.
La curvatura della sagoma deriva dal path Apple `RoundedRectangle(.continuous)`,
normalizzato e memorizzato una volta. Gli stessi segmenti governano disegno,
maschera e hit testing, con riflessione per gli attacchi concavi superiori.

`compactPreferredSideWidth` permette a un avviso di richiedere ali più larghe
(116 punti per volume e Bluetooth); il renderer normalizza e limita la richiesta
al display. La larghezza viene animata in punti e i getter del provider non
vengono chiamati a ogni frame. I contenuti sensibili nascosti non influenzano
neppure questa dimensione.

## Presentazione su più display

`NotchEngine` espone la facciata del `NotchDisplayCoordinator`: un inventario,
un monitor degli eventi, un monitor della finestra attiva, un `LiveActivityHost`
e un `WidgetHost` condivisi. Ogni desktop logico ha un controller e un pannello
stabili; il cambio del focus aggiorna le proiezioni senza ricreare i pannelli.
La sagoma compatta esiste anche senza attività. Il mirroring viene normalizzato
tramite la topologia CoreGraphics, senza dedurre l'identità dal nome o dal frame.

La selezione compatta principale/secondaria è indipendente dall'attività estesa:
aprire su A non elimina le copie compatte o il satellite su B. Le preferenze
permettono tutti i display, la finestra attiva (default) oppure un display fisso.
Il focus usa la finestra attiva, poi il puntatore e infine il display principale;
un cambio di finestra nella stessa app è un evento utile. Le coordinate AX sono
convertite prima del routing, fuori dal ciclo di animazione. Una destinazione
fissa scollegata non viene sostituita: al ritorno dello stesso UUID riappare solo
la pubblicazione ancora valida. Senza UUID il display partecipa a tutti/focus,
ma non diventa una destinazione fissa persistente.

Una sola superficie ottiene l'apertura. Il coordinatore aspetta il completamento
reale della chiusura precedente e verifica generazione, trigger e presenza del
display prima di concedere la richiesta valida più recente. L'uscita del mouse
può annullare un hover in attesa senza cancellare una precedente richiesta
esplicita valida. Fuori dal routing si aprono i widget. Un'attività già aperta
resta sul suo display se si sposta soltanto il focus; un cambio esplicito della
preferenza che esclude quel display la richiude.

Gli avvisi sono cambi di stato brevi, non copie delle Live Activities: seguono
solo il display attivo, conservando la scadenza originale. Espansione, blocco e
prenotazione di Spotlight ne impediscono l'accodamento per una riproduzione
successiva. Impostazioni e superfici ausiliarie mantengono l'ancora di invocazione;
una finestra Impostazioni visibile ma non attiva non riserva da sola l'apertura.
Popover, trascinamento e prenotazioni delle superfici native partecipano alla
stessa esclusività. Il blocco invalida richieste pendenti prima della pulizia
applicativa; stop rilascia monitor, pannelli e presentazioni condivise.

Sui display senza taglio fisico, `SoftwareNotchMetrics` separa la sporgenza di
riposo **96 × 8 pt**, l'altezza compatta **32 pt** e lo spazio centrale **24 pt**.
Gli stili Notch e Dynamic Island sono selezionabili per display; il secondo
collega il corpo alla sporgenza con collo di **12 pt** e offset di **8 pt**.
Il corpo include lo spazio dell'offset senza sottrarlo ai contenuti. Lo spazio di esclusione
del taglio hardware è zero su questi display.
La scelta persistente usa UUID; senza UUID dura solo fino a disconnessione/stop.
Il cambio stile aspetta la chiusura. Le calibrazioni hardware restano in uso,
mentre le vecchie misure software non ingrandiscono la sporgenza; la calibrazione
è disponibile solo per un bersaglio hardware. Disegno, maschera e hit testing
usano lo stesso path, anche nella variante Riduci trasparenza.

Il lifecycle conta istanze e presentazioni effettive, non una sottoscrizione per
monitor. La scadenza appartiene all'host comune: `scheduleExpiration()` sceglie
il prossimo termine fra stale/expiry e mantiene un solo `deadlineTask`
cancellabile. È una proprietà del sorgente, non una misura di scheduling nativo.
Il [verbale di verifica](../superpowers/verification/2026-09-24-multi-display-notch.md)
distingue i test con inventari sintetici dalle prove fisiche e dal profiling
ancora non eseguito.

## Regole per chi implementa un modulo

- Aggregare aggiornamenti della stessa sessione. Non generare un oggetto nuovo
  per ogni frame, tick o identico callback del sistema.
- Tenere scansioni, richieste di rete, decodifica e callback di framework fuori
  dalle factory e dal percorso di animazione; attraversare esplicitamente gli actor.
- Rilasciare le risorse della vista in `suspend()`. Il progresso visivo musicale
  può aggiornarsi soltanto mentre la relativa vista estesa è visibile e in play.
- Esporre un comando per disattivare l'integrazione. La rimozione per `sourceID`
  deve eliminare sia la presentazione attiva sia gli elementi in attesa.
- Riservare i controlli estesi alle azioni essenziali. La musica espone play/pausa;
  il contratto del provider conserva i comandi aggiuntivi per altre superfici.
- Usare simboli e testo leggibili, etichette accessibili e informazioni coerenti
  tra famiglie. Bluetooth mostra modello/nome a sinistra e stato con carica circolare a destra,
  con troncamento del nome e testo accessibile completo. La carica ignota resta
  indisponibile; il minimo dei due auricolari non viene sostituito dalla custodia.
- Non aggiungere suoni o aptica alle normali revisioni, né duplicare l'evento
  tramite una seconda notifica applicativa.

## Confini dell'adattamento

Il notch locale non implementa Lock Screen, StandBy, CarPlay, Apple Watch,
iPhone Mirroring o push ActivityKit. A schermo bloccato l'overlay si nasconde.
La seconda attività può occupare un cerchio separato dalla sagoma, con la stessa
maschera e gli stessi limiti di interazione del renderer. Le interazioni usano
hover, clic, attivazione accessibile e link espliciti macOS. La conformità estetica dei futuri contenuti richiede comunque
revisione visiva; nessun protocollo può impedire da solo testo promozionale o una
classificazione errata dei dati.

L'override dei banner Bluetooth rimane un servizio separato e selettivo. Questi
contratti non ne dimostrano la compatibilità con l'albero Accessibilità del sistema.
Il ritorno dell'uscita audio alle AirPods è distinto da una nuova connessione
ACL: il listener CoreAudio genera un avviso anche se il link è rimasto collegato,
con baseline silenziosa all'avvio e dopo il risveglio. Gli avvisi Bluetooth
mostrano solo modello/simbolo e anello, mentre nome e stato restano disponibili
tramite accessibilità e help localizzati. La parte residua dell'anello è verde
attenuata con tratto più sottile dell'arco carico.

Il volume usa un avviso di 1,8 secondi: icona e testo a sinistra, indicatore di
livello e percentuale a destra. La barra è un indicatore, come nell'HUD di
riferimento, non un controllo trascinabile. CoreAudio osserva l'uscita predefinita
senza polling; un event tap selettivo sostituisce i tasti volume solo quando può
gestirli. Accessibilità mancante o dispositivi a livello fisso mantengono il
comportamento nativo. Non vengono disattivati globalmente gli altri HUD macOS.


Gli aggiornamenti asincroni di un avviso già presentato usano `updateNotice`,
con la stessa identità/sorgente e una revisione strettamente crescente. Conservano
scadenza e priorità; non reinseriscono contenuti dopo hover, scadenza o chiusura.
`showNotice` resta riservato a un nuovo evento reale (per esempio un altro passo
volume). Bluetooth verifica anche l'identità del singolo evento di connessione
prima di aggiornare e arma l'override nativo una sola volta.

Gli avvisi AirPods usano i video originali dei banner Apple installati in macOS.
Il catalogo CoreBluetoothUI associa PID e colore alle immagini e agli alias;
BluetoothUIService fornisce il filmato corrispondente. Cascade legge le risorse
a runtime, senza copiarle nel bundle. Un worker decodifica al massimo 48 immagini
da 96 pixel per un giro di tre secondi. Movimento ridotto usa un fotogramma
statico; non rimangono player o timer dopo la chiusura della vista.
La lettura dei metadati avviene fuori dal main actor alla connessione, con un solo
retry, e i risultati cancellati o appartenenti a connessioni precedenti si scartano.

Il filtro volume si ricrea al risveglio e al ritorno della sessione. Un tap
disabilitato dal sistema può tentare un solo ripristino ogni cinque secondi,
solo su evento e con Accessibilità valida. I repeat di mute sono assorbiti senza
nuove scritture o feedback. Il ritorno all'app/menu riprova un permesso appena
concesso; non si modificano le impostazioni di FineTune né i permessi macOS.

Le variazioni di Accessibilità vengono osservate anche a menu chiuso; il
segnale di sistema viene accorpato e seguito da una verifica reale del permesso.
Il ritorno dalle Impostazioni costituisce un percorso aggiuntivo, senza polling.
La build Debug usa Apple Development: una firma ad hoc diversa a ogni build
non offre un’identità stabile a cui macOS possa associare il consenso.

La ricarica usa un avviso di quattro secondi al passaggio da batteria ad
alimentatore. IOKit osserva la sola batteria interna; percentuale e modalità di
risparmio energetico aggiornano l'avviso esistente senza prolungarlo. Avvio e
risveglio stabiliscono una baseline silenziosa. Il distacco chiude l'avviso.
Testo e batteria piena arrotondata rispettano il riferimento: verde in modalità
normale, giallo con risparmio energetico, compresa la sfumatura sotto il bordo.
La sfumatura si disattiva con Riduci trasparenza. Ricarica sospesa e completa
hanno etichette distinte; una percentuale sconosciuta non diventa uno zero.
Il menu permette di disattivare l'integrazione e vedere entrambe le anteprime.

La modalità compatta usa SF nello stile macOS Callout (12 pt, regular), come
definito nelle [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography).
Le [HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
richiedono margini concentrici alla sagoma, senza fissare un padding numerico
universale per un notch macOS personalizzato. Cascade li adatta alla propria
geometria: 12 pt verso il bordo esterno, 8 pt verso il taglio e 6 pt verticali.
Le presentazioni minime usano 12 pt su entrambi i lati. Il motore sottrae gli
inset prima di passare lo spazio ai provider; icone e immagini rispettano anche
la larghezza residua. La batteria usa 12 pt di altezza, i simboli 14 pt e gli
anelli Bluetooth al massimo 18 pt. La tipografia non cambia con l'altezza del
notch e l'eventuale riduzione dei testi non scende sotto i 10 pt.
