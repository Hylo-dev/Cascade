# Pagine, selezione contestuale e tre attività

Data: 26 settembre 2026.

Stato: specifica in discussione. Le decisioni della sezione 2 provengono dalle
richieste esplicite dell'utente. Le proposte delle sezioni successive completano
i casi limite e non costituiscono ancora una specifica esecutiva approvata.
Nessuna implementazione applicativa fa parte di questo intervento.

## 1. Obiettivo

Rendere accessibili widget personali, Live Activities e controlli dell'app in uso
attraverso lo stesso notch. Il sistema sceglie una principale per priorità e
rispetta la selezione dell'utente. Le attività restano raggiungibili tramite bolle
e navigazione orizzontale, senza sostituire improvvisamente una pagina aperta.

## 2. Decisioni confermate dall'utente

| ID | Decisione | Vincolo |
| --- | --- | --- |
| D1 | La pagina aperta è protetta dagli eventi automatici. | Nuove attività e cambi di priorità non cambiano di colpo il contenuto in uso. |
| D2 | Il notch presenta fino a tre attività. | Una principale e fino a due bolle, con riferimento alla Dynamic Island di iPhone 18 Pro. |
| D3 | Esiste una Pagina 0 personalizzabile. | È la base del notch; le attività la mettono in secondo piano senza eliminarla. |
| D4 | Pagina 0 è raggiungibile scorrendo da destra verso sinistra. | La navigazione deve conservarne un accesso prevedibile. |
| D5 | La principale viene scelta per priorità oppure dall'utente. | Se l'utente seleziona un'attività nel notch aperto e lo chiude, l'ultima visualizzata diventa principale compatta. |
| D6 | Il focus di un'app può rendere disponibile un'attività contestuale. | Esempi: comandi Photoshop e comandi di un player. |
| D7 | L'hover centrale apre la principale. | Si mantiene la relazione fra corpo compatto e contenuto espanso. |
| D8 | Il clic su una bolla apre direttamente l'attività selezionata. | Questa indicazione sostituisce la precedente proposta di apertura della bolla in hover. |
| D9 | Lo slide sulle bolle ruota le attività compatte. | La bolla entrante si unisce visivamente al notch e diventa principale; le altre si riposizionano. |
| D10 | Una nuova registrazione prevale sulla musica scelta manualmente. | A notch chiuso la registrazione diventa principale e la musica passa in una bolla. A notch aperto continua a valere D1. |

La precedente proposta di riportare sempre la principale alla selezione
automatica dopo la chiusura è superata da D5.

## 3. Riferimento visivo verificato

Apple documenta tre Live Activities simultanee su iPhone 18 Pro e lo swipe per
passare fra attività. La documentazione HIG generale consultata riporta ancora
il precedente caso a due; per il riferimento richiesto usiamo la guida del
modello e il materiale di lancio aggiornato.

- [Apple: guida Dynamic Island](https://support.apple.com/en-by/guide/iphone/iph28f50d10d/ios).
- [Apple: presentazione iPhone 18 Pro, sezione Dynamic Island](https://www.apple.com/newsroom/2026/09/apple-debuts-iphone-18-pro-and-iphone-18-pro-max/).
- [Riferimento visivo pubblicato da MacRumors](https://www.macrumors.com/2026/09/09/iphone-18-pro-features-smaller-dynamic-island/).
- [Immagine delle tre attività osservata nel browser](https://images.macrumors.com/t/15I1H8_5to6Md7Sle3RpeKoL3Qs%3D/400x0/article-new/2026/09/three-live-activities.jpg?lossy=).

L'immagine mostra una capsula principale con una bolla a sinistra e una a destra,
allineate orizzontalmente. Per Cascade adattiamo questa disposizione al taglio
hardware del Mac. L'hardware resta fisso: si muovono le superfici disegnate e i
loro contenuti. La fusione durante la rotazione è un requisito dell'utente;
l'immagine statica non ne dimostra la curva o la durata su iPhone.

Proposta per gli stati compatti:

- Nessuna attività: sagoma di riposo; l'hover apre Pagina 0.
- Una attività: principale intorno al notch, con contenuti sui due lati utili.
- Due attività: principale e bolla destra, conservando la disposizione attuale.
- Tre attività: bolla sinistra, principale, bolla destra.

## 4. Pagine e navigazione — proposta

Pagina 0 conserva identità, disposizione e preferenze fra aperture. Ogni attività
ha una destinazione espansa identificata dalla sessione, indipendente dalla sua
posizione corrente fra principale e bolle. Gli addon contribuiscono widget e
attività attraverso il contratto comune.

Per rendere letterale l'accesso richiesto a Pagina 0, la proposta pone le altre
attività a sinistra della principale e Pagina 0 immediatamente a destra:

    [altre attività] [principale all'apertura] [Pagina 0] [altre pagine personali]

Dalla principale, uno scorrimento del contenuto da destra verso sinistra rivela
Pagina 0; il gesto opposto porta alle altre attività. Le etichette delle pagine
restano stabili anche se cambia la principale. La sequenza viene fissata
all'apertura, così non si riordina sotto il puntatore durante la consultazione.
Sono disponibili anche controlli accessibili per cambiare pagina.

Una nuova attività aggiorna l'insieme disponibile; la nuova disposizione viene
applicata alla chiusura/riapertura. La conclusione della sessione visualizzata
rende immediatamente inerti i suoi comandi. Si propone una breve superficie
«Attività conclusa» mantenuta fino a navigazione o chiusura, evitando un cambio
automatico di pagina mentre il puntatore sta per premere un comando.

Interpretazione proposta di D2: tre sono le attività visibili nel compatto.
Eventuali ulteriori sessioni valide rimangono raggiungibili fra le pagine;
il limite di ammissione del runtime non viene ridotto implicitamente a tre.

Visitare Pagina 0 non la trasforma in una Live Activity e non conclude le attività
in corso. Si propone che chiudere da Pagina 0 conservi l'ultima attività
esplicitamente consultata in quella apertura, se ancora valida; se non ce n'è
una, conserva la principale precedente. Esempio: principale A, visita di B,
visita di Pagina 0, chiusura: la nuova principale è B.

## 5. Selezione automatica e manuale

La selezione mantiene separati:

- la principale compatta;
- la destinazione aperta;
- l'eventuale attività scelta esplicitamente dall'utente;
- le attività ordinate per priorità;
- la sequenza di navigazione della consultazione corrente.

Un semplice hover della principale non costituisce una nuova preferenza manuale.
Un clic sulla bolla o una navigazione esplicita seleziona la destinazione; alla
chiusura l'ultima attività visualizzata diventa principale. Uno slide completato
nel compatto imposta subito la nuova principale senza richiedere un'apertura.

Il riferimento manuale riguarda la sessione: conclusione, revoca o rimozione
definitiva lo invalidano. Una revisione dei contenuti conserva l'identità e non
annulla la scelta. Si propone che chiusure forzate per blocco schermo, stop o
scollegamento display non trasformino un'apertura automatica in preferenza.

### Decisione: nuova registrazione dopo una scelta manuale

Scenario: l'utente sceglie Musica, chiude il notch e poi avvia una registrazione.

L'utente ha scelto la precedenza al nuovo evento: la registrazione diventa
principale e Musica passa nella bolla laterale. È scartata l'alternativa che
manteneva Musica principale fino alla fine della sua sessione.

La regola generale proposta è: una nuova sessione con priorità maggiore supera
la scelta manuale precedente quando il notch è chiuso. Aggiornamenti ordinari,
cambio brano e ripubblicazioni della stessa sessione non sono nuovi eventi.
L'utente può selezionare nuovamente Musica dopo l'arrivo della registrazione:
la scelta vale fino al prossimo evento che soddisfa la regola.

Se la registrazione inizia con il notch aperto, D1 protegge la pagina corrente.
Come completamento del comportamento, si propone di applicare la precedenza
alla chiusura, salvo una nuova selezione manuale effettuata dopo l'arrivo
dell'attività. La semplice permanenza sulla pagina non conta come nuova scelta.

L'ordine automatico iniziale resta una proposta: registrazione/condivisione,
chiamata, comandi dell'app con focus, media e altre attività. La precedenza fra
registrazione e chiamata simultanee va ancora concordata. A parità di priorità
si conserva l'ordine precedente per evitare oscillazioni. Gli addon dichiarano
il proprio contesto; l'host assegna la precedenza finale.

## 6. Clic, slide e animazione — proposta

Si propone di supportare sia il trascinamento orizzontale della bolla con il
puntatore sia lo scorrimento orizzontale del trackpad sopra l'area compatta.
Entrambi attraversano lo stesso riconoscimento del gesto; le soglie si tarano
sul prototipo di interazione, senza intercettare lo scorrimento fuori dal notch.

Il clic viene riconosciuto al rilascio se il movimento non supera la soglia del
gesto. Lo slide riconosciuto annulla il clic e l'hover di apertura per tutta la
rotazione, compreso il passaggio del puntatore sulla zona centrale.

La bolla selezionata si avvicina al corpo, crea un breve raccordo liquido e vi
confluisce. La principale uscente diventa una bolla; la terza attività completa
la rotazione. Il gesto opposto inverte il verso. La posizione logica viene
confermata al completamento del gesto; un gesto annullato torna alla disposizione
precedente. Dopo il gesto si richiede un nuovo ingresso nella zona centrale per
aprire, così lo slide non provoca un'apertura involontaria.

Una sessione revocata durante il movimento non può tornare attiva al completamento
dell'animazione. Riduci movimento conserva il risultato con transizione minima.
Geometria, maschera e zone cliccabili seguono la stessa posizione. Nessun timer
di animazione rimane attivo a transizione conclusa.

Nel notch aperto lo scorrimento delle pagine deve lasciare ai controlli interni
i gesti iniziati su slider e altre superfici interattive. La rotazione compatta
e la navigazione espansa condividono le identità, ma hanno gesti distinti.

## 7. Attività contestuali dell'app — proposta

Il focus rende eleggibile una superficie dichiarata dall'integrazione:
Photoshop può offrire strumenti rapidi, un player i comandi del contenuto in uso.
La sola presenza di un'app installata o aperta in background non la attiva.

Le superfici contestuali partecipano alla stessa selezione e, come proposta,
allo stesso limite di tre posizioni compatte. Non costituiscono una quarta bolla.
La loro eleggibilità dipende dal contesto, mentre una chiamata o registrazione
continua a esistere anche se l'app perde il focus.

Durante una consultazione la superficie conserva la propria app sorgente.
Il notch non deve rubarle il focus. Se il bersaglio cambia o scompare, i comandi
non vengono dirottati alla nuova app: restano validi soltanto se l'integrazione
sa indirizzarli e verificarli sul bersaglio originale; altrimenti si disabilitano.
Il contesto successivo si applica alla successiva consultazione.

Le capacità di rilevamento e controllo restano verifiche separate per
registrazione di sistema, Meet, FaceTime, Discord e ciascuna nuova integrazione.
Uso di microfono/camera, identità della chiamata e stato mute non sono equivalenti.

## 8. Inserimento nella struttura attuale

- `LiveActivityHost` conserva sessioni, scadenze e lifecycle. La selezione attuale
  espone principale/secondaria e una destinazione espansa; serviranno tre
  posizioni compatte e una scelta manuale indipendente dalla priorità.
  Oggi viene ammessa nel compatto una sola attività per `sourceID`: la gestione
  di due sessioni distinte della stessa app rimane da definire, senza confonderla
  con il limite di tre posizioni visibili.
- `WidgetHost` e `NotchScreen` contengono già disposizione e identità dei widget.
  Servono navigazione reale, persistenza della Pagina 0 e sospensione delle sole
  viste che escono dalla pagina, senza duplicare le istanze.
- `NotchDisplayCoordinator` mantiene un solo notch aperto e distribuisce le
  stesse identità sui display secondo le preferenze esistenti.
  Attualmente `reconcilePresentations()` riallinea la vista aperta in hover alla
  principale corrente: questo comportamento deve lasciare il posto alla
  destinazione scelta una volta all'apertura e poi conservata fino a navigazione
  esplicita o conclusione della sessione.
- `NotchController`, geometrie e renderer gestiscono entrambe le bolle e il
  riconoscimento clic/slide. La fusione durante la rotazione richiede una
  transizione dedicata: oggi i cambi di identità passano dalla sagoma base.
- `AddonPresentationBridge` riceve contesto e capacità validati dall'host.
  Widget interni ed esterni continuano a usare gli stessi contratti.
- Il monitor del focus dispone già di PID e bundle ID dell'app esterna, ma il
  contratto della finestra pubblica solo il rettangolo. Si estende quel percorso
  per conservare il bersaglio dei comandi, evitando un secondo monitor.

La scelta si ricalcola sugli eventi rilevanti, fuori dal ciclo di animazione.
Le viste nascoste rilasciano risorse; una pagina nascosta non conclude la sessione.

## 9. Sequenza proposta per il successivo piano esecutivo

1. Confermare navigazione, interpretazione del limite visivo e proposta delle
   impostazioni. D10 chiude il caso registrazione dopo Musica scelta manualmente.
2. Definire e verificare selezione, identità delle pagine e ritorni alla chiusura.
3. Aggiungere Pagina 0 persistente e navigazione fra superfici.
4. Estendere il compatto a tre attività, clic delle bolle e rotazione con fusione.
5. Collegare le attività delle app con focus e verificare gli adattatori reali.

Scenari di accettazione: nessuna attività; musica; registrazione più musica;
registrazione più chiamata più musica; quarta attività; nuova sessione durante
consultazione; scelta manuale e riapertura; visita di Pagina 0; fine della
sessione selezionata; cambio focus; slide annullato; revoca durante animazione;
conflitto con slider musicale; Riduci movimento; blocco, risveglio e più display.

## 10. Impostazioni — proposta da discutere

### Struttura

Le impostazioni attuali usano una barra laterale con `Appearance`, `Dev` e
`Widget`, form SwiftUI raggruppati e ricerca trasversale. Si propone una sola
nuova destinazione e la riorganizzazione dei contenuti esistenti:

| Pagina | Contenuto |
| --- | --- |
| Aspetto | Geometria, stile e schermi, aptica e privacy già esistenti. |
| Pagine e widget | Sostituisce Widget: Pagina 0, altre pagine personali e disposizione dei widget. |
| Attività | Priorità, attività visibili, integrazioni e comandi legati all'app con focus. |
| Dev | Anteprime tecniche esistenti e versione. |

Gli avvisi Bluetooth, volume e ricarica restano in un gruppo «Avvisi» distinto
nella pagina Attività; non entrano nella graduatoria delle Live Activities.
Il controllo Spotlight mantiene un gruppo «Ricerca». Musica e visualizzatore
si spostano nel dettaglio Musica. Ogni preferenza ha una sola collocazione,
raggiungibile anche dalla ricerca.

### Pagine e widget

Una lista di pagine affianca l'anteprima della pagina selezionata. Pagina 0 è
sempre disponibile e non eliminabile. L'utente può aggiungere, rimuovere,
spostare e ridimensionare i suoi widget usando le dimensioni supportate.
L'editor permette anche di creare, rinominare e riordinare altre pagine personali;
le superfici delle attività rimangono gestite dal loro contesto.

«Aggiungi widget…» mostra quelli effettivamente forniti dalle integrazioni
disponibili, con nome e app sorgente. La modifica della griglia avviene in una
modalità esplicita «Personalizza» con pulsante «Fine»; spostamenti e dimensioni
sono disponibili anche da tastiera. Posizioni occupate o fuori griglia non
sovrascrivono altri widget: il rilascio non valido torna alla posizione iniziale.

Pagina vuota: anteprima con «Aggiungi il tuo primo widget». Un widget il cui
addon è temporaneamente indisponibile conserva il posto con indicazione della
sorgente, senza perdere la disposizione salvata.

### Attività: comportamento e priorità

- **Attività visibili:** scelta 1, 2 o 3, predefinito 3. Riguarda il compatto;
  le attività eccedenti restano consultabili nelle pagine. Questa opzione dipende
  dalla conferma dell'interpretazione del limite visivo della sezione 4.
- **Ordine di priorità:** elenco riordinabile dei tipi di attività. Proposta
  iniziale: registrazione/condivisione, chiamate, app in uso, musica, altre
  attività. L'ordine scelto si usa per le nuove selezioni automatiche; i nomi
  sostituiscono punteggi numerici esposti all'utente.
- Una descrizione stabile spiega: «L'ultima attività scelta resta principale
  finché ne inizia una con priorità maggiore. La pagina aperta resta invariata».
- **Ripristina priorità predefinite:** agisce solo sull'ordine, senza resettare
  pagine, integrazioni o preferenze degli schermi.

Il valore predefinito rispetta D10. Un riordino esplicito nelle impostazioni è
una personalizzazione dell'ordine automatico, non una modifica involontaria
causata da aggiornamenti degli addon. La protezione della pagina aperta resta
una regola stabile, senza interruttore per disabilitarla.

Queste personalizzazioni proposte hanno effetti espliciti: scegliendo una sola
attività visibile, la musica passa nelle pagine anziché in una bolla; ponendo
Musica sopra Registrazione, una nuova registrazione non la supera automaticamente.
L'anteprima e il testo accanto ai controlli devono mostrarlo. La possibilità di
alterare il comportamento predefinito in questo modo è parte della proposta
delle impostazioni e non viene attribuita alla conferma di D10.

### Integrazioni e comandi delle app

Un elenco mostra ogni integrazione con nome, interruttore e stato pertinente:
disattivata, disponibile senza sessione corrente, attiva oppure permesso mancante.
L'assenza di una chiamata non rende indisponibile la configurazione delle chiamate.
Il dettaglio contiene solo le opzioni specifiche della sorgente, i permessi
necessari e le azioni realmente supportate.

Nel gruppo «App in uso» le associazioni sono righe leggibili, per esempio:

    Photoshop → Comandi rapidi        Attiva
    Player → Controlli riproduzione   Attiva

«Attiva» è uno stato dell'associazione, non un secondo interruttore. La riga apre
la configurazione; l'attivazione resta quella unica dell'integrazione.

«Aggiungi app…» permette di associare un'app a un widget contestuale compatibile.
Il dettaglio permette di scegliere e ordinare i comandi offerti dall'integrazione.
Il focus rende eleggibile la superficie; l'ordine di priorità decide se sarà
principale o secondaria. Scegliere un'app non inventa un'integrazione: se non
esiste un widget compatibile viene indicato, senza mostrare controlli fittizi.

Per la prima versione si propone una sola attivazione per integrazione, senza
interruttori separati per pagina, bolla e promozione automatica. L'ordine delle
priorità rimane comune; eventuali eccezioni per singola app richiederanno un
caso concreto prima di introdurre un secondo livello di regole.

### Anteprima, gesti e applicazione delle modifiche

La pagina Attività include una piccola anteprima interattiva con dati dimostrativi:
musica; registrazione più musica; tre attività; comandi dell'app in uso. Mostra
come cambiano principale e bolle al riordino delle priorità. Il pulsante
«Simula nuova registrazione» verifica anche il caso D10 senza avviare registrazioni
reali o inviare comandi alle app.

Una legenda illustra hover centrale, clic sulle bolle, slide e accesso a Pagina 0.
I gesti mantengono una mappatura unica; aptica e movimento ridotto seguono le
preferenze già esistenti e quelle di sistema. Non si aggiungono regolazioni
numeriche di molle o velocità nella pagina Attività.

Le impostazioni ordinarie si salvano automaticamente e aggiornano l'anteprima.
Ordine e disposizione entrano nel notch al successivo stato compatto, mantenendo
la protezione della pagina aperta. Disabilitare un'integrazione revoca subito
i suoi comandi e contenuti, secondo la gestione della sessione conclusa.
Le scelte di contenuto e priorità sono globali; stile e calibrazione rimangono
per display, e la destinazione delle attività usa il routing già esistente.

La ricerca deve trovare anche pagine, widget, app e opzioni dei dettagli, e
aprire il controllo pertinente. Una lista vuota di integrazioni o associazioni
spiega come aggiungere un contenuto disponibile. Un permesso mancante propone
l'azione specifica vicino alla sorgente interessata.
